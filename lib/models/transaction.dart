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

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'source': source,
      'amount': amount,
      'type': type == TransactionType.credit ? 'credit' : 'debit',
      'date': date.toIso8601String(),
      'category': category,
    };
  }

  factory Transaction.fromMap(Map<String, dynamic> map) {
    return Transaction(
      id: map['id'],
      title: map['title'],
      source: map['source'],
      amount: map['amount'],
      date: DateTime.parse(map['date']),
      type: map['type'] == 'credit' ? TransactionType.credit : TransactionType.debit,
      category: map['category'],
    );
  }
}