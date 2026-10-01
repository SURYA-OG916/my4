import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../models/bank_account.dart';
import '../models/transaction.dart';
import '../utils/slice_balance.dart';

// Day 38: same navy palette as the rest of the app.
const Color _navy = Color(0xFF1F2A44);
const Color _accent = Color(0xFF6B8CAE);

/// What the quick-add sheet collects. The caller turns it into a Transaction
/// (category guessed) and runs the usual duplicate checks.
///
/// Day 36: [date] is no longer implicitly "now" — the sheet lets the user
/// set it, since a Quick Add is often recording something that happened
/// earlier (a self-transfer between accounts, say), not this exact second.
/// [source] already has the chosen account folded in, e.g.
/// "Paytm • SBI 3835", the same shape the rest of the app uses.
class QuickAddResult {
  final double amount;
  final String title;
  final TransactionType type;
  final String source;
  final DateTime date;

  const QuickAddResult({
    required this.amount,
    required this.title,
    required this.type,
    required this.source,
    required this.date,
  });
}

/// UPI apps don't notify you about money you send, so this is the fast way
/// to record it: amount, who, which app, which account, and when.
Future<QuickAddResult?> showQuickAddSheet(BuildContext context) {
  return showModalBottomSheet<QuickAddResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => const _QuickAddSheet(),
  );
}

class _QuickAddSheet extends StatefulWidget {
  const _QuickAddSheet();

  @override
  State<_QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends State<_QuickAddSheet> {
  static const List<String> _sources = [
    'Paytm',
    'Google Pay',
    'PhonePe',
    'Cash',
    'Other',
  ];

  // Remembered while the app is running, so repeated entries need one less tap.
  static String _lastSource = 'Paytm';

  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _titleController = TextEditingController();

  TransactionType _type = TransactionType.debit;
  String _source = _lastSource;
  String? _amountError;

  // Day 36: defaults to now, but the user can change it — a Quick Add is
  // frequently entered after the fact.
  DateTime _dateTime = DateTime.now();

  // Day 36: optional account, same idea as AddTransactionScreen's picker.
  static const String _noAccountValue = '__none__';
  List<BankAccount> _accounts = [];
  String? _selectedAccountId;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    final accounts = await DatabaseHelper.instance.getAllAccounts();
    final bankAccounts =
        accounts.where((a) => !isSliceSource(a.bank)).toList();
    if (!mounted) return;
    setState(() {
      _accounts = bankAccounts;
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _dateTime,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dateTime),
    );
    if (pickedTime == null) return;

    setState(() {
      _dateTime = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
    });
  }

  String _formatDateTime(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  /// Folds the chosen account into the source, e.g. "Paytm" + SBI 3835 ->
  /// "Paytm • SBI 3835" — the same shape belongsToAccount expects elsewhere.
  String _sourceWithAccount() {
    if (_selectedAccountId == null || _selectedAccountId == _noAccountValue) {
      return _source;
    }
    final account = _accounts.firstWhere(
      (a) => a.id == _selectedAccountId,
      orElse: () => _accounts.first,
    );
    return '$_source • ${account.bank} ${account.last4}';
  }

  void _save() {
    final amount =
        double.tryParse(_amountController.text.replaceAll(',', '').trim());
    if (amount == null || amount <= 0) {
      setState(() => _amountError = 'Enter an amount greater than 0');
      return;
    }

    _lastSource = _source;

    final title = _titleController.text.trim();
    Navigator.pop(
      context,
      QuickAddResult(
        amount: amount,
        title: title.isEmpty ? 'Payment' : title,
        type: _type,
        source: _sourceWithAccount(),
        date: _dateTime,
      ),
    );
  }

  OutlineInputBorder get _fieldBorder => OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
      );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: _accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.bolt, color: _navy, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Quick add',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          'For a payment your apps never notified you about.',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
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
                      label: Text('Sent'),
                      icon: Icon(Icons.arrow_upward),
                    ),
                    ButtonSegment(
                      value: TransactionType.credit,
                      label: Text('Received'),
                      icon: Icon(Icons.arrow_downward),
                    ),
                  ],
                  selected: {_type},
                  onSelectionChanged: (selection) {
                    setState(() => _type = selection.first);
                  },
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _amountController,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
                decoration: InputDecoration(
                  labelText: 'Amount',
                  prefixText: '₹ ',
                  errorText: _amountError,
                  border: _fieldBorder,
                ),
                onChanged: (_) {
                  if (_amountError != null) {
                    setState(() => _amountError = null);
                  }
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _titleController,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: _type == TransactionType.debit
                      ? 'Paid to (optional)'
                      : 'Received from (optional)',
                  border: _fieldBorder,
                ),
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final source in _sources)
                    ChoiceChip(
                      label: Text(source),
                      selected: _source == source,
                      showCheckmark: false,
                      selectedColor: _navy,
                      backgroundColor: _accent.withValues(alpha: 0.12),
                      side: BorderSide.none,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      labelStyle: TextStyle(
                        color: _source == source ? Colors.white : _navy,
                        fontWeight: FontWeight.w600,
                      ),
                      onSelected: (_) => setState(() => _source = source),
                    ),
                ],
              ),
              if (_accounts.isNotEmpty) ...[
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: _selectedAccountId ?? _noAccountValue,
                  decoration: InputDecoration(
                    labelText: 'Account (optional)',
                    border: _fieldBorder,
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
                    setState(() => _selectedAccountId = value);
                  },
                ),
              ],
              const SizedBox(height: 14),
              // Day 36: an editable "When" field, since a Quick Add is often
              // entered after the fact and needs its own real time.
              Material(
                color: _accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _pickDateTime,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.calendar_today_outlined,
                          size: 20,
                          color: _navy,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'When',
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _formatDateTime(_dateTime),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.edit_outlined,
                          size: 18,
                          color: Colors.grey.shade600,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _save,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Save',
                      style: TextStyle(
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
      ),
    );
  }
}