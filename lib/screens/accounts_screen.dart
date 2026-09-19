import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../models/bank_account.dart';
import '../models/transaction.dart';
import '../utils/balance_helper.dart';
import '../utils/notification_ingestor.dart';
import '../utils/notification_parser.dart';
import '../utils/transfer_helper.dart';

String _two(int n) => n.toString().padLeft(2, '0');

String _formatDate(DateTime d) => '${_two(d.day)}/${_two(d.month)}/${d.year}';

String _formatDateTime(DateTime d) =>
    '${_formatDate(d)} ${_two(d.hour)}:${_two(d.minute)}';

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  bool _loading = true;
  String? _error;

  List<BankAccount> _accounts = [];
  List<String> _myNames = [];
  Map<String, Set<String>> _links = {};
  BalanceSnapshot? _snapshot;
  List<Transaction> _transactions = [];
  Map<String, DateTime> _lastSeen = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final db = DatabaseHelper.instance;
      final accounts = await db.getAllAccounts();
      final names = await db.getMyNames();
      final links = await db.getAppLinks();
      final snapshot = await BalanceHelper.loadSnapshot();
      final transactions = await db.getAllTransactions();

      var lastSeen = <String, DateTime>{};
      try {
        lastSeen = await NotificationIngestor.lastSeenByApp();
      } catch (_) {
        // Notification bridge unavailable; the app list just shows no activity.
      }

      if (!mounted) return;
      setState(() {
        _accounts = accounts;
        _myNames = names;
        _links = links;
        _snapshot = snapshot;
        _transactions = transactions;
        _lastSeen = lastSeen;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // ---------------------------------------------------------------- balance

  Future<void> _editBalance() async {
    final controller = TextEditingController();
    final value = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Current bank balance'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter the total balance across all your bank accounts right '
              'now (check your bank app).',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                prefixText: '₹ ',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final parsed =
                  double.tryParse(controller.text.replaceAll(',', '').trim());
              if (parsed == null) return;
              Navigator.pop(ctx, parsed);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (value == null) return;
    await BalanceHelper.saveSnapshot(value, DateTime.now());
    await _load();
  }

  Future<void> _clearBalance() async {
    await BalanceHelper.clearSnapshot();
    await _load();
  }

  Widget _buildBalanceCard() {
    final snapshot = _snapshot;

    if (snapshot == null) {
      return _section(
        title: 'Bank balance',
        subtitle:
            "Not set. MY4 can't read your bank balance, so enter it once and "
            'it will keep it up to date from your transactions.',
        child: Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            onPressed: _editBalance,
            child: const Text('Set balance'),
          ),
        ),
      );
    }

    final current = BalanceHelper.currentBalance(snapshot, _transactions);

    return _section(
      title: 'Bank balance',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '₹${current.toStringAsFixed(2)}',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color:
                      current >= 0 ? Colors.green.shade800 : Colors.red.shade800,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'You set ₹${snapshot.amount.toStringAsFixed(2)} on '
            '${_formatDateTime(snapshot.asOf)}. Income and spending recorded '
            'after that are added or subtracted automatically; transfers '
            'between your own accounts are ignored.',
            style: TextStyle(color: Colors.grey.shade700),
          ),
          const SizedBox(height: 4),
          Text(
            "Payments MY4 can't see (for example small SBI debits with no SMS) "
            'are not included, so update this now and then.',
            style: TextStyle(color: Colors.grey.shade700),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _clearBalance,
                child: const Text('Clear'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _editBalance,
                child: const Text('Update balance'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------- accounts

  Future<void> _addAccount() async {
    final bankController = TextEditingController();
    final last4Controller = TextEditingController();

    final account = await showDialog<BankAccount>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add bank account'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: bankController,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Bank (for example SBI)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: last4Controller,
              keyboardType: TextInputType.number,
              maxLength: 4,
              decoration: const InputDecoration(
                labelText: 'Last 4 digits',
                helperText: 'Exactly 4 digits',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final bank = bankController.text.trim();
              final last4 = last4Controller.text.trim();
              if (bank.isEmpty || !RegExp(r'^\d{4}$').hasMatch(last4)) return;
              Navigator.pop(
                ctx,
                BankAccount(
                  id: 'acc_${DateTime.now().microsecondsSinceEpoch}',
                  bank: bank,
                  last4: last4,
                ),
              );
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (account == null) return;
    await DatabaseHelper.instance.insertAccount(account);
    await _load();
  }

  Future<void> _deleteAccount(BankAccount account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove account?'),
        content: Text(
          'Remove ${account.label}? Your transactions are not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await DatabaseHelper.instance.deleteAccount(account.id);
    await _load();
  }

  Widget _buildAccountsCard() {
    return _section(
      title: 'Bank accounts',
      subtitle: 'The accounts you use with UPI. Only the last 4 digits are kept.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_accounts.isEmpty)
            Text(
              'No accounts added yet.',
              style: TextStyle(color: Colors.grey.shade700),
            ),
          for (final account in _accounts)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.account_balance),
              title: Text(account.bank),
              subtitle: Text('Account ending ${account.last4}'),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Remove',
                onPressed: () => _deleteAccount(account),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _addAccount,
              icon: const Icon(Icons.add),
              label: const Text('Add account'),
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------- UPI apps

  Future<void> _toggleLink(String appKey, String accountId, bool linked) async {
    await DatabaseHelper.instance.setAppLink(
      appKey: appKey,
      accountId: accountId,
      linked: linked,
    );
    await _load();
  }

  Widget _buildAppsCard() {
    final apps =
        upiAppLabels.entries.where((e) => e.key != 'com.android.shell');

    return _section(
      title: 'UPI apps',
      subtitle:
          'Payment apps MY4 listens to, and which of your accounts each one uses.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final app in apps) ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.phone_android),
              title: Text(app.value),
              subtitle: Text(
                _lastSeen[app.key] != null
                    ? 'Last payment notification: ${_formatDateTime(_lastSeen[app.key]!)}'
                    : 'No payment notifications captured yet',
              ),
            ),
            if (_accounts.isEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  'Add a bank account above to link it to this app.',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final account in _accounts)
                      FilterChip(
                        label: Text(account.label),
                        selected:
                            _links[app.key]?.contains(account.id) ?? false,
                        onSelected: (selected) =>
                            _toggleLink(app.key, account.id, selected),
                      ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  // --------------------------------------------------------------- my names

  Future<void> _addName() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add a name of yours'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Use the name your payment apps show when you send money to '
              'yourself. A short form like "Sivakumar" also matches longer '
              'ones that contain it.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.length < 4) return;
              Navigator.pop(ctx, value);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (name == null) return;

    final alreadySaved =
        _myNames.any((n) => n.toLowerCase() == name.toLowerCase());
    if (!alreadySaved) {
      await DatabaseHelper.instance.addMyName(name);
    }
    await _load();
    await _retagExisting(name);
  }

  Future<void> _deleteName(String name) async {
    await DatabaseHelper.instance.deleteMyName(name);
    await _load();
  }

  // Offer to tag transactions already in the list that match the new name.
  Future<void> _retagExisting(String name) async {
    final all = await DatabaseHelper.instance.getAllTransactions();
    final matches = all
        .where((t) => !isTransfer(t) && matchesOwnName(t.title, [name]))
        .toList();
    if (matches.isEmpty || !mounted) return;

    final preview = matches.take(6).toList();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Tag ${matches.length} existing '
          'transaction${matches.length == 1 ? '' : 's'} as Transfer?',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final t in preview)
              Text(
                '${t.title} • ${t.type == TransactionType.credit ? '+' : '-'}'
                '₹${t.amount.toStringAsFixed(2)} • ${_formatDate(t.date)}',
              ),
            if (matches.length > preview.length)
              Text('…and ${matches.length - preview.length} more'),
            const SizedBox(height: 8),
            const Text(
              'Transfers stay in the list but no longer count as income or '
              'spending.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Skip'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Tag as Transfer'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    for (final t in matches) {
      await DatabaseHelper.instance.updateTransaction(
        Transaction(
          id: t.id,
          title: t.title,
          source: t.source,
          amount: t.amount,
          date: t.date,
          type: t.type,
          category: transferCategory,
        ),
      );
    }
    _snack(
      'Tagged ${matches.length} '
      'transaction${matches.length == 1 ? '' : 's'} as Transfer',
    );
    await _load();
  }

  Widget _buildNamesCard() {
    return _section(
      title: 'My names',
      subtitle:
          'Payments to or from these names are treated as transfers between '
          'your own accounts, not income or spending.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_myNames.isEmpty)
            Text(
              'No names added yet.',
              style: TextStyle(color: Colors.grey.shade700),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final name in _myNames)
                  Chip(
                    label: Text(name),
                    onDeleted: () => _deleteName(name),
                  ),
              ],
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _addName,
              icon: const Icon(Icons.add),
              label: const Text('Add name'),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ layout

  Widget _section({
    required String title,
    String? subtitle,
    required Widget child,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle, style: TextStyle(color: Colors.grey.shade700)),
            ],
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Accounts & balance')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                if (_error != null)
                  Card(
                    color: Colors.red.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        'Error: $_error',
                        style: TextStyle(color: Colors.red.shade900),
                      ),
                    ),
                  ),
                _buildBalanceCard(),
                _buildAccountsCard(),
                _buildAppsCard(),
                _buildNamesCard(),
              ],
            ),
    );
  }
}