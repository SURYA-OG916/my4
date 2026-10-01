import 'package:flutter/material.dart';
import '../models/transaction.dart';
import '../db/database_helper.dart';
import '../utils/category_colors.dart';
import '../utils/transfer_helper.dart';
import 'budget_settings_screen.dart';

// Day 38: same palette as the Accounts screen.
const Color _navy = Color(0xFF1F2A44);
const Color _navySoft = Color(0xFF3B4A6B);
const Color _warn = Color(0xFFC9A227);
const Color _over = Color(0xFFB5654A);

class CategorySummaryScreen extends StatefulWidget {
  final List<Transaction> transactions;
  final String? monthLabel;

  const CategorySummaryScreen({
    super.key,
    required this.transactions,
    this.monthLabel,
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
    if (!mounted) return;
    setState(() {
      _budgets = {for (var b in loaded) b.category: b.limit};
      _isLoading = false;
    });
  }

  Map<String, double> _computeCategoryTotals() {
    final Map<String, double> totals = {};

    for (final tx in widget.transactions) {
      if (tx.type != TransactionType.debit) continue;
      // Day 30: Transfers (own-name-matched payments) aren't real spend,
      // so they're excluded from category totals here the same way
      // recurring_detector.dart already excludes them (Day 29).
      if (tx.category == transferCategory) continue;
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
      ...{
        for (var t in widget.transactions)
          if (t.category != transferCategory) t.category
      }
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

  // Day 38: bars use the category's own colour; they only switch to amber /
  // terracotta when a budget is nearly used up or exceeded.
  Color _barColor(String category, double spend, double? limit) {
    if (limit == null || limit == 0) return categoryColor(category);
    final ratio = spend / limit;
    if (ratio >= 1.0) return _over;
    if (ratio >= 0.8) return _warn;
    return categoryColor(category);
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
        centerTitle: false,
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
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
              children: [
                _buildHero(grandTotal, sortedEntries.length, widget.monthLabel),
                for (final entry in sortedEntries)
                  _buildCategoryCard(entry, grandTotal),
              ],
            ),
    );
  }

  Widget _buildHero(double grandTotal, int categoryCount, String? monthLabel) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(20),
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
          Text(
            monthLabel != null ? 'Total spent in $monthLabel' : 'Total spent',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 6),
          Text(
            '₹${grandTotal.toStringAsFixed(2)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'across $categoryCount categor${categoryCount == 1 ? 'y' : 'ies'}',
            style: const TextStyle(color: Colors.white60, fontSize: 12.5),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryCard(MapEntry<String, double> entry, double grandTotal) {
    final scheme = Theme.of(context).colorScheme;
    final percentageOfTotal =
        grandTotal == 0 ? 0.0 : (entry.value / grandTotal) * 100;
    final limit = _budgets[entry.key];
    final hasBudget = limit != null && limit > 0;
    final budgetRatio = hasBudget ? (entry.value / limit).clamp(0.0, 1.0) : null;
    final overBy = hasBudget && entry.value > limit ? entry.value - limit : null;

    final barColor = _barColor(entry.key, entry.value, limit);
    final initial = entry.key.isEmpty ? '?' : entry.key[0].toUpperCase();

    final note = overBy != null
        ? 'Over budget by ₹${overBy.toStringAsFixed(2)}'
        : hasBudget
            ? '${(budgetRatio! * 100).toStringAsFixed(0)}% of '
                '₹${limit.toStringAsFixed(0)} budget'
            : '${percentageOfTotal.toStringAsFixed(1)}% of total spend';

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
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
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: categorySoftColor(entry.key),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    initial,
                    style: TextStyle(
                      color: categoryLabelColor(entry.key),
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    entry.key,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  hasBudget
                      ? '₹${entry.value.toStringAsFixed(2)} / ₹${limit.toStringAsFixed(0)}'
                      : '₹${entry.value.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: hasBudget ? budgetRatio : percentageOfTotal / 100,
                minHeight: 8,
                color: barColor,
                backgroundColor: barColor.withOpacity(0.15),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              note,
              style: TextStyle(
                fontSize: 12,
                color: overBy != null ? _over : Colors.grey.shade600,
                fontWeight: overBy != null ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}