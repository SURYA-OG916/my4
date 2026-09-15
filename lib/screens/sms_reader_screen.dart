import 'package:flutter/material.dart';
import 'package:another_telephony/telephony.dart';
import '../db/database_helper.dart';
import '../models/transaction.dart';
import '../utils/sms_parser.dart';
import '../utils/category_helper.dart';
import '../utils/duplicate_helper.dart';
import '../utils/needs_review_store.dart';
import 'add_transaction_screen.dart';

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

  // Rough first-pass filter — known bank/UPI sender ID patterns.
  bool _looksLikeTransactionSms(SmsMessage msg) {
    final String address = (msg.address ?? '').toUpperCase();
    final String body = (msg.body ?? '').toLowerCase();

    final bool senderLooksLikeBank = RegExp(
      r'^[A-Z]{2}-?[A-Z0-9]{3,}',
    ).hasMatch(address);

    final bool bodyMentionsTransaction = body.contains('debited') ||
        body.contains('credited') ||
        body.contains('upi') ||
        body.contains('a/c') ||
        body.contains('account') ||
        body.contains('spent') ||
        body.contains('paid');

    return senderLooksLikeBank && bodyMentionsTransaction;
  }

  /// Runs every flagged SMS through SmsParser, skipping any SMS whose
  /// hash is already in processed_sms. Successful parses that don't match
  /// an existing transaction are auto-inserted and marked processed
  /// immediately. Successful parses that DO match an existing transaction
  /// (same amount/type/day) are diverted into Needs Review instead of
  /// silently auto-inserting a likely duplicate — the user decides there.
  /// True failures are collected into [_needsReview] as before. Neither
  /// diverted duplicates nor true failures are marked processed — an
  /// unresolved needs-review SMS must keep reappearing on every refresh
  /// until the user actually saves a transaction for it (see
  /// [_openNeedsReviewItem]), otherwise it gets silently marked "done" and
  /// vanishes without ever being resolved.
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

        if (duplicates.isNotEmpty) {
          reviewList.add(SmsParseResult.failure(
            'Possible duplicate of an existing transaction (same amount, '
            'type, and date)',
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
    // Keep the cross-screen store in sync so main.dart's "+" add flow can
    // see what's currently pending here.
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

    final resolvedHash = DatabaseHelper.smsHash(
      sender: result.sender,
      body: result.rawBody,
      dateMillis: result.smsDate?.millisecondsSinceEpoch,
    );
    await DatabaseHelper.instance.markSmsProcessed(resolvedHash);

    // Any OTHER needs-review entries now representing the same real
    // transaction must be cleared too, or the user could resolve them
    // separately later and insert a genuine duplicate. Two cases:
    //   1. Same SMS hash (identical sender+body+date) — the old check.
    //   2. A DIFFERENT SMS (e.g. a second bank notification for the same
    //      payment, different sender — like an AXISBK message alongside
    //      an HDFCBK one) whose recovered amount/type/day matches what
    //      was just saved. This is the case that was previously missed:
    //      different hash, same underlying transaction.
    final toClear = _needsReview.where((r) {
      final rHash = DatabaseHelper.smsHash(
        sender: r.sender,
        body: r.rawBody,
        dateMillis: r.smsDate?.millisecondsSinceEpoch,
      );
      final sameHash = rHash == resolvedHash;
      final sameTransaction = r.partialAmount != null &&
          r.partialType != null &&
          r.smsDate != null &&
          r.partialAmount == saved.amount &&
          r.partialType == saved.type &&
          r.smsDate!.year == saved.date.year &&
          r.smsDate!.month == saved.date.month &&
          r.smsDate!.day == saved.date.day;
      return sameHash || sameTransaction;
    }).toList();

    for (final r in toClear) {
      final rHash = DatabaseHelper.smsHash(
        sender: r.sender,
        body: r.rawBody,
        dateMillis: r.smsDate?.millisecondsSinceEpoch,
      );
      await DatabaseHelper.instance.markSmsProcessed(rHash);
    }

    if (!mounted) return;
    setState(() {
      _needsReview.removeWhere((r) => toClear.contains(r));
    });
    NeedsReviewStore.instance.setAll(_needsReview);

    // The saved transaction may have introduced a new category (e.g. a
    // freshly typed "Other" value) — refresh so it's available next time.
    await _loadExistingCategories();
  }

  @override
  Widget build(BuildContext context) {
    final transactionLike = _messages.where(_looksLikeTransactionSms).toList();
    final other = _messages.where((m) => !_looksLikeTransactionSms(m)).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('SMS Reader (Day 19)'),
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
          child: Text(
            'Auto-added: $_autoAddedCount   •   '
            'Needs review: ${_needsReview.length}   •   '
            'Already processed (skipped): $_skippedAlreadyProcessed   •   '
            'Likely transaction SMS: ${transactionLike.length} / ${_messages.length} total',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        if (_needsReview.isNotEmpty) ...[
          const Divider(thickness: 2, color: Colors.orange),
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Text(
              'Needs review — tap to add (${_needsReview.length})',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.orange,
              ),
            ),
          ),
          ..._needsReview.map(
            (result) => _NeedsReviewTile(
              result: result,
              onTap: () => _openNeedsReviewItem(result),
            ),
          ),
        ],
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

class _NeedsReviewTile extends StatelessWidget {
  final SmsParseResult result;
  final VoidCallback onTap;

  const _NeedsReviewTile({required this.result, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.warning_amber, color: Colors.orange),
      title: Text(result.sender),
      subtitle: Text(
        '${result.failureReason}\n${result.rawBody}',
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: true,
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
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