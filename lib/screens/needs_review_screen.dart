import 'package:flutter/material.dart';

import '../models/transaction.dart';
import '../utils/needs_review_store.dart';
import '../utils/sms_parser.dart';
import '../widgets/bank_badge.dart';

// Day 38: same palette as the Accounts screen.
const Color _accent = Color(0xFF6B8CAE);
const Color _amber = Color(0xFFC9A227);

String _formatDate(DateTime? d) {
  if (d == null) return '';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year}';
}

/// Day 27: Needs Review as its own page inside SMS Reader.
/// The list lives in NeedsReviewStore (kept in sync by SmsReaderScreen);
/// the add/dismiss actions are SmsReaderScreen's own handlers, passed in.
class NeedsReviewScreen extends StatelessWidget {
  final Future<void> Function(SmsParseResult result) onAdd;
  final Future<void> Function(SmsParseResult result) onDismiss;

  const NeedsReviewScreen({
    super.key,
    required this.onAdd,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: NeedsReviewStore.instance,
      builder: (context, _) {
        final items = NeedsReviewStore.instance.items;
        return Scaffold(
          appBar: AppBar(
            centerTitle: false,
            title: Text('Needs review (${items.length})'),
          ),
          body: items.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: _accent.withOpacity(0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check_rounded,
                            size: 32,
                            color: Color(0xFF3B4A6B),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'All clear',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Nothing needs review. Messages MY4 could not add '
                          'automatically will show up here.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final result = items[index];
                    return _NeedsReviewTile(
                      result: result,
                      onAdd: () => onAdd(result),
                      onDismiss: () => onDismiss(result),
                    );
                  },
                ),
        );
      },
    );
  }
}

class _NeedsReviewTile extends StatelessWidget {
  final SmsParseResult result;
  final VoidCallback onAdd;
  final VoidCallback onDismiss;

  const _NeedsReviewTile({
    required this.result,
    required this.onAdd,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final type = result.partialType;
    final amount = result.partialAmount;
    final merchant = result.partialMerchant;

    final recovered = <String>[
      if (type != null)
        type == TransactionType.debit ? 'Debit' : 'Credit',
      if (amount != null) '₹${amount.toStringAsFixed(2)}',
      if (merchant != null && merchant.isNotEmpty) merchant,
    ].join(' • ');

    final reason = result.failureReason ?? '';

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant.withOpacity(0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                BankBadge(bankName: result.bankName, size: 38),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    result.sender,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
                Text(
                  _formatDate(result.smsDate),
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ],
            ),
            if (reason.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _amber.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.info_outline,
                      size: 16,
                      color: Color(0xFF8A6D0B),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        reason,
                        style: const TextStyle(
                          color: Color(0xFF8A6D0B),
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (recovered.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                'Found: $recovered',
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _accent.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                result.rawBody,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontSize: 12.5,
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: onDismiss,
                  child: const Text('Dismiss'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: onAdd,
                  child: const Text('Add'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}