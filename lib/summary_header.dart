import 'package:flutter/material.dart';
import 'models/transaction.dart';
import 'utils/app_lock.dart';
import 'utils/transfer_helper.dart';

class SummaryHeader extends StatelessWidget {
  final List<Transaction> transactions;

  /// The user's current bank balance (set on the Accounts screen), or null if
  /// it hasn't been set. When null, the third column shows "Net" instead.
  final double? bankBalance;

  /// "Balance" for the current month, "Closing" for a past month.
  final String balanceLabel;

  /// Day 33: tapping Income / Spent switches the main screen's
  /// All / Received / Sent selector. When a callback is null the column is
  /// not tappable.
  final VoidCallback? onIncomeTap;
  final VoidCallback? onSpentTap;

  /// Day 33: which of the two is currently the active filter (tinted).
  final bool incomeSelected;
  final bool spentSelected;

  const SummaryHeader({
    super.key,
    required this.transactions,
    this.bankBalance,
    this.balanceLabel = 'Balance',
    this.onIncomeTap,
    this.onSpentTap,
    this.incomeSelected = false,
    this.spentSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    // Own-account transfers are not real income or spending.
    final counted = withoutTransfers(transactions);

    final double totalCredit = counted
        .where((t) => t.type == TransactionType.credit)
        .fold(0.0, (sum, t) => sum + t.amount);

    final double totalDebit = counted
        .where((t) => t.type == TransactionType.debit)
        .fold(0.0, (sum, t) => sum + t.amount);

    // "Net" is income minus spending for the selected month. It is NOT your
    // bank balance, so it is labelled differently.
    final double net = totalCredit - totalDebit;
    final double? balance = bankBalance;

    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildColumn(
            'Income',
            totalCredit,
            Colors.green,
            onTap: onIncomeTap,
            selected: incomeSelected,
          ),
          _buildColumn(
            'Spent',
            totalDebit,
            Colors.red,
            onTap: onSpentTap,
            selected: spentSelected,
          ),
          if (balance != null)
            _buildLockedBalanceColumn(
                balanceLabel, balance, balance >= 0 ? Colors.green : Colors.red)
          else
            _buildColumn('Net', net, net >= 0 ? Colors.green : Colors.red),
        ],
      ),
    );
  }

  Widget _buildColumn(
    String label,
    double value,
    Color color, {
    VoidCallback? onTap,
    bool selected = false,
  }) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
        const SizedBox(height: 4),
        Text(
          '₹${value.toStringAsFixed(2)}',
          style: TextStyle(
              color: color, fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ],
    );

    // Not a filter shortcut (for example "Net"): plain, as before.
    if (onTap == null) return content;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.10) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: content,
      ),
    );
  }

  /// Day 27: the real bank balance is hidden until the user unlocks it with
  /// their fingerprint (or phone PIN). Tap to reveal; tap again to hide.
  Widget _buildLockedBalanceColumn(String label, double value, Color color) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppLock.instance.balancesVisible,
      builder: (context, visible, _) {
        return InkWell(
          onTap: () {
            if (visible) {
              AppLock.instance.hideBalances();
            } else {
              AppLock.instance.revealBalances();
            }
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label,
                      style: const TextStyle(color: Colors.grey, fontSize: 13)),
                  const SizedBox(width: 4),
                  Icon(
                    visible ? Icons.visibility_off : Icons.visibility,
                    size: 14,
                    color: Colors.grey,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                visible ? '₹${value.toStringAsFixed(2)}' : '₹ ••••••',
                style: TextStyle(
                  color: visible ? color : Colors.grey,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}