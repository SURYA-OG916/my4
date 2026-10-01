import 'package:flutter/material.dart';
import '../models/budget.dart';
import '../db/database_helper.dart';
import '../utils/category_colors.dart';

// Day 38: same navy palette as the rest of the app.
const Color _navy = Color(0xFF1F2A44);
const Color _accent = Color(0xFF6B8CAE);

class BudgetSettingsScreen extends StatefulWidget {
  final List<String> categories;

  const BudgetSettingsScreen({
    super.key,
    required this.categories,
  });

  @override
  State<BudgetSettingsScreen> createState() => _BudgetSettingsScreenState();
}

class _BudgetSettingsScreenState extends State<BudgetSettingsScreen> {
  Map<String, double> _budgets = {};
  final Map<String, TextEditingController> _controllers = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBudgets();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadBudgets() async {
    final loaded = await DatabaseHelper.instance.getAllBudgets();
    final map = {for (var b in loaded) b.category: b.limit};

    for (final category in widget.categories) {
      if (category == 'All') continue;
      _controllers[category] = TextEditingController(
        text: map[category] != null ? map[category]!.toStringAsFixed(0) : '',
      );
    }

    setState(() {
      _budgets = map;
      _isLoading = false;
    });
  }

  Future<void> _saveBudget(String category) async {
    final text = _controllers[category]!.text.trim();

    if (text.isEmpty) {
      await DatabaseHelper.instance.deleteBudget(category);
      setState(() {
        _budgets.remove(category);
      });
      return;
    }

    final value = double.tryParse(text);
    if (value == null || value < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid amount')),
      );
      return;
    }

    await DatabaseHelper.instance.setBudget(
      Budget(category: category, limit: value),
    );
    if (!mounted) return;
    setState(() {
      _budgets[category] = value;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Budget saved for $category')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final categoryList =
        widget.categories.where((c) => c != 'All').toList();

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: const Text('Monthly Budgets'),
      ),
      body: categoryList.isEmpty
          ? const Center(child: Text('No categories yet'))
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
              itemCount: categoryList.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                    child: Text(
                      'Set a monthly limit for a category and tap the tick '
                      'to save. Leave a box empty and tap the tick to remove '
                      'its budget.',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                  );
                }

                final category = categoryList[index - 1];
                return _buildCategoryRow(category);
              },
            ),
    );
  }

  Widget _buildCategoryRow(String category) {
    final scheme = Theme.of(context).colorScheme;
    final hasBudget = _budgets.containsKey(category);
    final initial = category.isEmpty ? '?' : category[0].toUpperCase();

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant.withOpacity(0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: categorySoftColor(category),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                initial,
                style: TextStyle(
                  color: categoryLabelColor(category),
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                category,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 128,
              child: TextField(
                controller: _controllers[category],
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  prefixText: '₹ ',
                  hintText: 'No limit',
                  isDense: true,
                  filled: true,
                  fillColor: _accent.withOpacity(0.08),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _navy, width: 1.4),
                  ),
                ),
                onSubmitted: (_) => _saveBudget(category),
              ),
            ),
            IconButton(
              icon: Icon(
                Icons.check_circle,
                color: hasBudget ? const Color(0xFF5A8F6E) : Colors.grey.shade400,
              ),
              tooltip: 'Save',
              onPressed: () => _saveBudget(category),
            ),
          ],
        ),
      ),
    );
  }
}