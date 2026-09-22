import 'package:flutter/material.dart';

import '../utils/app_lock.dart';
import 'bank_badge.dart';

/// One row per bank: logo/badge, name, account label, and its own balance.
/// The balance is masked until the user authenticates via the eye icon.
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
    return ListTile(
      leading: BankBadge(bankName: bankName),
      title: Text(bankName),
      subtitle: accountLabel == null ? null : Text(accountLabel!),
      onTap: onTap,
      trailing: ValueListenableBuilder<bool>(
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
              Text(text, style: const TextStyle(fontSize: 16)),
              IconButton(
                icon: Icon(visible ? Icons.visibility_off : Icons.visibility),
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
    );
  }
}