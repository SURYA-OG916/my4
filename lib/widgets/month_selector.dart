import 'package:flutter/material.dart';

// Day 38: soft round arrow buttons, a bolder month name, and a small
// "Back to this month" link that appears when you are on another month.
const Color _navy = Color(0xFF1F2A44);
const Color _accent = Color(0xFF6B8CAE);

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

  void _goToCurrentMonth() {
    final now = DateTime.now();
    onMonthChanged(DateTime(now.year, now.month, 1));
  }

  Widget _arrowButton({
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    final enabled = onPressed != null;
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon),
      iconSize: 22,
      style: IconButton.styleFrom(
        backgroundColor:
            enabled ? _accent.withValues(alpha: 0.14) : Colors.transparent,
        foregroundColor: _navy,
        disabledForegroundColor: Colors.grey.shade400,
      ),
    );
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
          _arrowButton(
            icon: Icons.chevron_left,
            onPressed: _goToPreviousMonth,
          ),
          SizedBox(
            width: 190,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${_monthNames[selectedMonth.month - 1]} ${selectedMonth.year}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: _navy,
                  ),
                ),
                if (!isCurrentMonth)
                  InkWell(
                    onTap: _goToCurrentMonth,
                    borderRadius: BorderRadius.circular(8),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      child: Text(
                        'Back to this month',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: _accent,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          _arrowButton(
            icon: Icons.chevron_right,
            onPressed: isCurrentMonth ? null : _goToNextMonth,
          ),
        ],
      ),
    );
  }
}