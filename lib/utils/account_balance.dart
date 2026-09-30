import '../db/database_helper.dart';
import '../models/bank_account.dart';
import '../models/transaction.dart';

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
///
/// Day 36: a value the user types in is only a snapshot, exactly like the
/// combined bank balance on BalanceHelper. [currentBalance] adds the
/// transactions recorded for that account since [AccountBalanceSnapshot.asOf],
/// so an account row moves as you spend and receive instead of staying frozen
/// at whatever was last typed in.
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

  /// Day 36: true if [t] is a transaction on [account] — its source names
  /// both the bank and the last 4 digits, e.g. "SBI 3742" or
  /// "Google Pay • SBI 3742". A source with no account number ("Google Pay"
  /// alone, an SBI SMS with a different last 4) never matches, so it's left
  /// out rather than guessed.
  ///
  /// Only the FIRST word of the bank name is checked, not the full string.
  /// The account's bank name is whatever the user typed into "Add account"
  /// ("SBI BANK", say), while auto-tagged sources use the shorter name the
  /// SMS/notification pipeline detects ("SBI"). Requiring the full string to
  /// match meant "SBI 3742" (from an SMS) silently failed to match an
  /// account named "SBI BANK" — the first word alone is enough to tell banks
  /// apart without being thrown off by that kind of wording difference.
  static bool belongsToAccount(Transaction t, BankAccount account) {
    final source = t.source.toLowerCase();
    final bankFirstWord = account.bank.trim().toLowerCase().split(' ').first;
    final last4 = account.last4;
    if (bankFirstWord.isEmpty) return false;
    return source.contains(bankFirstWord) && source.contains(last4);
  }

  /// Day 37: true when [d] carries no time of day (exactly midnight), which
  /// is how entries made with the date picker are stored.
  static bool _isDateOnly(DateTime d) =>
      d.hour == 0 && d.minute == 0 && d.second == 0 && d.millisecond == 0;

  /// Day 37: a transaction counts on top of the typed-in amount only if it
  /// happened AFTER the moment the amount was typed.
  ///
  /// Day 36 counted every transaction on the same calendar day as [asOf],
  /// whatever its time. That double-counted anything that had already
  /// happened earlier that day and was therefore already inside the balance
  /// the user read off their bank app (this is why SBI 3835 drifted above the
  /// real balance). Now:
  ///  * a transaction with a time counts only if it is after [asOf];
  ///  * a date-only (midnight) transaction on the same day as [asOf] still
  ///    counts, because it has no time to compare and is usually a manual
  ///    entry made after typing the balance. An earlier day never counts.
  static bool _isAfterSnapshot(DateTime date, DateTime asOf) {
    if (date.isAfter(asOf)) return true;
    final sameDay = date.year == asOf.year &&
        date.month == asOf.month &&
        date.day == asOf.day;
    return sameDay && _isDateOnly(date);
  }

  static double _signed(Transaction t) {
    return t.type == TransactionType.credit ? t.amount : -t.amount;
  }

  /// Day 37: the exact transactions [currentBalance] adds on top of the
  /// typed-in amount, so the Accounts screen can show what is being counted.
  static List<Transaction> countedTransactions(
    AccountBalanceSnapshot snapshot,
    BankAccount account,
    List<Transaction> transactions,
  ) {
    return transactions
        .where((t) =>
            belongsToAccount(t, account) &&
            _isAfterSnapshot(t.date, snapshot.asOf))
        .toList();
  }

  /// Today's balance for one account: the value the user last typed in, plus
  /// every later transaction tagged with that account (debits subtract,
  /// credits add). Transfers to the user's own names are still counted here
  /// — money that actually left or entered THIS account moves its balance,
  /// even though it's excluded from the combined "income/spent" totals
  /// elsewhere in the app.
  static double currentBalance(
    AccountBalanceSnapshot snapshot,
    BankAccount account,
    List<Transaction> transactions,
  ) {
    var balance = snapshot.amount;
    for (final t in countedTransactions(snapshot, account, transactions)) {
      balance += _signed(t);
    }
    return balance;
  }
}