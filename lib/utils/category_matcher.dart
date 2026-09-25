/// Maps merchant names / UPI VPAs to a best-guess category using
/// keyword matching. Shared by SMS parsing (and available for manual
/// entry auto-suggest later, if wired in).
class CategoryMatcher {
  // Keyword -> category. Checked against merchant text in lowercase.
  // Order matters only in that the first match wins, so keep more
  // specific keywords above generic ones if overlap ever becomes an issue.
  static const Map<String, String> _keywordToCategory = {
    // Food (Day 29: broadened beyond the big delivery apps to catch
    // generic eatery wording that shows up in UPI merchant strings)
    'swiggy': 'Food',
    'zomato': 'Food',
    'dominos': 'Food',
    "domino's": 'Food',
    'pizza': 'Food',
    'restaurant': 'Food',
    'cafe': 'Food',
    'bakery': 'Food',
    'sweets': 'Food',
    'hotel': 'Food',
    'mess': 'Food',
    'tiffin': 'Food',
    'biryani': 'Food',
    'kitchen': 'Food',
    'eatery': 'Food',
    'food': 'Food',

    // Groceries (Day 29: was falling into Food/Shopping/Other before)
    'grocery': 'Groceries',
    'groceries': 'Groceries',
    'supermarket': 'Groceries',
    'bigbasket': 'Groceries',
    'blinkit': 'Groceries',
    'zepto': 'Groceries',
    'dmart': 'Groceries',
    'more supermarket': 'Groceries',
    'reliance fresh': 'Groceries',
    'reliance smart': 'Groceries',
    'kirana': 'Groceries',

    // Shopping
    'amazon': 'Shopping',
    'flipkart': 'Shopping',
    'myntra': 'Shopping',
    'ajio': 'Shopping',
    'meesho': 'Shopping',
    'nykaa': 'Shopping',

    // Subscription
    'netflix': 'Subscription',
    'spotify': 'Subscription',
    'hotstar': 'Subscription',
    'prime': 'Subscription',
    'youtube': 'Subscription',
    'jio': 'Subscription',
    'airtel': 'Subscription',

    // Petrol / Fuel (Day 29: split out of Transport — pump/vehicle refuelling
    // is a distinct spending habit worth tracking on its own, separate from
    // bus/train/cab fares)
    'petrol': 'Petrol',
    'petroleum': 'Petrol',
    'fuel': 'Petrol',
    'diesel': 'Petrol',
    'indian oil': 'Petrol',
    'iocl': 'Petrol',
    'bharat petroleum': 'Petrol',
    'bpcl': 'Petrol',
    'hp petrol': 'Petrol',
    'hpcl': 'Petrol',
    'filling station': 'Petrol',
    'fuel station': 'Petrol',
    'petrol bunk': 'Petrol',

    // Transport (fares/travel, not fuel)
    'state transport': 'Transport',
    'tnstc': 'Transport',
    'transport': 'Transport',
    'irctc': 'Transport',
    'railway': 'Transport',
    'redbus': 'Transport',
    'uber': 'Transport',
    'rapido': 'Transport',
    'ola': 'Transport',
    'olacabs': 'Transport',
    'metro rail': 'Transport',
    'toll': 'Transport',
    'fastag': 'Transport',
    'parking': 'Transport',

    // Health (Day 29: new)
    'pharmacy': 'Health',
    'medical': 'Health',
    'medicals': 'Health',
    'hospital': 'Health',
    'clinic': 'Health',
    'diagnostic': 'Health',
    'apollo': 'Health',
    'pharmeasy': 'Health',
    '1mg': 'Health',
    'netmeds': 'Health',

    // Entertainment (Day 29: new)
    'bookmyshow': 'Entertainment',
    'cinema': 'Entertainment',
    'cinemas': 'Entertainment',
    'movies': 'Entertainment',
    'pvr': 'Entertainment',
    'inox': 'Entertainment',

    // Income (rarely a "merchant" but VPAs sometimes carry these words)
    'salary': 'Income',
    'refund': 'Income',

    // Bank-adjacent transaction types (surfaced now that bank context
    // is passed in — these show up as the "merchant" text itself on
    // EMI/ATM/fee-type SMS, not as a real payee)
    'emi': 'EMI',
    'loan': 'EMI',
    // Day 33: finance companies (loan / EMI repayments)
    'bajaj finance': 'EMI',
    'bajaj finserv': 'EMI',
    'finserv': 'EMI',
    'finance': 'EMI',
    'atm': 'ATM Withdrawal',
    'cash withdrawal': 'ATM Withdrawal',
    'interest': 'Bank Charges',
    'annual fee': 'Bank Charges',
    'late fee': 'Bank Charges',
    'penalty': 'Bank Charges',
    'gst': 'Bank Charges',
    // Day 33: fee descriptions seen in SBI SMS ("-CDM CHARGE DR"). Kept as
    // specific phrases: a bare "charge" would also match "Recharge".
    'cdm charge': 'Bank Charges',
    'service charge': 'Bank Charges',
    'sms charge': 'Bank Charges',
  };

  // Day 33: short keywords that also appear inside ordinary personal names
  // ("ola" in "Solaiyappan", "mess" in "Messi", "atm" in some names). These
  // only count when they stand alone as a whole word, so "Ola", "OLA CABS"
  // and "ola@paytm" match, but "Solaiyappan" does not. Every other keyword
  // is still matched anywhere in the text.
  static const Set<String> _wholeWordKeywords = {
    'ola',
    'atm',
    'emi',
    'mess',
    'jio',
    'gst',
    'toll',
    'pvr',
    'inox',
    'prime',
    'uber',
  };

  static const String defaultCategory = 'Other';
  static const String bankTransferCategory = 'Bank Transfer';

  /// Day 33: money received from a person through a payment app (WhatsApp
  /// Pay, PhonePe, Paytm, Google Pay, BHIM) when no keyword matched. It is
  /// assigned in notification_ingestor.dart, not by [categorize], because
  /// only the ingestor knows the payment app and the direction.
  static const String personalCategory = 'Personal';

  /// True when [keyword] appears in [normalized] as a standalone word: the
  /// characters on either side (if any) are not letters or digits.
  static bool _containsWholeWord(String normalized, String keyword) {
    final pattern = RegExp(
      '(^|[^a-z0-9])${RegExp.escape(keyword)}(\$|[^a-z0-9])',
    );
    return pattern.hasMatch(normalized);
  }

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
      final matched = _wholeWordKeywords.contains(entry.key)
          ? _containsWholeWord(normalized, entry.key)
          : normalized.contains(entry.key);
      if (matched) {
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

  /// All categories CategoryMatcher can assign, plus the manual/bank
  /// special-case ones (defaultCategory, bankTransferCategory), Transfer
  /// (assigned outside CategoryMatcher, via own-name matching in
  /// transfer_helper.dart) and Personal (assigned in
  /// notification_ingestor.dart). Used by category_helper.dart to seed the
  /// dropdown so a category shows up before any transaction has it yet.
  static Set<String> get allCategories => {
        ..._keywordToCategory.values,
        defaultCategory,
        bankTransferCategory,
        'Transfer',
        personalCategory,
      };
}