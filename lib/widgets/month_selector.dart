import 'package:flutter/material.dart';

class MonthSelector extends StatelessWidget {
  final DateTime selectedMonth;
  final ValueChanged<DateTime> onMonthChanged;

  const MonthSelector({
    super.key,
    required this.selectedMonth,
    required this.onMonthChanged,
  });

  static const List<String> _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  void _goToPreviousMonth() {
    final prev = DateTime(selectedMonth.year, selectedMonth.month - 1, 1);
    onMonthChanged(prev);
  }

  void _goToNextMonth() {
    final next = DateTime(selectedMonth.year, selectedMonth.month + 1, 1);
    onMonthChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isCurrentMonth =
        selectedMonth.year == now.year && selectedMonth.month == now.month;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: _goToPreviousMonth,
          ),
          SizedBox(
            width: 160,
            child: Text(
              '${_monthNames[selectedMonth.month - 1]} ${selectedMonth.year}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: isCurrentMonth ? null : _goToNextMonth,
          ),
        ],
      ),
    );
  }
}