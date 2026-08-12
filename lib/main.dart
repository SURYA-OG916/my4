import 'package:flutter/material.dart';
import 'models/transaction.dart';
import 'dummy_data.dart';
import 'summary_header.dart';
import 'utils/transaction_grouping.dart';
import 'screens/transaction_detail_screen.dart';
import 'widgets/category_filter_chips.dart';

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

class TransactionListScreen extends StatefulWidget {
  const TransactionListScreen({super.key});

  @override
  State<TransactionListScreen> createState() => _TransactionListScreenState();
}

class _TransactionListScreenState extends State<TransactionListScreen> {
  String selectedCategory = 'All';

  @override
  Widget build(BuildContext context) {
    // Build category list dynamically from the data ('All' + unique categories)
    final categories = ['All', ...{for (var t in dummyTransactions) t.category}];

    // Apply filter before grouping
    final filteredTransactions = selectedCategory == 'All'
        ? dummyTransactions
        : dummyTransactions.where((t) => t.category == selectedCategory).toList();

    final grouped = groupTransactionsByDate(filteredTransactions);
    final listItems = buildGroupedListItems(grouped);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transactions'),
      ),
      body: Column(
        children: [
          SummaryHeader(transactions: dummyTransactions),
          const SizedBox(height: 8),
          CategoryFilterChips(
            categories: categories,
            selectedCategory: selectedCategory,
            onCategorySelected: (category) {
              setState(() {
                selectedCategory = category;
              });
            },
          ),
          const SizedBox(height: 8),
          Expanded(
            child: listItems.isEmpty
                ? const Center(child: Text('No transactions in this category'))
                : ListView.builder(
                    itemCount: listItems.length,
                    itemBuilder: (context, index) {
                      final item = listItems[index];

                      if (item is String) {
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