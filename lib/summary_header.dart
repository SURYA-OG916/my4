import 'package:flutter/material.dart';
import 'models/transaction.dart';
import 'utils/app_lock.dart';
import 'utils/transfer_helper.dart';

// Day 38: navy hero card, same palette as the Accounts screen. Income, Spent
// and Balance sit on the gradient in soft light tones.
const Color _navy = Color(0xFF1F2A44);
const Color _navySoft = Color(0xFF3B4A6B);
const Color _incomeLight = Color(0xFFA8D5B8);
const Color _spentLight = Color(0xFFFFB4A2);

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
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 14),
      margin: const EdgeInsets.fromLTRB(14, 6, 14, 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_navy, _navySoft],
        ),
        boxShadow: [
          BoxShadow(
            color: _navy.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildColumn(
              'Income',
              totalCredit,
              _incomeLight,
              onTap: onIncomeTap,
              selected: incomeSelected,
            ),
          ),
          Expanded(
            child: _buildColumn(
              'Spent',
              totalDebit,
              _spentLight,
              onTap: onSpentTap,
              selected: spentSelected,
            ),
          ),
          Expanded(
            child: balance != null
                ? _buildLockedBalanceColumn(
                    balanceLabel,
                    balance,
                    balance >= 0 ? Colors.white : _spentLight,
                  )
                : _buildColumn(
                    'Net',
                    net,
                    net >= 0 ? _incomeLight : _spentLight,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _amountText(String text, Color color) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 16.5,
        ),
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
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12.5),
        ),
        const SizedBox(height: 4),
        _amountText('₹${value.toStringAsFixed(2)}', color),
      ],
    );

    // Not a filter shortcut (for example "Net"): plain, as before.
    if (onTap == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: content,
      );
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? Colors.white.withValues(alpha: 0.16)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
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
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            if (visible) {
              AppLock.instance.hideBalances();
            } else {
              AppLock.instance.revealBalances();
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      visible
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 14,
                      color: Colors.white70,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                _amountText(
                  visible ? '₹${value.toStringAsFixed(2)}' : '₹ ••••••',
                  visible ? color : Colors.white54,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}