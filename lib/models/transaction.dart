enum TransactionType { credit, debit }

class Transaction {
  final String id;
  final String title;
  final String source;
  final double amount;
  final DateTime date;
  final TransactionType type;
  final String category;

  Transaction({
    required this.id,
    required this.title,
    required this.source,
    required this.amount,
    required this.date,
    required this.type,
    required this.category,
  });
}