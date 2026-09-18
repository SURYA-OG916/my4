import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../db/database_helper.dart';
import '../models/transaction.dart';

class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key});

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  bool _exporting = false;
  String? _resultPath;
  String? _error;

  String _csvEscape(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  String _formatDate(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd/$mm/${d.year}';
  }

  Future<void> _exportCsv() async {
    setState(() {
      _exporting = true;
      _error = null;
      _resultPath = null;
    });

    try {
      final transactions = await DatabaseHelper.instance.getAllTransactions();

      // Oldest first reads more naturally in a spreadsheet export.
      transactions.sort((a, b) => a.date.compareTo(b.date));

      final buffer = StringBuffer();
      buffer.writeln('Date,Title,Source,Category,Type,Amount');

      for (final t in transactions) {
        final row = [
          _formatDate(t.date),
          _csvEscape(t.title),
          _csvEscape(t.source),
          _csvEscape(t.category),
          t.type == TransactionType.debit ? 'Debit' : 'Credit',
          t.amount.toStringAsFixed(2),
        ].join(',');
        buffer.writeln(row);
      }

      final dir = await getExternalStorageDirectory();
      if (dir == null) {
        throw Exception('Could not access external storage directory');
      }

      final now = DateTime.now();
      final fileName =
          'my4_export_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}.csv';
      final file = File('${dir.path}/$fileName');
      await file.writeAsString(buffer.toString());

      if (!mounted) return;
      setState(() {
        _resultPath = file.path;
        _exporting = false;
      });

      // Hand off to the system share sheet so the user can save it to
      // Downloads, Drive, WhatsApp, etc. — the app-private folder above is
      // just a staging location, not meant to be the final destination.
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'MY4 transaction export',
        text: 'MY4 transaction export ($fileName)',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _exporting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Export Data')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Export all transactions to a CSV file, then choose where to '
              'save or share it — Downloads, Drive, WhatsApp, and more.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _exporting ? null : _exportCsv,
              icon: const Icon(Icons.file_download),
              label: Text(_exporting ? 'Exporting...' : 'Export to CSV'),
            ),
            const SizedBox(height: 24),
            if (_resultPath != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.withOpacity(0.4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Export successful — choose where to save it',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      _resultPath!,
                      style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withOpacity(0.4)),
                ),
                child: Text(
                  'Export failed: $_error',
                  style: const TextStyle(color: Colors.red),
                ),
              ),
          ],
        ),
      ),
    );
  }
}