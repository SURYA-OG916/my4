import '../models/transaction.dart';

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
List<RecurringGroup> detectRecurring(
  List<Transaction> transactions, {
  int minMonths = 2,
  double amountTolerance = 0.15,
}) {
  final debitTxns = transactions.where(
    (t) => t.type == TransactionType.debit,
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