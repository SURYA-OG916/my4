enum TransactionType { debit, credit }

class Transaction {
  final String id;
  final String title;      // e.g. "Swiggy", "John Doe"
  final String source;     // "GPay", "PhonePe", "Bank"
  final double amount;
  final TransactionType type;
  final DateTime date;
  final String category;   // "Food", "Transfer", "Shopping" etc.

  Transaction({
    required this.id,
    required this.title,
    required this.source,
    required this.amount,
    required this.type,
    required this.date,
    required this.category,
  });
}