import 'package:flutter/material.dart';
import '../models/transaction.dart';

class CategorySummaryScreen extends StatelessWidget {
  final List<Transaction> transactions;

  const CategorySummaryScreen({
    super.key,
    required this.transactions,
  });

  Map<String, double> _computeCategoryTotals() {
    final Map<String, double> totals = {};

    for (final tx in transactions) {
      if (tx.type != TransactionType.debit) continue;
      totals.update(
        tx.category,
        (value) => value + tx.amount,
        ifAbsent: () => tx.amount,
      );
    }

    return totals;
  }

  @override
  Widget build(BuildContext context) {
    final totals = _computeCategoryTotals();
    final sortedEntries = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final grandTotal = totals.values.fold(0.0, (sum, v) => sum + v);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Category Summary'),
      ),
      body: sortedEntries.isEmpty
          ? const Center(
              child: Text('No spending recorded yet'),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: sortedEntries.length,
              itemBuilder: (context, index) {
                final entry = sortedEntries[index];
                final percentage =
                    grandTotal == 0 ? 0.0 : (entry.value / grandTotal) * 100;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            entry.key,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '₹${entry.value.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: percentage / 100,
                          minHeight: 8,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${percentage.toStringAsFixed(1)}% of total spend',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}