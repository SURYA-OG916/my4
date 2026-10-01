import 'package:flutter/material.dart';

import '../utils/app_lock.dart';
import 'bank_badge.dart';

/// One row per bank: logo/badge, name, account label, and its own balance.
/// The balance is masked until the user authenticates via the eye icon.
///
/// Day 38: rebuilt without ListTile so the account label gets the full width
/// under the bank name (it used to wrap onto four lines), and the balance and
/// eye icon sit together on the right.
class BankBalanceTile extends StatelessWidget {
  final String bankName;
  final String? accountLabel;
  final double? balance;
  final VoidCallback? onTap;

  const BankBalanceTile({
    super.key,
    required this.bankName,
    this.accountLabel,
    this.balance,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
            child: Row(
              children: [
                BankBadge(bankName: bankName, size: 42),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bankName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (accountLabel != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          accountLabel!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.3,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                ValueListenableBuilder<bool>(
                  valueListenable: AppLock.instance.balancesVisible,
                  builder: (context, visible, _) {
                    final text = balance == null
                        ? 'Not set'
                        : visible
                            ? '₹${balance!.toStringAsFixed(2)}'
                            : '₹ ••••••';
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          text,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: balance == null
                                ? Colors.grey.shade500
                                : null,
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                          padding: EdgeInsets.zero,
                          icon: Icon(
                            visible
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            size: 20,
                            color: Colors.grey.shade600,
                          ),
                          onPressed: () {
                            if (visible) {
                              AppLock.instance.hideBalances();
                            } else {
                              AppLock.instance.revealBalances();
                            }
                          },
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}