import 'package:flutter/material.dart';

import '../utils/notification_ingestor.dart';

// Captured UPI notifications are turned into real transactions automatically,
// except Slice payments, which always wait here for your OK. Possible
// duplicates also wait here for a decision. Notifications that are not
// payments (promotions, chats, rewards, failed payments) are hidden unless
// you switch them on.

// Day 38: same navy palette as the rest of the app.
const Color _navy = Color(0xFF1F2A44);
const Color _good = Color(0xFF5A8F6E);
const Color _amber = Color(0xFFC9A227);
const Color _amberDark = Color(0xFF8A6D0B);
const Color _bad = Color(0xFFB5654A);
const Color _muted = Color(0xFF6B6B6B);

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

  // Day 29: "Clear captured" wipes the native notification queue and cannot
  // be undone from Dart (the notifications are gone from the native side,
  // not just hidden), so this confirms first instead of offering a fake undo.
  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear captured notifications?'),
        content: const Text(
          'This removes them from the queue entirely and cannot be undone. '
          'Transactions already added are not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

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

  // Day 29: dismissing now offers an Undo action in the snackbar. Undo calls
  // NotificationIngestor.undismissReviewItem, which reverses the exact two
  // writes _dismiss made, then refreshes so the item reappears.
  Future<void> _dismiss(NotificationEntry entry) async {
    try {
      await NotificationIngestor.dismissReviewItem(entry);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
      return;
    }
    await _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Dismissed'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => _undismiss(entry),
        ),
      ),
    );
  }

  Future<void> _undismiss(NotificationEntry entry) async {
    try {
      await NotificationIngestor.undismissReviewItem(entry);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
      return;
    }
    await _refresh();
  }

  // ------------------------------------------------------------------ layout

  RoundedRectangleBorder _cardShape() {
    final scheme = Theme.of(context).colorScheme;
    return RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: BorderSide(color: scheme.outlineVariant.withOpacity(0.6)),
    );
  }

  Widget _iconBadge(IconData icon, Color color, {double size = 42}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: size * 0.5),
    );
  }

  Widget _buildStatusCard() {
    final color = _enabled ? _good : _amber;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: _cardShape(),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            _iconBadge(
              _enabled ? Icons.check_circle : Icons.error_outline,
              color,
              size: 46,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _enabled
                        ? 'Notification access is on'
                        : 'Notification access is off',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _enabled
                        ? 'Listening to Google Pay, PhonePe, Paytm, BHIM, '
                            'Samsung Wallet, WhatsApp Pay and Slice payments only.'
                        : "MY4 can't see UPI app notifications until you grant access.",
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 12.5,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _openSettings,
              child: Text(_enabled ? 'Manage' : 'Enable'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
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
              'Error: $_error',
              style: const TextStyle(color: _bad),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewTile(NotificationEntry entry) {
    final n = entry.notification;
    final approval = entry.awaitingApproval;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _amber.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _amber.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            n.title.isEmpty ? '(no title)' : n.title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          if (n.text.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(n.text),
          ],
          const SizedBox(height: 4),
          Text(
            '${n.appLabel} • ${_formatDateTime(n.postTime)}',
            style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Text(
            approval
                ? 'Add this ${n.appLabel} payment? ${entry.parsed.summary}'
                : '⚠ Possible duplicate: ${entry.parsed.summary}',
            style: const TextStyle(
              color: _amberDark,
              fontWeight: FontWeight.w600,
            ),
          ),
          for (final note in entry.duplicateNotes)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                note,
                style: TextStyle(color: Colors.grey.shade800, fontSize: 12.5),
              ),
            ),
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
                child: Text(approval ? 'Add' : 'Add anyway'),
              ),
            ],
          ),
        ],
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
        statusColor = _good;
        break;
      case NotificationStatus.alreadyHandled:
        statusText = '✓ Handled: ${entry.parsed.summary}';
        statusColor = _muted;
        break;
      case NotificationStatus.dismissed:
        statusText = '✗ Dismissed by you: ${entry.parsed.summary}';
        statusColor = _muted;
        break;
      case NotificationStatus.ignored:
        statusText = '✗ ${entry.parsed.summary}';
        statusColor = _amberDark;
        break;
      case NotificationStatus.needsReview:
        statusText = '⚠ ${entry.parsed.summary}';
        statusColor = _amberDark;
        break;
    }

    // Day 29: a "Dismissed by you" item can also be undone directly from the
    // list (not just via the snackbar right after dismissing), by tapping
    // the small undo icon.
    final canUndo = entry.status == NotificationStatus.dismissed;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: _cardShape(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 6, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _iconBadge(Icons.notifications_outlined, statusColor, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    n.title.isEmpty ? '(no title)' : n.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    n.text.isEmpty ? '(no text)' : n.text,
                    style: TextStyle(
                      color: Colors.grey.shade800,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${n.appLabel} • ${_formatDateTime(n.postTime)}',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    statusText,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            if (canUndo)
              IconButton(
                icon: const Icon(Icons.undo),
                tooltip: 'Undo dismiss',
                onPressed: () => _undismiss(entry),
              ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 18, 6, 10),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: Colors.grey.shade600,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
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
        centerTitle: false,
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
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
              children: [
                _buildStatusCard(),
                if (_error != null) _buildErrorCard(),
                if (needsReview.isNotEmpty) ...[
                  _sectionHeader('Needs review (${needsReview.length})'),
                  ...needsReview.map(_buildReviewTile),
                ],
                _sectionHeader('Payments (${handled.length})'),
                if (handled.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'No payment notifications yet. Once access is on, '
                      'payments from supported UPI apps will show up here '
                      'and be added to your transactions.',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  )
                else
                  ...handled.map(_buildTile),
                if (ignored.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Card(
                    elevation: 0,
                    shape: _cardShape(),
                    child: SwitchListTile(
                      activeColor: _navy,
                      title: Text('Show ignored (${ignored.length})'),
                      subtitle: const Text(
                        'Promotions, rewards, failed or pending payments, and '
                        'ones you dismissed. These are never added as '
                        'transactions.',
                      ),
                      value: _showIgnored,
                      onChanged: (value) {
                        setState(() => _showIgnored = value);
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_showIgnored) ...ignored.map(_buildTile),
                ],
              ],
            ),
    );
  }
}