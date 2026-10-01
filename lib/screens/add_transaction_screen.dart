import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../models/bank_account.dart';
import '../models/transaction.dart';
import '../utils/account_balance.dart';
import '../utils/category_colors.dart';
import '../utils/category_matcher.dart';
import '../utils/slice_balance.dart';
import '../utils/transfer_helper.dart';

// Day 38: same navy palette as the rest of the app.
const Color _navy = Color(0xFF1F2A44);
const Color _accent = Color(0xFF6B8CAE);
const Color _amber = Color(0xFFC9A227);

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

  // Day 36: which bank account this transaction went through, so manual
  // entries and edits carry the same "Bank 1234" tag the SMS/notification
  // pipeline adds. Optional — "None" leaves the Source field exactly as
  // typed, for cash or anything that isn't one of your saved accounts.
  static const String _noAccountValue = '__none__';
  List<BankAccount> _accounts = [];
  String? _selectedAccountId;
  bool _accountsLoaded = false;

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
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    final accounts = await DatabaseHelper.instance.getAllAccounts();
    // Slice is its own account elsewhere in the app and is never picked
    // from this list — its transactions come from Slice messages, not this
    // form.
    final bankAccounts =
        accounts.where((a) => !isSliceSource(a.bank)).toList();

    String? matchedId;
    final existing = widget.existingTransaction;
    if (existing != null) {
      for (final a in bankAccounts) {
        if (AccountBalance.belongsToAccount(existing, a)) {
          matchedId = a.id;
          break;
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _accounts = bankAccounts;
      _selectedAccountId = matchedId;
      _accountsLoaded = true;
    });
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

  // Day 36: there was no way to edit the TIME on an existing entry, only the
  // date — the field kept whatever time it already had. That mattered for a
  // manual self-transfer entered after the fact, where the real time (not
  // "when I happened to type it in") is what makes the order of same-day
  // transactions make sense when you look back at them.
  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedDate),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = DateTime(
          _selectedDate.year,
          _selectedDate.month,
          _selectedDate.day,
          picked.hour,
          picked.minute,
        );
      });
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  String _formatTime(DateTime date) {
    return '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }

  /// Day 36: folds the chosen account into the Source text, e.g. typing
  /// "Google Pay" as the source and picking "SBI 3742" produces
  /// "Google Pay • SBI 3742" — the same shape SMS/notification entries use,
  /// so AccountBalance.belongsToAccount recognizes it. If the source already
  /// names that bank and last 4 digits (as SBI SMS already do), nothing is
  /// added twice.
  String _sourceWithAccount() {
    final typed = _sourceController.text.trim();
    if (_selectedAccountId == null || _selectedAccountId == _noAccountValue) {
      return typed;
    }
    final account = _accounts.firstWhere(
      (a) => a.id == _selectedAccountId,
      orElse: () => _accounts.first,
    );
    final already = typed.toLowerCase().contains(account.bank.toLowerCase()) &&
        typed.contains(account.last4);
    if (already) return typed;
    if (typed.isEmpty) return '${account.bank} ${account.last4}';
    return '$typed • ${account.bank} ${account.last4}';
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
      source: _sourceWithAccount(),
      amount: double.parse(_amountController.text.trim()),
      date: _selectedDate,
      type: _selectedType,
      category: resolvedCategory,
    );

    Navigator.pop(context, newTransaction);
  }

  // ------------------------------------------------------------------ layout

  InputDecoration _decoration({
    required String label,
    String? hint,
    String? helper,
    String? prefixText,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      prefixText: prefixText,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _navy, width: 1.6),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: Colors.grey.shade600,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildAccountPicker() {
    if (!_accountsLoaded) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: DropdownButtonFormField<String>(
        value: _selectedAccountId ?? _noAccountValue,
        decoration: _decoration(
          label: 'Account (optional)',
          helper: 'Which bank account this went through',
        ),
        items: [
          const DropdownMenuItem(
            value: _noAccountValue,
            child: Text('None / not sure'),
          ),
          ..._accounts.map(
            (a) => DropdownMenuItem(
              value: a.id,
              child: Text(a.label),
            ),
          ),
        ],
        onChanged: (value) {
          setState(() {
            _selectedAccountId = value;
          });
        },
      ),
    );
  }

  Widget _dateTimeTile({
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: _accent.withOpacity(0.08),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 20, color: _navy),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final realCategories =
        widget.existingCategories.where((c) => c != 'All').toList();

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: Text(
          _isEditing
              ? 'Edit Transaction'
              : (widget.isDraft
                  ? 'Add Transaction (from SMS)'
                  : 'Add Transaction'),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
          children: [
            if (widget.isDraft)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: _amber.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, size: 18, color: Color(0xFF8A6D0B)),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Prefilled from an SMS. Check the details before saving.',
                        style: TextStyle(
                          color: Color(0xFF8A6D0B),
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Debit / Credit
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<TransactionType>(
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.grey.shade700,
                  selectedBackgroundColor: _navy,
                  selectedForegroundColor: Colors.white,
                  side: BorderSide(color: Colors.grey.shade300),
                  textStyle: const TextStyle(fontWeight: FontWeight.w600),
                ),
                segments: const [
                  ButtonSegment(
                    value: TransactionType.debit,
                    label: Text('Debit'),
                    icon: Icon(Icons.arrow_upward),
                  ),
                  ButtonSegment(
                    value: TransactionType.credit,
                    label: Text('Credit'),
                    icon: Icon(Icons.arrow_downward),
                  ),
                ],
                selected: {_selectedType},
                onSelectionChanged: (selection) {
                  setState(() {
                    _selectedType = selection.first;
                  });
                },
              ),
            ),
            const SizedBox(height: 16),

            // Amount
            TextFormField(
              controller: _amountController,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
              decoration: _decoration(label: 'Amount', prefixText: '₹ '),
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

            _sectionLabel('Details'),
            TextFormField(
              controller: _titleController,
              decoration: _decoration(label: 'Title'),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a title';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _sourceController,
              decoration: _decoration(
                label: 'Source',
                hint: 'e.g. GPay, Cash, HDFC Bank',
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a source';
                }
                return null;
              },
            ),
            _buildAccountPicker(),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              value: _selectedCategory,
              decoration: _decoration(label: 'Category'),
              items: [
                ...realCategories.map(
                  (category) => DropdownMenuItem(
                    value: category,
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: categoryColor(category),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(category),
                      ],
                    ),
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
              const SizedBox(height: 14),
              TextFormField(
                controller: _customCategoryController,
                decoration: _decoration(label: 'New category name'),
                validator: (value) {
                  if (_selectedCategory != _otherOptionValue) return null;
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a category name';
                  }
                  return null;
                },
              ),
            ],

            _sectionLabel('When'),
            Row(
              children: [
                Expanded(
                  child: _dateTimeTile(
                    label: 'Date',
                    value: _formatDate(_selectedDate),
                    icon: Icons.calendar_today_outlined,
                    onTap: _pickDate,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _dateTimeTile(
                    label: 'Time',
                    value: _formatTime(_selectedDate),
                    icon: Icons.access_time,
                    onTap: _pickTime,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _submit,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    _isEditing ? 'Update Transaction' : 'Save Transaction',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}