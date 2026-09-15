import '../models/transaction.dart';
import '../utils/sms_parser.dart';
import '../db/database_helper.dart' show dedupWindowDays;

/// In-memory, app-lifetime store mirroring SmsReaderScreen's current
/// needs-review list. Needs-review items are transient by nature (rebuilt
/// from SMS + processed_sms on every SMS Reader load), so they're not
/// persisted to the database — but that also meant nothing outside
/// SmsReaderScreen could see them, so the main "+" add flow had no way to
/// check a manually-entered transaction against a pending needs-review SMS.
/// This store closes that gap: SmsReaderScreen keeps it in sync with its
/// local _needsReview list, and main.dart reads it when checking for
/// duplicates on manual add.
class NeedsReviewStore {
  NeedsReviewStore._privateConstructor();
  static final NeedsReviewStore instance =
      NeedsReviewStore._privateConstructor();

  List<SmsParseResult> _items = [];

  List<SmsParseResult> get items => List.unmodifiable(_items);

  /// Replaces the whole list. Call this whenever SmsReaderScreen's
  /// _needsReview list changes (initial parse, or an item resolved/cleared).
  void setAll(List<SmsParseResult> items) {
    _items = List.from(items);
  }

  /// True if [a] and [b] fall within [dedupWindowDays] calendar days of
  /// each other. Mirrors DatabaseHelper's window check exactly, using the
  /// same shared constant, so a needs-review match and a real-transaction
  /// match never disagree about how close is "close enough."
  bool _isWithinDedupWindow(DateTime a, DateTime b) {
    final aDay = DateTime(a.year, a.month, a.day);
    final bDay = DateTime(b.year, b.month, b.day);
    final diff = aDay.difference(bDay).inDays.abs();
    return diff <= dedupWindowDays;
  }

  /// Needs-review entries whose recovered partial data matches [amount],
  /// [type], and fall within [dedupWindowDays] calendar days of [date].
  /// Mirrors the same amount+type+date-window signal
  /// DatabaseHelper.findPotentialDuplicates() uses against real
  /// transactions — deliberately not matching on merchant text, for the
  /// same false-positive reasons. Entries where the parser couldn't
  /// recover an amount/type/date never match — there's nothing concrete
  /// to compare against.
  List<SmsParseResult> findMatching({
    required double amount,
    required TransactionType type,
    required DateTime date,
  }) {
    return _items.where((r) {
      if (r.partialAmount == null ||
          r.partialType == null ||
          r.smsDate == null) {
        return false;
      }
      return r.partialAmount == amount &&
          r.partialType == type &&
          _isWithinDedupWindow(r.smsDate!, date);
    }).toList();
  }
}