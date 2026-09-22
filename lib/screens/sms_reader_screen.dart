import 'package:flutter/material.dart';
import 'package:another_telephony/telephony.dart' hide SmsFilter;
import '../db/database_helper.dart';
import '../models/transaction.dart';
import '../utils/sms_parser.dart';
import '../utils/sms_filter.dart';
import '../utils/slice_balance.dart';
import '../utils/category_helper.dart';
import '../utils/duplicate_helper.dart';
import '../utils/needs_review_store.dart';
import 'add_transaction_screen.dart';
import 'needs_review_screen.dart';

class SmsReaderScreen extends StatefulWidget {
  const SmsReaderScreen({super.key});

  @override
  State<SmsReaderScreen> createState() => _SmsReaderScreenState();
}

class _SmsReaderScreenState extends State<SmsReaderScreen> {
  final Telephony telephony = Telephony.instance;

  // Category list offered when adding a transaction from a needs-review
  // SMS. As of Day 18 this is derived from the real transaction table via
  // categoriesFrom() — the same helper main.dart uses — instead of a
  // hardcoded local list, so it stays in sync with the app's actual
  // categories. "Other" remains available as a fallback via the form itself.
  List<String> _existingCategories = const ['All'];

  List<SmsMessage> _messages = [];
  bool _loading = false;
  bool _permissionDenied = false;

  int _autoAddedCount = 0;
  int _skippedAlreadyProcessed = 0;
  final List<SmsParseResult> _needsReview = [];

  @override
  void initState() {
    super.initState();
    _requestPermissionAndLoad();
  }

  Future<void> _loadExistingCategories() async {
    final allTransactions = await DatabaseHelper.instance.getAllTransactions();
    if (!mounted) return;
    setState(() {
      _existingCategories = categoriesFrom(allTransactions);
    });
  }

  Future<void> _requestPermissionAndLoad() async {
    setState(() {
      _loading = true;
      _permissionDenied = false;
    });

    final bool? granted = await telephony.requestPhoneAndSmsPermissions;

    if (granted != true) {
      setState(() {
        _loading = false;
        _permissionDenied = true;
      });
      return;
    }

    await _loadExistingCategories();
    await _loadMessages();
  }

  Future<void> _loadMessages() async {
    setState(() => _loading = true);

    final List<SmsMessage> messages = await telephony.getInboxSms(
      columns: [
        SmsColumn.ADDRESS,
        SmsColumn.BODY,
        SmsColumn.DATE,
      ],
      sortOrder: [
        OrderBy(SmsColumn.DATE, sort: Sort.DESC),
      ],
    );

    setState(() {
      _messages = messages;
      _loading = false;
    });

    await _parseAndInsertTransactions(messages);
  }

  // Day 28: first-pass filter now lives in lib/utils/sms_filter.dart so
  // promos, OTPs, due reminders etc. are rejected before parsing.
  // (another_telephony also exports a class named SmsFilter, so it is
  // hidden in the import above to avoid a name clash.)
  bool _looksLikeTransactionSms(SmsMessage msg) {
    return SmsFilter.looksLikeTransaction(
      sender: msg.address ?? '',
      body: msg.body ?? '',
    );
  }

