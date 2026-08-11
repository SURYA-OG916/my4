import 'package:flutter/material.dart';
import 'models/transaction.dart';
import 'dummy_data.dart';
import 'summary_header.dart';
import 'utils/transaction_grouping.dart';
import 'screens/transaction_detail_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MY4',
      home: const TransactionListScreen(),
    );
  }
}

class TransactionListScreen extends StatelessWidget {
  const TransactionListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final grouped = groupTransactionsByDate(dummyTransactions);
    final listItems = buildGroupedListItems(grouped);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transactions'),
      ),
      body: Column(
        children: [
          SummaryHeader(transactions: dummyTransactions),
          Expanded(
            child: ListView.builder(
              itemCount: listItems.length,
              itemBuilder: (context, index) {
                final item = listItems[index];

                if (item is String) {
                  // Section header (e.g. "Today", "Yesterday", "Aug 9, 2026")
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text(
                      item,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey,
                      ),
                    ),
                  );
                }

                // Otherwise it's a Transaction
                final txn = item as Transaction;
                return ListTile(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => TransactionDetailScreen(transaction: txn),
                      ),
                    );
                  },
                  leading: Icon(
                    txn.type == TransactionType.debit
                        ? Icons.arrow_upward
                        : Icons.arrow_downward,
                    color: txn.type == TransactionType.debit
                        ? Colors.red
                        : Colors.green,
                  ),
                  title: Text(txn.title),
                  subtitle: Text('${txn.source} • ${txn.category}'),
                  trailing: Text(
                    '${txn.type == TransactionType.debit ? '-' : '+'}₹${txn.amount.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: txn.type == TransactionType.debit
                          ? Colors.red
                          : Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}