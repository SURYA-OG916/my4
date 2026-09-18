import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../models/transaction.dart' as model;
import '../utils/date_range_helper.dart';

class MonthlySpend {
  final DateTime month;
  final double total;

  MonthlySpend({required this.month, required this.total});
}

class TrendsScreen extends StatefulWidget {
  const TrendsScreen({super.key});

  @override
  State<TrendsScreen> createState() => _TrendsScreenState();
}

class _TrendsScreenState extends State<TrendsScreen> {
  bool _loading = true;
  List<MonthlySpend> _monthlySpend = [];

  static const int _monthsToShow = 6;

  @override
  void initState() {
    super.initState();
    _loadTrends();
  }

  Future<void> _loadTrends() async {
    final transactions = await DatabaseHelper.instance.getAllTransactions();

    final now = DateTime.now();
    final months = <DateTime>[];
    for (int i = _monthsToShow - 1; i >= 0; i--) {
      months.add(DateTime(now.year, now.month - i, 1));
    }

    final result = <MonthlySpend>[];
    for (final month in months) {
      final start = DateRangeHelper.startOfMonth(month);
      final end = DateRangeHelper.endOfMonth(month);

      double total = 0;
      for (final t in transactions) {
        if (t.type == model.TransactionType.debit &&
            !t.date.isBefore(start) &&
            !t.date.isAfter(end)) {
          total += t.amount;
        }
      }

      result.add(MonthlySpend(month: month, total: total));
    }

    if (!mounted) return;
    setState(() {
      _monthlySpend = result;
      _loading = false;
    });
  }

  String _monthLabel(DateTime month) {
    const names = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${names[month.month - 1]} ${month.year % 100}';
  }

  void _onBarTapped(DateTime month) {
    // Pop back to the transaction list with the tapped month so the caller
    // can switch its selected month filter.
    Navigator.pop(context, month);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Spending Trends')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _monthlySpend.isEmpty
              ? const Center(child: Text('No data yet'))
              : Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Last $_monthsToShow months',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tap a bar to view that month',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey,
                            ),
                      ),
                      const SizedBox(height: 20),
                      Expanded(child: _buildChart(context)),
                    ],
                  ),
                ),
    );
  }

  Widget _buildChart(BuildContext context) {
    final maxSpend = _monthlySpend
        .map((m) => m.total)
        .fold<double>(0, (a, b) => a > b ? a : b);
    final safeMax = maxSpend == 0 ? 1.0 : maxSpend;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Reserve space for the amount label above the bar and the month
        // label below it, plus a little breathing room to avoid overflow.
        const reservedForLabels = 70.0;
        final availableHeight =
            (constraints.maxHeight - reservedForLabels).clamp(0.0, double.infinity);

        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: _monthlySpend.map((m) {
            final barHeight =
                ((m.total / safeMax) * availableHeight).clamp(0.0, availableHeight);
            final isCurrent = m.month.year == DateTime.now().year &&
                m.month.month == DateTime.now().month;

            return Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _onBarTapped(m.month),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        m.total > 0 ? '₹${m.total.toStringAsFixed(0)}' : '',
                        style: const TextStyle(fontSize: 11),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        height: barHeight,
                        decoration: BoxDecoration(
                          color: isCurrent
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withOpacity(0.5),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _monthLabel(m.month),
                        style: const TextStyle(fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}