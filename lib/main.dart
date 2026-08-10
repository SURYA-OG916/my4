import 'package:flutter/material.dart';
import 'models/transaction.dart';
import 'dummy_data.dart';
import 'summary_header.dart';

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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transactions'),
      ),
      body: Column(
        children: [
          SummaryHeader(transactions: dummyTransactions),
          Expanded(
            child: ListView.builder(
              itemCount: dummyTransactions.length,
              itemBuilder: (context, index) {
                final txn = dummyTransactions[index];
                return ListTile(
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