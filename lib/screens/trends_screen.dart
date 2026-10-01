import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../models/transaction.dart' as model;
import '../utils/date_range_helper.dart';
import '../utils/transfer_helper.dart';

// Day 38: same palette as the Accounts screen.
const Color _navy = Color(0xFF1F2A44);
const Color _navySoft = Color(0xFF3B4A6B);
const Color _accent = Color(0xFF6B8CAE);

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
        // Day 30: Transfers aren't real spend, excluded the same way
        // Category Summary and Recurring detection already do.
        if (t.category == transferCategory) continue;
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
      appBar: AppBar(
        title: const Text('Spending Trends'),
        centerTitle: false,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _monthlySpend.isEmpty
              ? const Center(child: Text('No data yet'))
              : Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSummaryCard(),
                      const SizedBox(height: 14),
                      Expanded(child: _buildChartCard(context)),
                    ],
                  ),
                ),
    );
  }

  // Hero card: this month's spend, the average, and the change vs last month.
  Widget _buildSummaryCard() {
    final current = _monthlySpend.last;
    final previous =
        _monthlySpend.length >= 2 ? _monthlySpend[_monthlySpend.length - 2] : null;

    final withData = _monthlySpend.where((m) => m.total > 0).toList();
    final average = withData.isEmpty
        ? 0.0
        : withData.fold<double>(0, (s, m) => s + m.total) / withData.length;

    double? changePct;
    if (previous != null && previous.total > 0) {
      changePct = ((current.total - previous.total) / previous.total) * 100;
    }

    return Container(
      width: double.infinity,
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
            'Spent in ${_monthLabel(current.month)}',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 6),
          Text(
            '₹${current.total.toStringAsFixed(2)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _stat(
                  'Monthly average',
                  '₹${average.toStringAsFixed(0)}',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: _changeStat(changePct, previous)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 11.5),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _changeStat(double? changePct, MonthlySpend? previous) {
    final label = previous == null
        ? 'vs last month'
        : 'vs ${_monthLabel(previous.month)}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 11.5),
          ),
          const SizedBox(height: 2),
          if (changePct == null)
            const Text(
              '—',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            )
          else
            Row(
              children: [
                Icon(
                  changePct >= 0 ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 15,
                  color: changePct >= 0
                      ? const Color(0xFFFFB4A2)
                      : const Color(0xFFA8D5B8),
                ),
                const SizedBox(width: 4),
                Text(
                  '${changePct.abs().toStringAsFixed(0)}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildChartCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant.withOpacity(0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Last $_monthsToShow months',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Tap a bar to view that month',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
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
        final now = DateTime.now();

        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: _monthlySpend.map((m) {
            final barHeight =
                ((m.total / safeMax) * availableHeight).clamp(0.0, availableHeight);
            final isCurrent =
                m.month.year == now.year && m.month.month == now.month;

            return Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _onBarTapped(m.month),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        m.total > 0 ? '₹${m.total.toStringAsFixed(0)}' : '',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight:
                              isCurrent ? FontWeight.w700 : FontWeight.w500,
                          color: isCurrent ? _navy : Colors.grey.shade700,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        height: barHeight,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: isCurrent
                              ? _navy
                              : _accent.withOpacity(0.45),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _monthLabel(m.month),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              isCurrent ? FontWeight.w700 : FontWeight.w400,
                          color: isCurrent ? _navy : Colors.grey.shade700,
                        ),
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