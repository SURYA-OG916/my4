import 'models/transaction.dart';

List<Transaction> dummyTransactions = [
  Transaction(
    id: '1',
    title: 'Swiggy',
    source: 'GPay',
    amount: 350.0,
    type: TransactionType.debit,
    date: DateTime.now().subtract(const Duration(days: 2)),
    category: 'Food',
  ),
  Transaction(
    id: '2',
    title: 'Salary Credit',
    source: 'Bank',
    amount: 45000.0,
    type: TransactionType.credit,
    date: DateTime.now().subtract(const Duration(days: 4)),
    category: 'Income',
  ),
  Transaction(
    id: '3',
    title: 'Amazon',
    source: 'PhonePe',
    amount: 1200.0,
    type: TransactionType.debit,
    date: DateTime.now().subtract(const Duration(days: 5)),
    category: 'Shopping',
  ),
  Transaction(
    id: '4',
    title: 'Netflix',
    source: 'GPay',
    amount: 649.0,
    type: TransactionType.debit,
    date: DateTime.now().subtract(const Duration(days: 6)),
    category: 'Subscription',
  ),
];