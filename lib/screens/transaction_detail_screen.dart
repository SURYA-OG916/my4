import 'package:flutter/material.dart';
import '../models/transaction.dart';
import '../utils/category_colors.dart';
import '../utils/transfer_helper.dart';
import 'add_transaction_screen.dart';

// Day 38: same palette as the Accounts screen and the transaction list.
const Color _navy = Color(0xFF1F2A44);
const Color _credit = Color(0xFF5A8F6E);
const Color _debit = Color(0xFFB5654A);
const Color _transfer = Color(0xFF9E9E9E);

String _two(int n) => n.toString().padLeft(2, '0');

String _formatDateTime(DateTime d) =>
    '${_two(d.day)}/${_two(d.month)}/${d.year} ${_two(d.hour)}:${_two(d.minute)}';

class TransactionDetailScreen extends StatelessWidget {
  final Transaction transaction;
  final List<String> existingCategories;

  const TransactionDetailScreen({
    super.key,
    required this.transaction,
    required this.existingCategories,
  });

  Future<void> _editTransaction(BuildContext context) async {
    final updated = await Navigator.push<Transaction>(
      context,
      MaterialPageRoute(
        builder: (context) => AddTransactionScreen(
          existingCategories: existingCategories,
          existingTransaction: transaction,
        ),
      ),
    );

    if (updated != null && context.mounted) {
      // Hand the updated transaction back to whoever pushed this detail
      // screen (main.dart), so it can be merged into the master list.
      Navigator.pop(context, updated);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDebit = transaction.type == TransactionType.debit;
    final isTransferTx = transaction.category == transferCategory;
    final color = isTransferTx ? _transfer : (isDebit ? _debit : _credit);

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: const Text('Transaction Detail'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit',
            onPressed: () => _editTransaction(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
        children: [
          // Amount header
          Container(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              color: color.withOpacity(0.10),
            ),
            child: Column(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.18),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isDebit ? Icons.arrow_upward : Icons.arrow_downward,
                    color: color,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '${isDebit ? '-' : '+'}₹${transaction.amount.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                    color: color,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  transaction.title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: _navy,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Details
          Card(
            elevation: 0,
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: scheme.outlineVariant.withOpacity(0.6)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Column(
                children: [
                  _DetailRow(label: 'Title', value: transaction.title),
                  const _RowDivider(),
                  _DetailRow(label: 'Source', value: transaction.source),
                  const _RowDivider(),
                  _DetailRow(
                    label: 'Category',
                    valueWidget: _CategoryChip(category: transaction.category),
                  ),
                  const _RowDivider(),
                  _DetailRow(
                    label: 'Type',
                    value: isDebit ? 'Debit' : 'Credit',
                  ),
                  const _RowDivider(),
                  _DetailRow(
                    label: 'Date',
                    value: _formatDateTime(transaction.date),
                  ),
                  const _RowDivider(),
                  _DetailRow(
                    label: 'Transaction ID',
                    value: transaction.id,
                    small: true,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String category;

  const _CategoryChip({required this.category});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: categorySoftColor(category),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        category,
        style: TextStyle(
          color: categoryLabelColor(category),
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.5),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String? value;
  final Widget? valueWidget;
  final bool small;

  const _DetailRow({
    required this.label,
    this.value,
    this.valueWidget,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: valueWidget ??
                  Text(
                    value ?? '',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: small ? 12 : 15,
                      color: small ? Colors.grey.shade700 : null,
                    ),
                  ),
            ),
          ),
        ],
      ),
    );
  }
}