  /// Runs every flagged SMS through SmsParser, skipping any SMS whose
  /// hash is already in processed_sms. Successful parses that don't match
  /// an existing transaction are auto-inserted and marked processed
  /// immediately. Successful parses that DO match an existing transaction
  /// (same amount/type/day) are diverted into Needs Review instead of
  /// silently auto-inserting a likely duplicate — the user decides there.
  /// Day 28: Slice SMS are never auto-inserted; every one waits in Needs
  /// Review for the user's OK (only earlier Slice entries count as "similar").
  /// True failures are collected into [_needsReview] as before. Neither
  /// diverted duplicates nor true failures are marked processed — an
  /// unresolved needs-review SMS must keep reappearing on every refresh
  /// until the user actually saves a transaction for it (see
  /// [_openNeedsReviewItem]) or explicitly dismisses it (see
  /// [_dismissNeedsReviewItem]), otherwise it gets silently marked "done"
  /// and vanishes without ever being resolved.
  Future<void> _parseAndInsertTransactions(List<SmsMessage> messages) async {
    final flagged = messages.where(_looksLikeTransactionSms).toList();

    int autoAdded = 0;
    int skipped = 0;
    final List<SmsParseResult> reviewList = [];

    for (final msg in flagged) {
      final hash = DatabaseHelper.smsHash(
        sender: msg.address ?? '',
        body: msg.body ?? '',
        dateMillis: msg.date,
      );

      final alreadyProcessed = await DatabaseHelper.instance.isSmsProcessed(hash);
      if (alreadyProcessed) {
        skipped++;
        continue;
      }

      final result = SmsParser.parse(
        sender: msg.address ?? '',
        body: msg.body ?? '',
        dateMillis: msg.date,
      );

      if (result.isSuccess) {
        final txn = result.transaction!;
        final duplicates = await DatabaseHelper.instance.findPotentialDuplicates(
          amount: txn.amount,
          type: txn.type,
          date: txn.date,
        );

        // Slice always asks first, and is only compared with other Slice
        // entries so a same-amount payment from another app isn't flagged.
        final askFirst = isSliceSource(txn.source);
        final similar = askFirst
            ? duplicates.where((t) => isSliceSource(t.source)).toList()
            : duplicates;

        if (similar.isNotEmpty || askFirst) {
          reviewList.add(SmsParseResult.failure(
            similar.isNotEmpty
                ? 'Possible duplicate of an existing transaction (same '
                    'amount, type, and date)'
                : 'Slice payment: waiting for your OK',
            result.rawBody,
            result.sender,
            partialAmount: txn.amount,
            partialType: txn.type,
            partialMerchant: txn.title,
            bankName: txn.source,
            smsDate: txn.date,
          ));
        } else {
          await DatabaseHelper.instance.insertTransaction(txn);
          await DatabaseHelper.instance.markSmsProcessed(hash);
          autoAdded++;
        }
      } else {
        reviewList.add(result);
      }
    }

    if (!mounted) return;
    setState(() {
      _autoAddedCount = autoAdded;
      _skippedAlreadyProcessed = skipped;
      _needsReview
        ..clear()
        ..addAll(reviewList);
    });
    // Keep the cross-screen store in sync so main.dart's "+" add flow and
    // the Needs Review page can see what's currently pending here.
    NeedsReviewStore.instance.setAll(_needsReview);

    // New categories may have been introduced by auto-added transactions
    // (e.g. a new merchant keyword match) — refresh so the needs-review
    // dropdown reflects them too.
    if (autoAdded > 0) {
      await _loadExistingCategories();
    }
  }

  /// Builds a draft Transaction from whatever partial data the parser
  /// recovered, to prefill AddTransactionScreen. Amount defaults to 0
  /// (fails form validation until the user enters a real value) and
  /// category defaults to empty (falls into "Other", forcing a choice)
  /// when the parser couldn't determine them.
  Transaction _buildDraftFromResult(SmsParseResult result) {
    return Transaction(
      id: 'draft_${DateTime.now().millisecondsSinceEpoch}',
      title: result.partialMerchant ?? '',
      source: result.bankName,
      amount: result.partialAmount ?? 0,
      date: result.smsDate ?? DateTime.now(),
      type: result.partialType ?? TransactionType.debit,
      category: '',
    );
  }

