import 'package:flutter/material.dart';
import 'models/transaction.dart';

class SummaryHeader extends StatelessWidget {
  final List<Transaction> transactions;

  const SummaryHeader({super.key, required this.transactions});

  @override
  Widget build(BuildContext context) {
    final double totalCredit = transactions
        .where((t) => t.type == TransactionType.credit)
        .fold(0.0, (sum, t) => sum + t.amount);

    final double totalDebit = transactions
        .where((t) => t.type == TransactionType.debit)
        .fold(0.0, (sum, t) => sum + t.amount);

    final double balance = totalCredit - totalDebit;

    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
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
          _buildColumn('Balance', balance,
              balance >= 0 ? Colors.green : Colors.red),
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