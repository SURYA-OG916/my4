import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../db/database_helper.dart';
import '../models/transaction.dart';

// Day 38: same navy palette as the rest of the app.
const Color _navy = Color(0xFF1F2A44);
const Color _navySoft = Color(0xFF3B4A6B);
const Color _accent = Color(0xFF6B8CAE);
const Color _good = Color(0xFF5A8F6E);
const Color _bad = Color(0xFFB5654A);

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

  Widget _buildHero() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_navy, _navySoft],
        ),
        boxShadow: [
          BoxShadow(
            color: _navy.withOpacity(0.25),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.ios_share, color: Colors.white),
          ),
          const SizedBox(height: 16),
          const Text(
            'Export your data',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Export all transactions to a CSV file, then choose where to '
            'save or share it: Downloads, Drive, WhatsApp, and more.',
            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: const [
              _ColumnChip('Date'),
              _ColumnChip('Title'),
              _ColumnChip('Source'),
              _ColumnChip('Category'),
              _ColumnChip('Type'),
              _ColumnChip('Amount'),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: const Text('Export Data'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
        children: [
          _buildHero(),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: _exporting ? null : _exportCsv,
              icon: _exporting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.file_download_outlined),
              label: Text(
                _exporting ? 'Exporting...' : 'Export to CSV',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_resultPath != null)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _good.withOpacity(0.10),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _good.withOpacity(0.35)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.check_circle, size: 20, color: _good),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Export successful — choose where to save it',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: _good,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SelectableText(
                    _resultPath!,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontFamily: 'monospace',
                      color: Colors.grey.shade800,
                    ),
                  ),
                ],
              ),
            ),
          if (_error != null)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _bad.withOpacity(0.10),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _bad.withOpacity(0.35)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline, size: 20, color: _bad),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Export failed: $_error',
                      style: const TextStyle(color: _bad),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ColumnChip extends StatelessWidget {
  final String label;

  const _ColumnChip(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _accent.withOpacity(0.25),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 11.5),
      ),
    );
  }
}