import 'dart:convert';

import 'package:flutter/services.dart';

import '../db/database_helper.dart';
import '../models/transaction.dart';
import 'category_matcher.dart';
import 'needs_review_store.dart';
import 'notification_parser.dart';
import 'transfer_helper.dart';

// Turns captured UPI-app notifications into real transactions.
//
// Rules (mirrors the SMS pipeline):
//  - successful parse + no possible duplicate  -> auto-inserted
//  - successful parse + possible duplicate     -> "needs review" (user decides)
//  - failed parse (no amount, failed/pending/promotional) -> ignored, and NOT
//    marked processed, so an improved parser can pick it up on a later run
//  - payments to/from one of the user's own names -> category "Transfer"
//  - handled notifications are remembered in the processed_sms table

class CapturedNotification {
  final String id;
  final String packageName;
  final String title;
  final String text;
  final int postTime;

  const CapturedNotification({
    required this.id,
    required this.packageName,
    required this.title,
    required this.text,
    required this.postTime,
  });

  factory CapturedNotification.fromJson(Map<String, dynamic> json) {
    return CapturedNotification(
      id: (json['id'] ?? '').toString(),
      packageName: (json['package'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      text: (json['text'] ?? '').toString(),
      postTime: (json['postTime'] as num? ?? 0).toInt(),
    );
  }

  String get appLabel => upiAppLabels[packageName] ?? packageName;

  DateTime get postedAt => DateTime.fromMillisecondsSinceEpoch(postTime);

  // Same fingerprint scheme as SMS, so it shares the processed_sms table.
  String get hash => DatabaseHelper.smsHash(
        sender: packageName,
        body: '$title|$text',
        dateMillis: postTime,
      );

  NotificationParseResult parse() {
    return NotificationParser.parse(
      packageName: packageName,
      title: title,
      text: text,
    );
  }
}

enum NotificationStatus { added, alreadyHandled, needsReview, ignored }

class NotificationEntry {
  final CapturedNotification notification;
  final NotificationParseResult parsed;
  final NotificationStatus status;

  /// The transaction that would be inserted (set for added / needsReview).
  final Transaction? draft;

  /// Human-readable descriptions of the possible duplicates (needsReview only).
  final List<String> duplicateNotes;

  const NotificationEntry({
    required this.notification,
    required this.parsed,
    required this.status,
    this.draft,
    this.duplicateNotes = const [],
  });
}

class NotificationIngestResult {
  final bool listenerEnabled;

  /// Newest first.
  final List<NotificationEntry> entries;
  final int addedCount;

  const NotificationIngestResult({
    required this.listenerEnabled,
    required this.entries,
    required this.addedCount,
  });

  List<NotificationEntry> get needsReview => entries
      .where((e) => e.status == NotificationStatus.needsReview)
      .toList();

  /// Payments that became (or already are) transactions.
  List<NotificationEntry> get handled => entries
      .where((e) =>
          e.status == NotificationStatus.added ||
          e.status == NotificationStatus.alreadyHandled)
      .toList();

  /// Promotions, chats, rewards, failed payments: captured but not payments.
  List<NotificationEntry> get ignored =>
      entries.where((e) => e.status == NotificationStatus.ignored).toList();
}

class NotificationIngestor {
  static const MethodChannel _channel = MethodChannel('my4/notifications');

  static Future<NotificationIngestResult>? _inFlight;

  /// Reads the native queue and ingests anything new. Safe to call from
  /// several places at once: concurrent callers share one run.
  static Future<NotificationIngestResult> run() {
    final existing = _inFlight;
    if (existing != null) return existing;

    final future = _run().whenComplete(() {
      _inFlight = null;
    });
    _inFlight = future;
    return future;
  }

  static Future<List<CapturedNotification>> _readQueue() async {
    final raw = await _channel.invokeMethod<String>('getPending') ?? '[]';
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((e) => CapturedNotification.fromJson(
            Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  static Future<NotificationIngestResult> _run() async {
    final enabled =
        await _channel.invokeMethod<bool>('isListenerEnabled') ?? false;

    // Oldest first, so earlier notifications are inserted before later ones
    // are checked for duplicates.
    final captured = await _readQueue();
    captured.sort((a, b) => a.postTime.compareTo(b.postTime));

    final ownNames = await DatabaseHelper.instance.getMyNames();

    final entries = <NotificationEntry>[];
    var addedCount = 0;

    for (final n in captured) {
      final parsed = n.parse();

      if (await DatabaseHelper.instance.isSmsProcessed(n.hash)) {
        entries.add(NotificationEntry(
          notification: n,
          parsed: parsed,
          status: NotificationStatus.alreadyHandled,
        ));
        continue;
      }

      if (!parsed.success) {
        entries.add(NotificationEntry(
          notification: n,
          parsed: parsed,
          status: NotificationStatus.ignored,
        ));
        continue;
      }

      final draft = _buildTransaction(n, parsed, ownNames);

      final duplicates = await DatabaseHelper.instance.findPotentialDuplicates(
        amount: draft.amount,
        type: draft.type,
        date: draft.date,
      );
      final pendingSms = NeedsReviewStore.instance.findMatching(
        amount: draft.amount,
        type: draft.type,
        date: draft.date,
      );

      if (duplicates.isEmpty && pendingSms.isEmpty) {
        await DatabaseHelper.instance.insertTransaction(draft);
        await DatabaseHelper.instance.markSmsProcessed(n.hash);
        addedCount++;
        entries.add(NotificationEntry(
          notification: n,
          parsed: parsed,
          status: NotificationStatus.added,
          draft: draft,
        ));
      } else {
        final notes = <String>[
          for (final t in duplicates)
            'Similar: ${t.title} • ₹${t.amount.toStringAsFixed(2)} • ${_formatDate(t.date)}',
          if (pendingSms.isNotEmpty)
            'A matching SMS is waiting in SMS Reader → Needs review',
        ];
        entries.add(NotificationEntry(
          notification: n,
          parsed: parsed,
          status: NotificationStatus.needsReview,
          draft: draft,
          duplicateNotes: notes,
        ));
      }
    }

    entries.sort((a, b) =>
        b.notification.postTime.compareTo(a.notification.postTime));

    return NotificationIngestResult(
      listenerEnabled: enabled,
      entries: entries,
      addedCount: addedCount,
    );
  }

  static Transaction _buildTransaction(
    CapturedNotification n,
    NotificationParseResult parsed,
    List<String> ownNames,
  ) {
    final merchant = parsed.merchant;
    final type = parsed.direction == NotificationDirection.credit
        ? TransactionType.credit
        : TransactionType.debit;

    // Money to/from one of the user's own names is a transfer between their
    // own accounts, not income or spending.
    final category = (merchant != null && matchesOwnName(merchant, ownNames))
        ? transferCategory
        : CategoryMatcher.categorize(merchant ?? '', bankName: parsed.bankName);

    return Transaction(
      id: 'notif_${n.postTime}_${n.hash.substring(0, 8)}',
      title: merchant ?? parsed.appLabel,
      source: parsed.sourceLabel,
      amount: parsed.amount!,
      date: n.postedAt,
      type: type,
      category: category,
    );
  }

  // --- Actions for needs-review entries ---

  static Future<void> addReviewItem(NotificationEntry entry) async {
    final draft = entry.draft;
    if (draft == null) return;
    await DatabaseHelper.instance.insertTransaction(draft);
    await DatabaseHelper.instance.markSmsProcessed(entry.notification.hash);
  }

  static Future<void> dismissReviewItem(NotificationEntry entry) async {
    await DatabaseHelper.instance.markSmsProcessed(entry.notification.hash);
  }

  // --- Info for the Accounts screen ---

  /// Package name -> time of the newest captured notification from that app.
  static Future<Map<String, DateTime>> lastSeenByApp() async {
    final captured = await _readQueue();
    final result = <String, DateTime>{};
    for (final n in captured) {
      // Rewards, promotions and chats don't count as payment notifications.
      if (!n.parse().success) continue;
      final existing = result[n.packageName];
      if (existing == null || n.postedAt.isAfter(existing)) {
        result[n.packageName] = n.postedAt;
      }
    }
    return result;
  }

  // --- Native bridge helpers ---

  static Future<void> clearCaptured() async {
    await _channel.invokeMethod<void>('clearPending');
  }

  static Future<void> openListenerSettings() async {
    await _channel.invokeMethod<void>('openListenerSettings');
  }

  static String _formatDate(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year}';
  }
}