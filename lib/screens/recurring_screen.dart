import 'package:flutter/material.dart';
import '../models/transaction.dart';
import '../utils/recurring_detector.dart';

class RecurringScreen extends StatelessWidget {
  final List<Transaction> transactions;

  const RecurringScreen({super.key, required this.transactions});

  @override
  Widget build(BuildContext context) {
    final groups = detectRecurring(transactions);

    return Scaffold(
      appBar: AppBar(title: const Text('Recurring / Subscriptions')),
      body: groups.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24.0),
                child: Text(
                  'No recurring transactions detected yet.\n'
                  'A transaction needs to repeat with a similar amount '
                  'across at least 2 months to show up here.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.builder(
              itemCount: groups.length,
              itemBuilder: (context, index) {
                final g = groups[index];
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: ListTile(
                    leading: const Icon(Icons.repeat),
                    title: Text(g.title),
                    subtitle: Text(
                      '${g.category} • ${g.monthCount} months • '
                      'last on ${g.lastSeen.day}/${g.lastSeen.month}/${g.lastSeen.year}',
                    ),
                    trailing: Text(
                      '₹${g.averageAmount.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}