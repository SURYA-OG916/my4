import '../db/database_helper.dart';
import '../models/transaction.dart';
import 'slice_balance.dart';
import 'transfer_helper.dart';

/// The bank balance the user last typed in, and when they typed it.
///
/// [sliceAmount] is the separate Slice balance (from Slice notifications).
/// It is added on top when working out today's balance, so the main screen
/// shows bank accounts + Slice. It is 0 unless the snapshot was loaded with
/// includeSlice.
class BalanceSnapshot {
  final double amount;
  final DateTime asOf;
  final double sliceAmount;

  const BalanceSnapshot({
    required this.amount,
    required this.asOf,
    this.sliceAmount = 0,
  });
}

/// MY4 can't read your real bank balance, so the "actual balance" works like
/// this: you enter what your banks show right now (a snapshot), and MY4 keeps
/// it current by adding credits and subtracting debits recorded AFTER that
/// moment. Transfers between your own accounts are ignored, since they
/// don't change your total.
///
/// Day 28: Slice is a separate account with its own balance, so Slice
/// transactions are left out of this calculation (otherwise the same money
/// would be counted twice). Today's balance = bank accounts + the Slice
/// balance; a past month's closing balance covers bank accounts only.
class BalanceHelper {
  static const String _amountKey = 'bank_balance_amount';
  static const String _asOfKey = 'bank_balance_as_of';

  /// [includeSlice]: when true (the default, used by the main screen) the
  /// Slice balance is carried in the snapshot and added to today's balance.
  /// The Accounts screen passes false so its "Bank balance" card stays
  /// bank-only.
  static Future<BalanceSnapshot?> loadSnapshot({
    bool includeSlice = true,
  }) async {
    final amountText = await DatabaseHelper.instance.getSetting(_amountKey);
    final asOfText = await DatabaseHelper.instance.getSetting(_asOfKey);
    if (amountText == null || asOfText == null) return null;

    final amount = double.tryParse(amountText);
    final asOf = DateTime.tryParse(asOfText);
    if (amount == null || asOf == null) return null;

    var sliceAmount = 0.0;
    if (includeSlice) {
      final slice = await SliceBalance.load();
      if (slice != null) sliceAmount = slice.amount;
    }

    return BalanceSnapshot(
      amount: amount,
      asOf: asOf,
      sliceAmount: sliceAmount,
    );
  }

  static Future<void> saveSnapshot(double amount, DateTime asOf) async {
    await DatabaseHelper.instance.setSetting(_amountKey, amount.toString());
    await DatabaseHelper.instance.setSetting(_asOfKey, asOf.toIso8601String());
  }

  static Future<void> clearSnapshot() async {
    await DatabaseHelper.instance.deleteSetting(_amountKey);
    await DatabaseHelper.instance.deleteSetting(_asOfKey);
  }

  /// True if a transaction dated [date] counts as recorded AFTER the balance
  /// was set at [asOf].
  ///
  /// Anything with a time after [asOf] counts. Entries that carry only a date
  /// (time 00:00, as manual entries and some SMS do) and fall on the same day
  /// as [asOf] also count: they were most likely added after you set the
  /// balance, and treating them as earlier would make the balance ignore
  /// them. Entries dated on earlier days are assumed to be already included
  /// in the balance you typed.
  static bool _isAfterSnapshot(DateTime date, DateTime asOf) {
    if (date.isAfter(asOf)) return true;

    final dateOnly = date.hour == 0 &&
        date.minute == 0 &&
        date.second == 0 &&
        date.millisecond == 0;
    final sameDay = date.year == asOf.year &&
        date.month == asOf.month &&
        date.day == asOf.day;
    return dateOnly && sameDay;
  }

  static double _signed(Transaction t) {
    return t.type == TransactionType.credit ? t.amount : -t.amount;
  }

  /// Transfers between own accounts and Slice transactions don't move the
  /// bank-account balance.
  static bool _skipForBank(Transaction t) {
    return isTransfer(t) || isSliceSource(t.source);
  }

  /// Today's balance: the bank balance the user set, adjusted by later bank
  /// transactions, plus the separate Slice balance.
  static double currentBalance(
    BalanceSnapshot snapshot,
    List<Transaction> transactions,
  ) {
    var balance = snapshot.amount;
    for (final t in transactions) {
      if (_skipForBank(t)) continue;
      if (!_isAfterSnapshot(t.date, snapshot.asOf)) continue;
      balance += _signed(t);
    }
    return balance + snapshot.sliceAmount;
  }

  /// The very last moment of [month] (any day in that month works).
  static DateTime endOfMonth(DateTime month) {
    return DateTime(month.year, month.month + 1, 1)
        .subtract(const Duration(microseconds: 1));
  }

  /// Estimated bank balance at the moment [at] (Slice not included). After the
  /// snapshot it adds the transactions recorded between the snapshot and
  /// [at]; before the snapshot it walks backwards, undoing the transactions
  /// recorded between [at] and the snapshot. Transfers and Slice transactions
  /// are ignored either way. It is only as complete as the transactions MY4
  /// has recorded.
  static double balanceAt(
    BalanceSnapshot snapshot,
    List<Transaction> transactions,
    DateTime at,
  ) {
    var balance = snapshot.amount;

    if (!at.isBefore(snapshot.asOf)) {
      for (final t in transactions) {
        if (_skipForBank(t)) continue;
        if (_isAfterSnapshot(t.date, snapshot.asOf) && !t.date.isAfter(at)) {
          balance += _signed(t);
        }
      }
    } else {
      for (final t in transactions) {
        if (_skipForBank(t)) continue;
        if (!_isAfterSnapshot(t.date, snapshot.asOf) && t.date.isAfter(at)) {
          balance -= _signed(t);
        }
      }
    }

    return balance;
  }
}