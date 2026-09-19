import 'package:flutter/material.dart';
import 'models/transaction.dart';
import 'utils/transfer_helper.dart';

class SummaryHeader extends StatelessWidget {
  final List<Transaction> transactions;

  /// The user's current bank balance (set on the Accounts screen), or null if
  /// it hasn't been set. When null, the third column shows "Net" instead.
  final double? bankBalance;

  /// "Balance" for the current month, "Closing" for a past month.
  final String balanceLabel;

  const SummaryHeader({
    super.key,
    required this.transactions,
    this.bankBalance,
    this.balanceLabel = 'Balance',
  });

  @override
  Widget build(BuildContext context) {
    // Own-account transfers are not real income or spending.
    final counted = withoutTransfers(transactions);

    final double totalCredit = counted
        .where((t) => t.type == TransactionType.credit)
        .fold(0.0, (sum, t) => sum + t.amount);

    final double totalDebit = counted
        .where((t) => t.type == TransactionType.debit)
        .fold(0.0, (sum, t) => sum + t.amount);

    // "Net" is income minus spending for the selected month. It is NOT your
    // bank balance, so it is labelled differently.
    final double net = totalCredit - totalDebit;
    final double? balance = bankBalance;

    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildColumn('Income', totalCredit, Colors.green),
          _buildColumn('Spent', totalDebit, Colors.red),
          if (balance != null)
            _buildColumn(
                balanceLabel, balance, balance >= 0 ? Colors.green : Colors.red)
          else
            _buildColumn('Net', net, net >= 0 ? Colors.green : Colors.red),
        ],
      ),
    );
  }

  Widget _buildColumn(String label, double value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
        const SizedBox(height: 4),
        Text(
          '₹${value.toStringAsFixed(2)}',
          style: TextStyle(
              color: color, fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ],
    );
  }
}