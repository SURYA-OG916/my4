/// Maps merchant names / UPI VPAs to a best-guess category using
/// keyword matching. Shared by SMS parsing (and available for manual
/// entry auto-suggest later, if wired in).
class CategoryMatcher {
  // Keyword -> category. Checked against merchant text in lowercase.
  // Order matters only in that the first match wins, so keep more
  // specific keywords above generic ones if overlap ever becomes an issue.
  static const Map<String, String> _keywordToCategory = {
    // Food
    'swiggy': 'Food',
    'zomato': 'Food',
    'dominos': 'Food',
    'pizza': 'Food',
    'restaurant': 'Food',
    'cafe': 'Food',
    'food': 'Food',

    // Shopping
    'amazon': 'Shopping',
    'flipkart': 'Shopping',
    'myntra': 'Shopping',
    'ajio': 'Shopping',
    'meesho': 'Shopping',

    // Subscription
    'netflix': 'Subscription',
    'spotify': 'Subscription',
    'hotstar': 'Subscription',
    'prime': 'Subscription',
    'youtube': 'Subscription',
    'jio': 'Subscription',
    'airtel': 'Subscription',

    // Transport (Day 27). Kept to whole-name keywords on purpose: short
    // ones like "bus" or "ola" would also match unrelated words.
    'state transport': 'Transport',
    'tnstc': 'Transport',
    'transport': 'Transport',
    'irctc': 'Transport',
    'railway': 'Transport',
    'redbus': 'Transport',
    'uber': 'Transport',
    'rapido': 'Transport',
    'petrol': 'Transport',
    'petroleum': 'Transport',
    'fuel': 'Transport',

    // Income (rarely a "merchant" but VPAs sometimes carry these words)
    'salary': 'Income',
    'refund': 'Income',

    // Bank-adjacent transaction types (surfaced now that bank context
    // is passed in — these show up as the "merchant" text itself on
    // EMI/ATM/fee-type SMS, not as a real payee)
    'emi': 'EMI',
    'loan': 'EMI',
    'atm': 'ATM Withdrawal',
    'cash withdrawal': 'ATM Withdrawal',
    'interest': 'Bank Charges',
    'annual fee': 'Bank Charges',
    'late fee': 'Bank Charges',
    'penalty': 'Bank Charges',
    'gst': 'Bank Charges',
  };

  static const String defaultCategory = 'Other';
  static const String bankTransferCategory = 'Bank Transfer';

  /// Returns a best-guess category for a merchant name or VPA string.
  ///
  /// [bankName], if provided, is used to detect the case where no real
  /// merchant could be extracted from an SMS and [merchantOrVpa] is just
  /// the bank name itself (sms_parser.dart's fallback). That case is
  /// tagged [bankTransferCategory] instead of falling through to
  /// [defaultCategory], since it's almost always a bank transfer, ATM
  /// withdrawal, or fee rather than a genuinely uncategorizable spend.
  static String categorize(String merchantOrVpa, {String? bankName}) {
    final String normalized = merchantOrVpa.toLowerCase();

    for (final entry in _keywordToCategory.entries) {
      if (normalized.contains(entry.key)) {
        return entry.value;
      }
    }

    if (bankName != null &&
        bankName.isNotEmpty &&
        normalized == bankName.toLowerCase()) {
      return bankTransferCategory;
    }

    return defaultCategory;
  }
}