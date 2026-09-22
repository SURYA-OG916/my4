import '../db/database_helper.dart';

/// The balance shown in Slice's own notifications ("Avl. Bal. ₹2.14"),
/// and when that notification was posted.
class SliceBalanceSnapshot {
  final double amount;
  final DateTime asOf;

  const SliceBalanceSnapshot({required this.amount, required this.asOf});
}

/// Slice is a separate account (not one of the user's normal bank accounts),
/// so its balance is tracked on its own. It is only updated when the user
/// approves a Slice payment, and never with an older notification than the
/// one already stored.
class SliceBalance {
  static const String _amountKey = 'slice_balance_amount';
  static const String _asOfKey = 'slice_balance_as_of';

  static Future<SliceBalanceSnapshot?> load() async {
    final amountText = await DatabaseHelper.instance.getSetting(_amountKey);
    final asOfText = await DatabaseHelper.instance.getSetting(_asOfKey);
    if (amountText == null || asOfText == null) return null;

    final amount = double.tryParse(amountText);
    final asOf = DateTime.tryParse(asOfText);
    if (amount == null || asOf == null) return null;

    return SliceBalanceSnapshot(amount: amount, asOf: asOf);
  }

  static Future<void> _store(double amount, DateTime asOf) async {
    await DatabaseHelper.instance.setSetting(_amountKey, amount.toString());
    await DatabaseHelper.instance.setSetting(_asOfKey, asOf.toIso8601String());
  }

  /// Saves [amount] only if [asOf] is newer than what is already stored, so
  /// approving an old notification can't overwrite a newer balance.
  static Future<void> saveIfNewer(double amount, DateTime asOf) async {
    final existing = await load();
    if (existing != null && !asOf.isAfter(existing.asOf)) return;
    await _store(amount, asOf);
  }

  /// Applies a payment that carries no balance figure of its own, for example
  /// the SMS Slice sends when you SEND money ("Rs. 5,000 sent from a/c ...").
  /// [signedAmount] is negative for money sent. Does nothing if there is no
  /// stored balance yet, or if the payment is older than the stored balance
  /// (that balance already includes it).
  static Future<void> applyPayment({
    required double signedAmount,
    required DateTime date,
  }) async {
    final existing = await load();
    if (existing == null) return;
    if (!date.isAfter(existing.asOf)) return;

    final updated = ((existing.amount + signedAmount) * 100).round() / 100;
    await _store(updated, date);
  }

  static Future<void> clear() async {
    await DatabaseHelper.instance.deleteSetting(_amountKey);
    await DatabaseHelper.instance.deleteSetting(_asOfKey);
  }
}

/// True if a transaction source / bank name belongs to Slice: the Slice app
/// ("Slice • 9809"), the Slice bank account ("Slice"), or Slice's SMS sender
/// ("VM-SLCBNK-T"). Slice money is tracked separately from the user's other
/// bank accounts.
bool isSliceSource(String source) {
  final lower = source.toLowerCase();
  return lower.contains('slice') || lower.contains('slcbnk');
}