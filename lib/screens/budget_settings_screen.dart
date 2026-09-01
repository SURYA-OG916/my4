import 'package:flutter/material.dart';
import '../models/budget.dart';
import '../db/database_helper.dart';

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
        title: const Text('Monthly Budgets'),
      ),
      body: categoryList.isEmpty
          ? const Center(child: Text('No categories yet'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: categoryList.length,
              itemBuilder: (context, index) {
                final category = categoryList[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Text(
                          category,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _controllers[category],
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            prefixText: '₹ ',
                            hintText: 'No limit set',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _saveBudget(category),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.check, color: Colors.green),
                        onPressed: () => _saveBudget(category),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}