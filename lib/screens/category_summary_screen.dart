import 'package:flutter/material.dart';
import '../models/transaction.dart';
import '../db/database_helper.dart';
import 'budget_settings_screen.dart';

class CategorySummaryScreen extends StatefulWidget {
  final List<Transaction> transactions;

  const CategorySummaryScreen({
    super.key,
    required this.transactions,
  });

  @override
  State<CategorySummaryScreen> createState() => _CategorySummaryScreenState();
}

class _CategorySummaryScreenState extends State<CategorySummaryScreen> {
  Map<String, double> _budgets = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBudgets();
  }

  Future<void> _loadBudgets() async {
    final loaded = await DatabaseHelper.instance.getAllBudgets();
    setState(() {
      _budgets = {for (var b in loaded) b.category: b.limit};
      _isLoading = false;
    });
  }

  Map<String, double> _computeCategoryTotals() {
    final Map<String, double> totals = {};

    for (final tx in widget.transactions) {
      if (tx.type != TransactionType.debit) continue;
      totals.update(
        tx.category,
        (value) => value + tx.amount,
        ifAbsent: () => tx.amount,
      );
    }

    return totals;
  }

  Future<void> _openBudgetSettings() async {
    final categories = [
      'All',
      ...{for (var t in widget.transactions) t.category}
    ];

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BudgetSettingsScreen(categories: categories),
      ),
    );

    // Refresh budgets after returning, in case they changed
    _loadBudgets();
  }

  Color _progressColor(double spend, double? limit) {
    if (limit == null || limit == 0) return Colors.blue;
    final ratio = spend / limit;
    if (ratio >= 1.0) return Colors.red;
    if (ratio >= 0.8) return Colors.orange;
    return Colors.green;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final totals = _computeCategoryTotals();
    final sortedEntries = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final grandTotal = totals.values.fold(0.0, (sum, v) => sum + v);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Category Summary'),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Set Budgets',
            onPressed: _openBudgetSettings,
          ),
        ],
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
                final percentageOfTotal =
                    grandTotal == 0 ? 0.0 : (entry.value / grandTotal) * 100;
                final limit = _budgets[entry.key];
                final hasBudget = limit != null && limit > 0;
                final budgetRatio =
                    hasBudget ? (entry.value / limit).clamp(0.0, 1.0) : null;
                final overBy = hasBudget && entry.value > limit
                    ? entry.value - limit
                    : null;

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
                            hasBudget
                                ? '₹${entry.value.toStringAsFixed(2)} / ₹${limit!.toStringAsFixed(0)}'
                                : '₹${entry.value.toStringAsFixed(2)}',
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
                          value: hasBudget
                              ? budgetRatio
                              : percentageOfTotal / 100,
                          minHeight: 8,
                          color: _progressColor(entry.value, limit),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        overBy != null
                            ? 'Over budget by ₹${overBy.toStringAsFixed(2)}'
                            : hasBudget
                                ? '${(budgetRatio! * 100).toStringAsFixed(0)}% of ₹${limit!.toStringAsFixed(0)} budget'
                                : '${percentageOfTotal.toStringAsFixed(1)}% of total spend',
                        style: TextStyle(
                          fontSize: 12,
                          color: overBy != null
                              ? Colors.red
                              : Colors.grey[600],
                          fontWeight:
                              overBy != null ? FontWeight.w600 : FontWeight.normal,
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