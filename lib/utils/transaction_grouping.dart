import '../models/transaction.dart';

Map<String, List<Transaction>> groupTransactionsByDate(List<Transaction> transactions) {
  final Map<String, List<Transaction>> grouped = {};
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));

  // Sort newest first before grouping
  final sortedTransactions = List<Transaction>.from(transactions)
    ..sort((a, b) => b.date.compareTo(a.date));

  for (final tx in sortedTransactions) {
    final txDate = DateTime(tx.date.year, tx.date.month, tx.date.day);
    String label;

    if (txDate == today) {
      label = 'Today';
    } else if (txDate == yesterday) {
      label = 'Yesterday';
    } else {
      label = '${_monthName(txDate.month)} ${txDate.day}, ${txDate.year}';
    }

    grouped.putIfAbsent(label, () => []).add(tx);
  }

  return grouped;
}

String _monthName(int month) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return months[month - 1];
}

List<dynamic> buildGroupedListItems(Map<String, List<Transaction>> grouped) {
  final List<dynamic> items = [];
  grouped.forEach((label, txs) {
    items.add(label);
    items.addAll(txs);
  });
  return items;
}