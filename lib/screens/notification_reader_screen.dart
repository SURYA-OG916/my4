import 'package:flutter/material.dart';

import '../utils/notification_ingestor.dart';

// Captured UPI notifications are turned into real transactions automatically.
// Possible duplicates wait here for a decision. Notifications that are not
// payments (promotions, chats, rewards, failed payments) are hidden unless
// you switch them on.

String _formatDateTime(int millis) {
  final d = DateTime.fromMillisecondsSinceEpoch(millis);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
}

class NotificationReaderScreen extends StatefulWidget {
  const NotificationReaderScreen({super.key});

  @override
  State<NotificationReaderScreen> createState() =>
      _NotificationReaderScreenState();
}

class _NotificationReaderScreenState extends State<NotificationReaderScreen>
    with WidgetsBindingObserver {
  bool _loading = true;
  bool _showIgnored = false;
  String? _error;
  NotificationIngestResult? _result;

  bool get _enabled => _result?.listenerEnabled ?? false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Coming back from the system "Notification access" screen should update the status.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    try {
      final result = await NotificationIngestor.run();
      if (!mounted) return;
      setState(() {
        _result = result;
        _error = null;
        _loading = false;
      });
      if (result.addedCount > 0) {
        final count = result.addedCount;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Added $count transaction${count == 1 ? '' : 's'} from notifications',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _openSettings() async {
    try {
      await NotificationIngestor.openListenerSettings();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _clear() async {
    try {
      await NotificationIngestor.clearCaptured();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
      return;
    }
    await _refresh();
  }

  Future<void> _addAnyway(NotificationEntry entry) async {
    try {
      await NotificationIngestor.addReviewItem(entry);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
      return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Transaction added')),
      );
    }
    await _refresh();
  }

  Future<void> _dismiss(NotificationEntry entry) async {
    try {
      await NotificationIngestor.dismissReviewItem(entry);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
      return;
    }
    await _refresh();
  }

  Widget _buildStatusCard() {
    return Card(
      child: ListTile(
        leading: Icon(
          _enabled ? Icons.check_circle : Icons.error_outline,
          color: _enabled ? Colors.green.shade700 : Colors.orange.shade800,
          size: 32,
        ),
        title: Text(
          _enabled ? 'Notification access is on' : 'Notification access is off',
        ),
        subtitle: Text(
          _enabled
              ? 'Listening to Google Pay, PhonePe, Paytm, BHIM and CRED only.'
              : "MY4 can't see UPI app notifications until you grant access.",
        ),
        trailing: FilledButton(
          onPressed: _openSettings,
          child: Text(_enabled ? 'Manage' : 'Enable'),
        ),
      ),
    );
  }

  Widget _buildErrorCard() {
    return Card(
      color: Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          'Error: $_error',
          style: TextStyle(color: Colors.red.shade900),
        ),
      ),
    );
  }

  Widget _buildReviewTile(NotificationEntry entry) {
    final n = entry.notification;
    return Card(
      color: Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              n.title.isEmpty ? '(no title)' : n.title,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (n.text.isNotEmpty) Text(n.text),
            Text(
              '${n.appLabel} • ${_formatDateTime(n.postTime)}',
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 6),
            Text(
              '⚠ Possible duplicate: ${entry.parsed.summary}',
              style: TextStyle(
                color: Colors.orange.shade900,
                fontWeight: FontWeight.w600,
              ),
            ),
            for (final note in entry.duplicateNotes)
              Text(note, style: TextStyle(color: Colors.grey.shade800)),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => _dismiss(entry),
                  child: const Text('Dismiss'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => _addAnyway(entry),
                  child: const Text('Add anyway'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTile(NotificationEntry entry) {
    final n = entry.notification;

    String statusText;
    Color statusColor;
    switch (entry.status) {
      case NotificationStatus.added:
        statusText = '✓ Added: ${entry.parsed.summary}';
        statusColor = Colors.green.shade800;
        break;
      case NotificationStatus.alreadyHandled:
        statusText = '✓ Handled: ${entry.parsed.summary}';
        statusColor = Colors.grey.shade700;
        break;
      case NotificationStatus.ignored:
        statusText = '✗ ${entry.parsed.summary}';
        statusColor = Colors.orange.shade900;
        break;
      case NotificationStatus.needsReview:
        statusText = '⚠ ${entry.parsed.summary}';
        statusColor = Colors.orange.shade900;
        break;
    }

    return Card(
      child: ListTile(
        isThreeLine: true,
        leading: const CircleAvatar(
          child: Icon(Icons.notifications_outlined),
        ),
        title: Text(n.title.isEmpty ? '(no title)' : n.title),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(n.text.isEmpty ? '(no text)' : n.text),
            Text('${n.appLabel} • ${_formatDateTime(n.postTime)}'),
            const SizedBox(height: 4),
            Text(
              statusText,
              style: TextStyle(
                color: statusColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final needsReview = result?.needsReview ?? const <NotificationEntry>[];
    final handled = result?.handled ?? const <NotificationEntry>[];
    final ignored = result?.ignored ?? const <NotificationEntry>[];
    final hasAnything =
        needsReview.isNotEmpty || handled.isNotEmpty || ignored.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification Reader'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _refresh,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Clear captured',
            onPressed: hasAnything ? _clear : null,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _buildStatusCard(),
                if (_error != null) _buildErrorCard(),
                if (needsReview.isNotEmpty) ...[
                  _sectionHeader('Needs review (${needsReview.length})'),
                  ...needsReview.map(_buildReviewTile),
                ],
                _sectionHeader('Payments (${handled.length})'),
                if (handled.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'No payment notifications yet. Once access is on, '
                      'payments from supported UPI apps will show up here '
                      'and be added to your transactions.',
                    ),
                  )
                else
                  ...handled.map(_buildTile),
                if (ignored.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Card(
                    child: SwitchListTile(
                      title: Text('Show ignored (${ignored.length})'),
                      subtitle: const Text(
                        'Promotions, rewards and failed or pending payments. '
                        'These are never added as transactions.',
                      ),
                      value: _showIgnored,
                      onChanged: (value) {
                        setState(() => _showIgnored = value);
                      },
                    ),
                  ),
                  if (_showIgnored) ...ignored.map(_buildTile),
                ],
              ],
            ),
    );
  }
}