import '../db/database_helper.dart';
import '../models/transaction.dart';
import 'category_matcher.dart';
import 'transfer_helper.dart';

// Day 33: one-time cleanup. Transactions keep the category they were given
// when they were created, so rows saved as "Other" before the newer keywords
// (Transport, EMI, ...) and the "Personal" category existed stay "Other".
// This re-runs the matcher over those rows once.
//
// Also (v3): rows saved as "Transfer" before the own-name list was correct
// are rechecked against the current own-name list. A row whose title no
// longer matches an own name is not really a transfer, so it is moved to a
// real category instead.
//
// v1: keyword matching + Personal for payment-app credits.
// v2: Personal now also covers credits from Slice and Samsung Wallet.
// v3: also fixes wrongly-tagged "Transfer" rows.

class Recategorizer {
  // Change the version suffix (v3 -> v4) to make the pass run one more time.
  static const String _doneKey = 'recategorize_other_v3';

  // Apps where a credit with a real sender name is a payment from a person.
  // Same payment apps as _paymentAppLabels in notification_ingestor.dart,
  // plus Slice and Samsung Wallet. Keep in sync with _personalCreditAppLabels
  // in notification_ingestor.dart.
  static const Set<String> _personalCreditAppLabels = {
    'Google Pay',
    'PhonePe',
    'Paytm',
    'BHIM',
    'CRED',
    'WhatsApp Pay',
    'Slice',
    'Samsung Wallet',
  };

  /// The app part of a stored source, e.g. "Paytm • SBI 3835" -> "Paytm".
  static String _appOfSource(String source) {
    return source.split(' • ').first.trim();
  }

  /// Runs the pass if it has not run before. Returns how many transactions
  /// were changed (0 if it already ran).
  static Future<int> runOnce() async {
    final db = DatabaseHelper.instance;
    if (await db.getSetting(_doneKey) != null) return 0;

    final ownNames = await db.getMyNames();
    final all = await db.getAllTransactions();
    var changed = 0;

    for (final t in all) {
      String? newCategory;

      if (t.category == transferCategory) {
        // Day 33 (v3): re-check against the current own-name list. Still a
        // real match -> stays Transfer, nothing to do.
        if (matchesOwnName(t.title, ownNames)) continue;

        // No longer matches: this was never really a transfer.
        if (t.type == TransactionType.credit &&
            _personalCreditAppLabels.contains(_appOfSource(t.source))) {
          newCategory = CategoryMatcher.personalCategory;
        } else if (t.type == TransactionType.debit) {
          // A named payment to someone who is not you is a personal payment.
          newCategory = CategoryMatcher.personalCategory;
        } else {
          newCategory = CategoryMatcher.categorize(t.title);
        }
      } else if (t.category == CategoryMatcher.defaultCategory) {
        var candidate = CategoryMatcher.categorize(t.title);

        // A credit from a named sender through one of these apps, with no
        // keyword match, is a personal payment. A title that is just the
        // app's own name means no sender name was found, so leave it alone.
        if (candidate == CategoryMatcher.defaultCategory &&
            t.type == TransactionType.credit) {
          final app = _appOfSource(t.source);
          final hasRealName =
              t.title.trim().toLowerCase() != app.toLowerCase();
          if (hasRealName && _personalCreditAppLabels.contains(app)) {
            candidate = CategoryMatcher.personalCategory;
          }
        }
        newCategory = candidate;
      } else {
        continue;
      }

      if (newCategory == null || newCategory == t.category) continue;

      await db.updateTransaction(Transaction(
        id: t.id,
        title: t.title,
        source: t.source,
        amount: t.amount,
        date: t.date,
        type: t.type,
        category: newCategory,
      ));
      changed++;
    }

    await db.setSetting(_doneKey, DateTime.now().toIso8601String());
    return changed;
  }
}