  /// Day 27: opens the separate Needs Review page. The page reads its list
  /// from NeedsReviewStore and calls back into this screen's add/dismiss
  /// handlers, so all the existing resolve/undo logic stays in one place.
  Future<void> _openNeedsReviewPage() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NeedsReviewScreen(
          onAdd: _openNeedsReviewItem,
          onDismiss: _dismissNeedsReviewItem,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openNeedsReviewItem(SmsParseResult result) async {
    final draft = _buildDraftFromResult(result);

    final saved = await Navigator.push<Transaction>(
      context,
      MaterialPageRoute(
        builder: (_) => AddTransactionScreen(
          existingCategories: _existingCategories,
          existingTransaction: draft,
          isDraft: true,
        ),
      ),
    );

    if (saved == null) return;

    final duplicates = await DatabaseHelper.instance.findPotentialDuplicates(
      amount: saved.amount,
      type: saved.type,
      date: saved.date,
    );

    if (duplicates.isNotEmpty) {
      if (!mounted) return;
      final proceed = await confirmPossibleDuplicate(
        context,
        existingDuplicates: duplicates,
      );
      if (!proceed) return;
    }

    await DatabaseHelper.instance.insertTransaction(saved);

    // Slice's SMS for money you send from the Slice bank account carries no
    // balance, so lower the stored Slice balance by the amount (only for
    // payments newer than that balance). Credit card items are charged to the
    // card, not the bank account, so they don't touch the balance.
    if (saved.type == TransactionType.debit &&
        isSliceSource(saved.source) &&
        !saved.source.toLowerCase().contains('card')) {
      await SliceBalance.applyPayment(
        signedAmount: -saved.amount,
        date: saved.date,
      );
    }

    final resolvedHash = DatabaseHelper.smsHash(
      sender: result.sender,
      body: result.rawBody,
      dateMillis: result.smsDate?.millisecondsSinceEpoch,
    );
    await DatabaseHelper.instance.markSmsProcessed(resolvedHash);

    await _clearMatchingNeedsReview(result, resolvedHash,
        amount: saved.amount, type: saved.type, date: saved.date);

    // The saved transaction may have introduced a new category (e.g. a
    // freshly typed "Other" value) — refresh so it's available next time.
    await _loadExistingCategories();
  }

  /// Dismisses a needs-review item WITHOUT inserting a transaction —
  /// for cases like "this SMS is for something I already added manually"
  /// (a true duplicate) or "this isn't a real transaction I need to
  /// track". Marks the SMS (and any other needs-review entries matching
  /// the same recovered amount/type/day) as processed so none of them
  /// keep reappearing, then removes them from the list. Shows a Snackbar
  /// with an Undo action so an accidental dismiss can be reversed.
  Future<void> _dismissNeedsReviewItem(SmsParseResult result) async {
    final hash = DatabaseHelper.smsHash(
      sender: result.sender,
      body: result.rawBody,
      dateMillis: result.smsDate?.millisecondsSinceEpoch,
    );

    // Capture exactly which entries get cleared (including matches by
    // amount/type/day, e.g. the twin ₹777 SMS) so Undo can restore all
    // of them, not just the one that was tapped.
    final cleared = await _clearMatchingNeedsReview(
      result,
      hash,
      amount: result.partialAmount,
      type: result.partialType,
      date: result.smsDate,
      alsoMarkPrimary: true,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          cleared.length > 1
              ? 'Dismissed ${cleared.length} matching messages'
              : 'Dismissed',
        ),
        action: SnackBarAction(
          label: 'UNDO',
          onPressed: () => _undoDismiss(cleared),
        ),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  /// Reverses a dismissal: unmarks each cleared SMS as processed and
  /// re-inserts them into [_needsReview] so they reappear immediately
  /// without needing a manual refresh.
  Future<void> _undoDismiss(List<SmsParseResult> cleared) async {
    for (final r in cleared) {
      final rHash = DatabaseHelper.smsHash(
        sender: r.sender,
        body: r.rawBody,
        dateMillis: r.smsDate?.millisecondsSinceEpoch,
      );
      await DatabaseHelper.instance.unmarkSmsProcessed(rHash);
    }

    if (!mounted) return;
    setState(() {
      _needsReview.addAll(cleared);
    });
    NeedsReviewStore.instance.setAll(_needsReview);
  }

  /// Shared cleanup: marks every needs-review entry that represents the
  /// same underlying transaction as [resolvedHash]/[amount]/[type]/[date]
  /// as processed, and removes them all from [_needsReview]. Used by both
  /// the "save a real transaction" path and the "dismiss, no transaction"
  /// path so a duplicate SMS from a different sender (e.g. AXISBK vs
  /// HDFCBK for the same payment) doesn't keep lingering after its twin
  /// has been resolved either way. Returns the list of entries that were
  /// cleared, so callers (like dismiss) can offer an Undo.
  ///
  /// [alsoMarkPrimary]: when true, [resolvedHash] itself is guaranteed to
  /// be included/marked even if it isn't found in [_needsReview] by hash
  /// (defensive — normally it always is, since it's the tapped item).
  Future<List<SmsParseResult>> _clearMatchingNeedsReview(
    SmsParseResult result,
    String resolvedHash, {
    double? amount,
    TransactionType? type,
    DateTime? date,
    bool alsoMarkPrimary = false,
  }) async {
    final toClear = _needsReview.where((r) {
      final rHash = DatabaseHelper.smsHash(
        sender: r.sender,
        body: r.rawBody,
        dateMillis: r.smsDate?.millisecondsSinceEpoch,
      );
      final sameHash = rHash == resolvedHash;
      final sameTransaction = amount != null &&
          type != null &&
          date != null &&
          r.partialAmount != null &&
          r.partialType != null &&
          r.smsDate != null &&
          r.partialAmount == amount &&
          r.partialType == type &&
          r.smsDate!.year == date.year &&
          r.smsDate!.month == date.month &&
          r.smsDate!.day == date.day;
      return sameHash || sameTransaction;
    }).toList();

    if (alsoMarkPrimary && !toClear.contains(result)) {
      toClear.add(result);
    }

    for (final r in toClear) {
      final rHash = DatabaseHelper.smsHash(
        sender: r.sender,
        body: r.rawBody,
        dateMillis: r.smsDate?.millisecondsSinceEpoch,
      );
      await DatabaseHelper.instance.markSmsProcessed(rHash);
    }

    if (!mounted) return toClear;
    setState(() {
      _needsReview.removeWhere((r) => toClear.contains(r));
    });
    NeedsReviewStore.instance.setAll(_needsReview);

    return toClear;
  }

  @override
  Widget build(BuildContext context) {
    final transactionLike = _messages.where(_looksLikeTransactionSms).toList();
    final other = _messages.where((m) => !_looksLikeTransactionSms(m)).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('SMS Reader'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _loadMessages,
          ),
        ],
      ),
      body: _buildBody(transactionLike, other),
    );
  }

  Widget _buildNeedsReviewCard() {
    final count = _needsReview.length;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: count > 0 ? Colors.orange.shade50 : null,
      child: ListTile(
        leading: Icon(
          count > 0 ? Icons.warning_amber : Icons.check_circle_outline,
          color: count > 0 ? Colors.orange : Colors.green,
        ),
        title: Text('Needs review ($count)'),
        subtitle: Text(
          count > 0
              ? 'Messages MY4 could not add automatically. Tap to review.'
              : 'Nothing waiting.',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: _openNeedsReviewPage,
      ),
    );
  }

  Widget _buildBody(List<SmsMessage> transactionLike, List<SmsMessage> other) {
    if (_permissionDenied) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'SMS permission was denied. MY4 needs SMS read access '
                'to auto-detect transactions.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _requestPermissionAndLoad,
                child: const Text('Grant Permission'),
              ),
            ],
          ),
        ),
      );
    }

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_messages.isEmpty) {
      return const Center(child: Text('No SMS messages found.'));
    }

    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Auto-added: $_autoAddedCount   •   '
                'Already processed (skipped): $_skippedAlreadyProcessed',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'Likely transaction SMS: ${transactionLike.length} / '
                '${_messages.length} total',
                style: TextStyle(color: Colors.grey.shade700),
              ),
            ],
          ),
        ),
        _buildNeedsReviewCard(),
        const SizedBox(height: 8),
        const Divider(thickness: 2),
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: Text(
            'All flagged SMS (${transactionLike.length})',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        ...transactionLike.map((msg) => _SmsTile(msg: msg, flagged: true)),
        const Divider(thickness: 2),
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: Text(
            'Other SMS (${other.length})',
            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
          ),
        ),
        ...other.map((msg) => _SmsTile(msg: msg, flagged: false)),
      ],
    );
  }
}

class _SmsTile extends StatelessWidget {
  final SmsMessage msg;
  final bool flagged;

  const _SmsTile({required this.msg, required this.flagged});

  @override
  Widget build(BuildContext context) {
    final date = msg.date != null
        ? DateTime.fromMillisecondsSinceEpoch(msg.date!)
        : null;

    return ListTile(
      leading: Icon(
        flagged ? Icons.account_balance_wallet : Icons.message_outlined,
        color: flagged ? Colors.green : Colors.grey,
      ),
      title: Text(msg.address ?? 'Unknown sender'),
      subtitle: Text(
        msg.body ?? '',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: date != null
          ? Text('${date.day}/${date.month}/${date.year}')
          : null,
    );
  }
}