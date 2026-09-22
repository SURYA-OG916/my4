import 'package:flutter/material.dart';

import '../models/transaction.dart';
import '../utils/needs_review_store.dart';
import '../utils/sms_parser.dart';
import '../widgets/bank_badge.dart';

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
          appBar: AppBar(title: Text('Needs review (${items.length})')),
          body: items.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Nothing needs review. Messages MY4 could not add '
                      'automatically will show up here.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
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
    final type = result.partialType;
    final amount = result.partialAmount;
    final merchant = result.partialMerchant;

    final recovered = <String>[
      if (type != null)
        type == TransactionType.debit ? 'Debit' : 'Credit',
      if (amount != null) '₹${amount.toStringAsFixed(2)}',
      if (merchant != null && merchant.isNotEmpty) merchant,
    ].join(' • ');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BankBadge(bankName: result.bankName, size: 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${result.sender}   ${_formatDate(result.smsDate)}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        result.failureReason ?? '',
                        style: TextStyle(color: Colors.orange.shade900),
                      ),
                      if (recovered.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Found: $recovered',
                          style: TextStyle(color: Colors.grey.shade800),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        result.rawBody,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
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