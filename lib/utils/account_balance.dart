import '../db/database_helper.dart';

/// A balance the user typed in for one bank account, and when they typed it.
class AccountBalanceSnapshot {
  final double amount;
  final DateTime asOf;

  const AccountBalanceSnapshot({required this.amount, required this.asOf});
}

/// Individual balances for the accounts on the Accounts & balance page.
/// MY4 can't read a bank's balance, so these are values the user enters.
/// (Slice is different: its balance comes from its own notifications, see
/// slice_balance.dart.)
class AccountBalance {
  static String _amountKey(String accountId) =>
      'account_balance_amount_$accountId';
  static String _asOfKey(String accountId) => 'account_balance_as_of_$accountId';

  static Future<AccountBalanceSnapshot?> load(String accountId) async {
    final amountText =
        await DatabaseHelper.instance.getSetting(_amountKey(accountId));
    final asOfText =
        await DatabaseHelper.instance.getSetting(_asOfKey(accountId));
    if (amountText == null || asOfText == null) return null;

    final amount = double.tryParse(amountText);
    final asOf = DateTime.tryParse(asOfText);
    if (amount == null || asOf == null) return null;

    return AccountBalanceSnapshot(amount: amount, asOf: asOf);
  }

  static Future<void> save(
    String accountId,
    double amount,
    DateTime asOf,
  ) async {
    await DatabaseHelper.instance
        .setSetting(_amountKey(accountId), amount.toString());
    await DatabaseHelper.instance
        .setSetting(_asOfKey(accountId), asOf.toIso8601String());
  }

  static Future<void> clear(String accountId) async {
    await DatabaseHelper.instance.deleteSetting(_amountKey(accountId));
    await DatabaseHelper.instance.deleteSetting(_asOfKey(accountId));
  }
}