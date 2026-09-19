import 'package:flutter/material.dart';
import '../models/transaction.dart';

/// What the quick-add sheet collects. The caller turns it into a Transaction
/// (dated now, category guessed) and runs the usual duplicate checks.
class QuickAddResult {
  final double amount;
  final String title;
  final TransactionType type;
  final String source;

  const QuickAddResult({
    required this.amount,
    required this.title,
    required this.type,
    required this.source,
  });
}

/// UPI apps don't notify you about money you send, so this is the fast way
/// to record it: amount, who, and which app. Everything else is filled in.
Future<QuickAddResult?> showQuickAddSheet(BuildContext context) {
  return showModalBottomSheet<QuickAddResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
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

  @override
  void dispose() {
    _amountController.dispose();
    _titleController.dispose();
    super.dispose();
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
        source: _source,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Quick add',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'Saved with today\'s date and time.',
                style: TextStyle(color: Colors.grey.shade700),
              ),
              const SizedBox(height: 16),
              SegmentedButton<TransactionType>(
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
              const SizedBox(height: 16),
              TextField(
                controller: _amountController,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Amount',
                  prefixText: '₹ ',
                  errorText: _amountError,
                  border: const OutlineInputBorder(),
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
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final source in _sources)
                    ChoiceChip(
                      label: Text(source),
                      selected: _source == source,
                      onSelected: (_) => setState(() => _source = source),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _save,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Save'),
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