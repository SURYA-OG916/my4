import '../models/transaction.dart';
import '../utils/sms_filter.dart';
import '../utils/transfer_helper.dart';

class RecurringGroup {
  final String title;
  final String category;
  final List<Transaction> occurrences;

  RecurringGroup({
    required this.title,
    required this.category,
    required this.occurrences,
  });

  double get averageAmount {
    final total = occurrences.fold<double>(0, (sum, t) => sum + t.amount);
    return total / occurrences.length;
  }

  int get monthCount {
    final months = occurrences
        .map((t) => '${t.date.year}-${t.date.month}')
        .toSet();
    return months.length;
  }

  DateTime get lastSeen {
    return occurrences
        .map((t) => t.date)
        .reduce((a, b) => a.isAfter(b) ? a : b);
  }
}

/// Detects likely recurring transactions (subscriptions, EMIs, rent, etc.)
/// by grouping debit transactions with the same normalized title and
/// checking they occur in at least [minMonths] distinct months with
/// amounts close enough to each other (within [amountTolerance] fraction).
///
/// Day 29 fix: two bugs let obvious non-subscriptions through.
///   1. Promo/OTP/reminder SMS titles (e.g. "avoid service disconnection")
///      were never excluded, so a leftover promo import that happened to
///      recur got flagged as a subscription. Now checked with the same
///      SmsFilter.looksLikePromo pattern the cleanup card uses, so the two
///      can never disagree on what counts as promo text.
///   2. Own-account Transfer-tagged transactions (e.g. one-off large
///      transfers to a person that happened to land 2 months apart) were
///      never excluded, and minMonths defaulted to 2, which is loose enough
///      for coincidence. Transfers are now excluded outright and the
///      default is raised to 3 distinct months before something counts as
///      recurring.
List<RecurringGroup> detectRecurring(
  List<Transaction> transactions, {
  int minMonths = 3,
  double amountTolerance = 0.15,
}) {
  final debitTxns = transactions.where(
    (t) =>
        t.type == TransactionType.debit &&
        !isTransfer(t) &&
        !SmsFilter.looksLikePromo(t.title) &&
        !SmsFilter.looksLikePromo(t.source),
  );

  final Map<String, List<Transaction>> grouped = {};
  for (final t in debitTxns) {
    final key = t.title.trim().toLowerCase();
    if (key.isEmpty) continue;
    grouped.putIfAbsent(key, () => []).add(t);
  }

  final List<RecurringGroup> result = [];

  grouped.forEach((key, txns) {
    final distinctMonths =
        txns.map((t) => '${t.date.year}-${t.date.month}').toSet();
    if (distinctMonths.length < minMonths) return;

    final amounts = txns.map((t) => t.amount).toList();
    final avg = amounts.reduce((a, b) => a + b) / amounts.length;
    final maxDeviation = amounts
        .map((a) => (a - avg).abs())
        .reduce((a, b) => a > b ? a : b);

    if (avg == 0 || maxDeviation / avg > amountTolerance) return;

    result.add(RecurringGroup(
      title: txns.first.title,
      category: txns.first.category,
      occurrences: txns..sort((a, b) => b.date.compareTo(a.date)),
    ));
  });

  result.sort((a, b) => b.monthCount.compareTo(a.monthCount));
  return result;
}