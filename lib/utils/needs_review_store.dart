import '../models/transaction.dart';
import '../utils/sms_parser.dart';

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

  /// Needs-review entries whose recovered partial data matches [amount],
  /// [type], and the same calendar day as [date]. Mirrors the same
  /// amount+type+day signal DatabaseHelper.findPotentialDuplicates() uses
  /// against real transactions — deliberately not matching on merchant
  /// text, for the same false-positive reasons. Entries where the parser
  /// couldn't recover an amount/type/date never match — there's nothing
  /// concrete to compare against.
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
          r.smsDate!.year == date.year &&
          r.smsDate!.month == date.month &&
          r.smsDate!.day == date.day;
    }).toList();
  }
}