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

    // Income (rarely a "merchant" but VPAs sometimes carry these words)
    'salary': 'Income',
    'refund': 'Income',
  };

  static const String defaultCategory = 'Other';

  /// Returns a best-guess category for a merchant name or VPA string.
  /// Falls back to [defaultCategory] if nothing matches.
  static String categorize(String merchantOrVpa) {
    final String normalized = merchantOrVpa.toLowerCase();

    for (final entry in _keywordToCategory.entries) {
      if (normalized.contains(entry.key)) {
        return entry.value;
      }
    }

    return defaultCategory;
  }
}