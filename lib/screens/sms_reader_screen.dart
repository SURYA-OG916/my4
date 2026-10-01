import 'package:flutter/material.dart';
import 'package:another_telephony/telephony.dart' hide SmsFilter;
import '../db/database_helper.dart';
import '../models/transaction.dart';
import '../utils/sms_parser.dart';
import '../utils/sms_ingestor.dart';
import '../utils/slice_balance.dart';
import '../utils/category_helper.dart';
import '../utils/duplicate_helper.dart';
import '../utils/needs_review_store.dart';
import '../utils/transfer_helper.dart';
import 'add_transaction_screen.dart';
import 'needs_review_screen.dart';

// Day 38: same navy palette as the rest of the app.
const Color _navy = Color(0xFF1F2A44);
const Color _navySoft = Color(0xFF3B4A6B);
const Color _accent = Color(0xFF6B8CAE);
const Color _good = Color(0xFF5A8F6E);
const Color _amber = Color(0xFFC9A227);

String _two(int n) => n.toString().padLeft(2, '0');

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
  int _enrichedCount = 0;
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

  /// Day 36: the parsing/adding itself now lives in SmsIngestor (also run
  /// when the app starts or resumes). This screen just runs it and shows the
  /// outcome.
  Future<void> _loadMessages() async {
    setState(() => _loading = true);

    final result = await SmsIngestor.run();

    if (!mounted) return;
    setState(() {
      _messages = result.messages;
      _autoAddedCount = result.autoAdded;
      _enrichedCount = result.enriched;
      _skippedAlreadyProcessed = result.skipped;
      _needsReview
        ..clear()
        ..addAll(result.needsReview);
      _loading = false;
    });
    // Keep the cross-screen store in sync so main.dart's "+" add flow and
    // the Needs Review page can see what's currently pending here.
    NeedsReviewStore.instance.setAll(_needsReview);

    // New categories may have been introduced by auto-added transactions.
    if (result.autoAdded > 0) {
      await _loadExistingCategories();
    }
  }

  bool _looksLikeTransactionSms(SmsMessage msg) {
    return SmsIngestor.looksLikeTransactionSms(msg);
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
        centerTitle: false,
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

  // ------------------------------------------------------------------ layout

  Widget _statBox(String label, int value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.10),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                label,
                style: const TextStyle(color: Colors.white70, fontSize: 11.5),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '$value',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(int flagged, int total) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_navy, _navySoft],
        ),
        boxShadow: [
          BoxShadow(
            color: _navy.withOpacity(0.25),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _statBox('Auto-added', _autoAddedCount),
              const SizedBox(width: 8),
              _statBox('Account filled in', _enrichedCount),
              const SizedBox(width: 8),
              _statBox('Already processed', _skippedAlreadyProcessed),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Likely transaction SMS: $flagged / $total total',
            style: const TextStyle(color: Colors.white70, fontSize: 12.5),
          ),
        ],
      ),
    );
  }

  Widget _buildNeedsReviewCard() {
    final count = _needsReview.length;
    final hasItems = count > 0;
    final color = hasItems ? _amber : _good;
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: hasItems ? _amber.withOpacity(0.10) : Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: _openNeedsReviewPage,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: hasItems
                  ? _amber.withOpacity(0.4)
                  : scheme.outlineVariant.withOpacity(0.6),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  hasItems ? Icons.warning_amber : Icons.check_circle_outline,
                  color: color,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Needs review ($count)',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasItems
                          ? 'Messages MY4 could not add automatically. Tap to review.'
                          : 'Nothing waiting.',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey.shade600),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 20, 6, 10),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: Colors.grey.shade600,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildBody(List<SmsMessage> transactionLike, List<SmsMessage> other) {
    if (_permissionDenied) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: _amber.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.sms_failed_outlined,
                    size: 30, color: Color(0xFF8A6D0B)),
              ),
              const SizedBox(height: 16),
              const Text(
                'SMS permission was denied. MY4 needs SMS read access '
                'to auto-detect transactions.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
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
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
      children: [
        _buildSummaryCard(transactionLike.length, _messages.length),
        _buildNeedsReviewCard(),
        _sectionLabel('All flagged SMS (${transactionLike.length})'),
        ...transactionLike.map((msg) => _SmsTile(msg: msg, flagged: true)),
        _sectionLabel('Other SMS (${other.length})'),
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
    final scheme = Theme.of(context).colorScheme;
    final date = msg.date != null
        ? DateTime.fromMillisecondsSinceEpoch(msg.date!)
        : null;
    final color = flagged ? _good : Colors.grey.shade500;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant.withOpacity(0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: (flagged ? _good : _accent).withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                flagged ? Icons.account_balance_wallet : Icons.message_outlined,
                color: color,
                size: 19,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    msg.address ?? 'Unknown sender',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14.5,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    msg.body ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontSize: 12.5,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            if (date != null) ...[
              const SizedBox(width: 8),
              Text(
                '${_two(date.day)}/${_two(date.month)}/${date.year}',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 11.5),
              ),
            ],
          ],
        ),
      ),
    );
  }
}