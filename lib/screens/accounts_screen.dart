import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../models/bank_account.dart';
import '../models/transaction.dart';
import '../utils/account_balance.dart';
import '../utils/balance_helper.dart';
import '../utils/notification_ingestor.dart';
import '../utils/notification_parser.dart';
import '../utils/slice_balance.dart';
import '../utils/sms_filter.dart';
import '../utils/transfer_helper.dart';
import '../widgets/bank_balance_tile.dart';

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
  SliceBalanceSnapshot? _sliceBalance;
  Map<String, AccountBalanceSnapshot> _accountBalances = {};
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
      final transactions = await db.getAllTransactions();

      // Day 28: Slice appears as its own bank account. Create it the first
      // time a Slice payment has been added.
      await _ensureSliceAccount(transactions);

      final accounts = await db.getAllAccounts();
      final names = await db.getMyNames();
      final links = await db.getAppLinks();
      // Bank-only snapshot: Slice is shown separately below.
      final snapshot = await BalanceHelper.loadSnapshot(includeSlice: false);
      final sliceBalance = await SliceBalance.load();

      final accountBalances = <String, AccountBalanceSnapshot>{};
      for (final account in accounts) {
        final balance = await AccountBalance.load(account.id);
        if (balance != null) accountBalances[account.id] = balance;
      }

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
        _sliceBalance = sliceBalance;
        _accountBalances = accountBalances;
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

  /// Creates the "Slice" bank account (last 4 digits taken from an existing
  /// Slice transaction, e.g. "Slice • 9809") and links the Slice app to it.
  /// Does nothing if it already exists or no Slice payment has been added yet.
  Future<void> _ensureSliceAccount(List<Transaction> transactions) async {
    final db = DatabaseHelper.instance;
    final existing = await db.getAllAccounts();
    if (existing.any((a) => isSliceSource(a.bank))) return;

    String? last4;
    for (final t in transactions) {
      if (!isSliceSource(t.source)) continue;
      final match = RegExp(r'(\d{4})\s*$').firstMatch(t.source);
      if (match != null) {
        last4 = match.group(1);
        break;
      }
    }
    if (last4 == null) return;

    final account = BankAccount(
      id: 'acc_slice_$last4',
      bank: 'Slice',
      last4: last4,
    );
    await db.insertAccount(account);
    await db.setAppLink(
      appKey: slicePackage,
      accountId: account.id,
      linked: true,
    );
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
              'now (check your bank app). Do not include Slice: it is tracked '
              'separately.',
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
    final slice = _sliceBalance;

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
          if (slice != null) ...[
            const SizedBox(height: 4),
            Text(
              'The balance on the main screen is this plus your Slice balance '
              '(₹${slice.amount.toStringAsFixed(2)}): '
              '₹${(current + slice.amount).toStringAsFixed(2)} in total.',
              style: TextStyle(color: Colors.grey.shade700),
            ),
          ],
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
    await AccountBalance.clear(account.id);
    await _load();
  }

  // Balance for one bank account (typed in by the user).
  Future<void> _editAccountBalance(BankAccount account) async {
    final existing = _accountBalances[account.id];
    final controller = TextEditingController(
      text: existing == null ? '' : existing.amount.toStringAsFixed(2),
    );
    final value = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Balance for ${account.label}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter what this account shows in your bank app right now. '
              "MY4 can't read it, so update it now and then.",
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
    await AccountBalance.save(account.id, value, DateTime.now());
    await _load();
  }

  Future<void> _clearAccountBalance(BankAccount account) async {
    await AccountBalance.clear(account.id);
    await _load();
  }

  Future<void> _showAccountSheet(BankAccount account) async {
    final isSlice = isSliceSource(account.bank);
    final hasBalance = _accountBalances.containsKey(account.id);

    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            if (isSlice)
              const ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Balance updates automatically'),
                subtitle: Text(
                  'It comes from the "Avl. Bal." in the Slice notifications '
                  'you approve in the Notification Reader, and drops when you '
                  'approve a payment you sent.',
                ),
              )
            else ...[
              ListTile(
                leading: const Icon(Icons.edit),
                title: Text(hasBalance ? 'Update balance' : 'Set balance'),
                onTap: () {
                  Navigator.pop(ctx);
                  _editAccountBalance(account);
                },
              ),
              if (hasBalance)
                ListTile(
                  leading: const Icon(Icons.backspace_outlined),
                  title: const Text('Clear balance'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _clearAccountBalance(account);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text(
                  'Remove account',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteAccount(account);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAccountTile(BankAccount account) {
    final isSlice = isSliceSource(account.bank);
    double? balance;
    var label = 'Account ending ${account.last4}';

    if (isSlice) {
      final slice = _sliceBalance;
      balance = slice?.amount;
      label += slice == null
          ? ' • updates from Slice notifications'
          : ' • as of ${_formatDateTime(slice.asOf)}';
    } else {
      final snap = _accountBalances[account.id];
      balance = snap?.amount;
      if (snap != null) {
        label += ' • set ${_formatDate(snap.asOf)}';
      }
    }

    return BankBalanceTile(
      bankName: account.bank,
      accountLabel: label,
      balance: balance,
      onTap: () => _showAccountSheet(account),
    );
  }

  Widget _buildAccountsCard() {
    return _section(
      title: 'Bank accounts',
      subtitle:
          'Each bank shows its own balance, hidden until you unlock it with '
          'the eye icon. Tap a bank to set its balance. Slice updates '
          'automatically.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_accounts.isEmpty)
            Text(
              'No accounts added yet.',
              style: TextStyle(color: Colors.grey.shade700),
            ),
          for (final account in _accounts) _buildAccountTile(account),
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

  /// Day 27: apps grouped by display name. Samsung Wallet and WhatsApp Pay
  /// each have two package names but should appear as a single row.
  Map<String, List<String>> get _appGroups {
    final groups = <String, List<String>>{};
    for (final entry in upiAppLabels.entries) {
      if (entry.key == 'com.android.shell') continue;
      groups.putIfAbsent(entry.value, () => <String>[]).add(entry.key);
    }
    return groups;
  }

  /// Links or unlinks an account for every package name in the group.
  Future<void> _toggleLink(
    List<String> appKeys,
    String accountId,
    bool linked,
  ) async {
    for (final key in appKeys) {
      await DatabaseHelper.instance.setAppLink(
        appKey: key,
        accountId: accountId,
        linked: linked,
      );
    }
    await _load();
  }

  Widget _buildAppRow(String label, List<String> keys) {
    DateTime? lastSeen;
    for (final key in keys) {
      final seen = _lastSeen[key];
      if (seen != null && (lastSeen == null || seen.isAfter(lastSeen))) {
        lastSeen = seen;
      }
    }

    // Day 28: the Slice bank account belongs to the Slice app only, so it is
    // not offered under Google Pay, PhonePe, Paytm and the rest. The Slice app
    // itself lists every account, because Slice can link other banks too.
    final isSliceApp = keys.contains(slicePackage);
    final linkable = isSliceApp
        ? _accounts
        : _accounts.where((a) => !isSliceSource(a.bank)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.phone_android),
          title: Text(label),
          subtitle: Text(
            lastSeen != null
                ? 'Last payment notification: ${_formatDateTime(lastSeen)}'
                : 'No payment notifications captured yet',
          ),
        ),
        if (linkable.isEmpty)
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
                for (final account in linkable)
                  FilterChip(
                    label: Text(account.label),
                    selected: keys.any(
                      (key) => _links[key]?.contains(account.id) ?? false,
                    ),
                    onSelected: (selected) =>
                        _toggleLink(keys, account.id, selected),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildAppsCard() {
    return _section(
      title: 'UPI apps',
      subtitle:
          'Payment apps MY4 listens to, and which of your accounts each one '
          'uses. The Slice account is only used by the Slice app.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final group in _appGroups.entries)
            _buildAppRow(group.key, group.value),
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

  // ----------------------------------------------------------- cleanup (D29)

  /// Day 29: leftover promo/OTP/due-reminder SMS that got imported as
  /// transactions before Day 28's sms_filter.dart fix, plus transactions
  /// wrongly tagged as Slice-related before the same fix. Titles are the
  /// closest thing to the original SMS text still stored, so promo text is
  /// checked there via the same SmsFilter.looksLikePromo pattern the live
  /// SMS reader uses. Slice mismatches reuse isSliceSource, exactly as the
  /// rest of this screen does for account/app matching.
  List<Transaction> get _cleanupCandidates {
    return _transactions.where((t) {
      final looksPromo =
          SmsFilter.looksLikePromo(t.title) || SmsFilter.looksLikePromo(t.source);
      final looksSliceButMistagged =
          isSliceSource(t.source) && t.category != transferCategory && looksPromo;
      return looksPromo || looksSliceButMistagged;
    }).toList();
  }

  Future<void> _cleanupOldImports() async {
    final matches = _cleanupCandidates;
    if (matches.isEmpty) {
      _snack('No leftover promo or Slice-mistagged transactions found.');
      return;
    }

    final preview = matches.take(6).toList();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Delete ${matches.length} old import'
          '${matches.length == 1 ? '' : 's'}?',
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'These look like promo/OTP/reminder SMS that were imported '
                'before the Day 28 filter fix, not real transactions.',
              ),
              const SizedBox(height: 8),
              for (final t in preview)
                Text(
                  '${t.title} • ${t.type == TransactionType.credit ? '+' : '-'}'
                  '₹${t.amount.toStringAsFixed(2)} • ${_formatDate(t.date)}',
                ),
              if (matches.length > preview.length)
                Text('…and ${matches.length - preview.length} more'),
              const SizedBox(height: 8),
              const Text('This cannot be undone.'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final ids = matches.map((t) => t.id).toList();
    final deleted = await DatabaseHelper.instance.deleteTransactionsByIds(ids);
    _snack(
      'Deleted $deleted old import${deleted == 1 ? '' : 's'}',
    );
    await _load();
  }

  Widget _buildCleanupCard() {
    final count = _cleanupCandidates.length;
    return _section(
      title: 'Clean up old imports',
      subtitle: count == 0
          ? 'No leftover promo or Slice-mistagged transactions detected.'
          : '$count transaction${count == 1 ? '' : 's'} look like promo/OTP/'
              'reminder SMS or Slice entries imported before the Day 28 '
              'filter fix. Review and delete them below.',
      child: Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.tonalIcon(
          onPressed: count == 0 ? null : _cleanupOldImports,
          icon: const Icon(Icons.cleaning_services_outlined),
          label: Text(count == 0 ? 'Nothing to clean up' : 'Review & clean up'),
        ),
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
                _buildCleanupCard(),
              ],
            ),
    );
  }
}