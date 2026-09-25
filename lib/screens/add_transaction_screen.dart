import 'package:flutter/material.dart';
import '../models/transaction.dart';
import '../utils/category_matcher.dart';

class AddTransactionScreen extends StatefulWidget {
  final List<String> existingCategories;
  final Transaction? existingTransaction;

  /// When true, [existingTransaction] is treated as a prefilled draft
  /// (e.g. partial data recovered from an unparseable SMS) rather than
  /// a real transaction being edited. The screen still uses its id/fields
  /// to prefill the form, but shows "Add"/"Save" wording instead of
  /// "Edit"/"Update".
  final bool isDraft;

  const AddTransactionScreen({
    super.key,
    required this.existingCategories,
    this.existingTransaction,
    this.isDraft = false,
  });

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _titleController;
  late final TextEditingController _sourceController;
  late final TextEditingController _amountController;

  late TransactionType _selectedType;
  String? _selectedCategory;
  late DateTime _selectedDate;

  static const String _otherOptionValue = '__other__';
  final TextEditingController _customCategoryController = TextEditingController();

  bool get _isEditing =>
      widget.existingTransaction != null && !widget.isDraft;

  // Day 29: auto-suggests a category from the title as you type, using the
  // same CategoryMatcher the notification/SMS pipeline already uses. Only
  // active for a genuinely new transaction (not an edit or an SMS draft,
  // both of which may already carry a deliberate category), and it stops
  // the moment the user picks a category themselves, so it never overwrites
  // a manual choice.
  bool _categoryTouchedByUser = false;

  @override
  void initState() {
    super.initState();

    final existing = widget.existingTransaction;

    _titleController = TextEditingController(text: existing?.title ?? '');
    _sourceController = TextEditingController(text: existing?.source ?? '');
    _amountController = TextEditingController(
      text: existing != null && existing.amount > 0
          ? existing.amount.toString()
          : '',
    );
    _selectedType = existing?.type ?? TransactionType.debit;
    _selectedDate = existing?.date ?? DateTime.now();

    final realCategories =
        widget.existingCategories.where((c) => c != 'All').toList();

    if (existing != null) {
      // If the transaction's category is still a known one, select it in the
      // dropdown; otherwise fall back to the "Other" option pre-filled with
      // its current value so nothing is silently lost.
      if (realCategories.contains(existing.category)) {
        _selectedCategory = existing.category;
      } else {
        _selectedCategory = _otherOptionValue;
        _customCategoryController.text = existing.category;
      }
      // Editing or a draft already has a category worth keeping — don't
      // let title edits silently reassign it.
      _categoryTouchedByUser = true;
    } else if (realCategories.isNotEmpty) {
      _selectedCategory = realCategories.first;
    }

    _titleController.addListener(_onTitleChanged);
  }

  void _onTitleChanged() {
    if (widget.existingTransaction != null) return; // edit/draft: skip
    if (_categoryTouchedByUser) return;

    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    final guess = CategoryMatcher.categorize(title);
    final realCategories =
        widget.existingCategories.where((c) => c != 'All').toList();

    // Only apply the guess if it's an actual category already in use in
    // this app (so a brand-new user with an empty category list still just
    // sees the plain default, not a category that doesn't exist for them).
    if (realCategories.contains(guess) && _selectedCategory != guess) {
      setState(() => _selectedCategory = guess);
    }
  }

  @override
  void dispose() {
    _titleController.removeListener(_onTitleChanged);
    _titleController.dispose();
    _sourceController.dispose();
    _amountController.dispose();
    _customCategoryController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        // Keep the time of day that was already selected. A date-only value
        // would be midnight, which counts as "before" a bank balance you set
        // earlier today and would be left out of it.
        _selectedDate = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _selectedDate.hour,
          _selectedDate.minute,
          _selectedDate.second,
        );
      });
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategory == null) return;

    final resolvedCategory = _selectedCategory == _otherOptionValue
        ? _customCategoryController.text.trim()
        : _selectedCategory!;

    if (resolvedCategory.isEmpty) return;

    final newTransaction = Transaction(
      id: widget.existingTransaction?.id ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      title: _titleController.text.trim(),
      source: _sourceController.text.trim(),
      amount: double.parse(_amountController.text.trim()),
      date: _selectedDate,
      type: _selectedType,
      category: resolvedCategory,
    );

    Navigator.pop(context, newTransaction);
  }

  @override
  Widget build(BuildContext context) {
    final realCategories =
        widget.existingCategories.where((c) => c != 'All').toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isEditing
              ? 'Edit Transaction'
              : (widget.isDraft
                  ? 'Add Transaction (from SMS)'
                  : 'Add Transaction'),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Title'),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a title';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _sourceController,
                decoration: const InputDecoration(
                  labelText: 'Source',
                  hintText: 'e.g. GPay, Cash, HDFC Bank',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a source';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _amountController,
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  prefixText: '₹',
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter an amount';
                  }
                  final parsed = double.tryParse(value.trim());
                  if (parsed == null || parsed <= 0) {
                    return 'Enter a valid amount greater than 0';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedCategory,
                decoration: const InputDecoration(labelText: 'Category'),
                items: [
                  ...realCategories.map(
                    (category) => DropdownMenuItem(
                      value: category,
                      child: Text(category),
                    ),
                  ),
                  const DropdownMenuItem(
                    value: _otherOptionValue,
                    child: Text('Other (type new category)'),
                  ),
                ],
                onChanged: (value) {
                  setState(() {
                    _selectedCategory = value;
                    _categoryTouchedByUser = true;
                  });
                },
                validator: (value) =>
                    value == null ? 'Please select a category' : null,
              ),
              if (_selectedCategory == _otherOptionValue) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _customCategoryController,
                  decoration: const InputDecoration(
                    labelText: 'New category name',
                  ),
                  validator: (value) {
                    if (_selectedCategory != _otherOptionValue) return null;
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a category name';
                    }
                    return null;
                  },
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: RadioListTile<TransactionType>(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Debit'),
                      value: TransactionType.debit,
                      groupValue: _selectedType,
                      onChanged: (value) {
                        setState(() {
                          _selectedType = value!;
                        });
                      },
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<TransactionType>(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Credit'),
                      value: TransactionType.credit,
                      groupValue: _selectedType,
                      onChanged: (value) {
                        setState(() {
                          _selectedType = value!;
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Date'),
                subtitle: Text(_formatDate(_selectedDate)),
                trailing: const Icon(Icons.calendar_today),
                onTap: _pickDate,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _submit,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(_isEditing ? 'Update Transaction' : 'Save Transaction'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}