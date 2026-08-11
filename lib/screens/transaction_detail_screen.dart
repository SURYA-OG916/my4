import 'package:flutter/material.dart';
import '../models/transaction.dart';

class TransactionDetailScreen extends StatelessWidget {
  final Transaction transaction;

  const TransactionDetailScreen({super.key, required this.transaction});

  @override
  Widget build(BuildContext context) {
    final isDebit = transaction.type == TransactionType.debit;
    final color = isDebit ? Colors.red : Colors.green;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaction Detail'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Column(
                children: [
                  Icon(
                    isDebit ? Icons.arrow_upward : Icons.arrow_downward,
                    color: color,
                    size: 40,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${isDebit ? '-' : '+'}₹${transaction.amount.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            _DetailRow(label: 'Title', value: transaction.title),
            _DetailRow(label: 'Source', value: transaction.source),
            _DetailRow(label: 'Category', value: transaction.category),
            _DetailRow(
              label: 'Type',
              value: isDebit ? 'Debit' : 'Credit',
            ),
            _DetailRow(
              label: 'Date',
              value: '${transaction.date.day}/${transaction.date.month}/${transaction.date.year}',
            ),
            _DetailRow(label: 'Transaction ID', value: transaction.id),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.grey, fontSize: 14),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          ),
        ],
      ),
    );
  }
}