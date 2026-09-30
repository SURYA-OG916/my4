import 'package:flutter/material.dart';
import 'transfer_helper.dart';

// Day 35: single source of truth for category colors, so chips, Category
// Summary bars, and transaction list tiles all agree on the same palette
// instead of each screen picking its own. Muted, elegant tones rather than
// stock Material primaries.
const Map<String, Color> _categoryColors = {
  'Food': Color(0xFFD97757),
  'Transport': Color(0xFF6B8CAE),
  'Petrol': Color(0xFFC9A227),
  'Fuel': Color(0xFFC9A227),
  'Groceries': Color(0xFF7A9B76),
  'Health': Color(0xFFC97B84),
  'Entertainment': Color(0xFF9B7EBD),
  'Shopping': Color(0xFF5C9AA0),
  'Subscription': Color(0xFF6C6FA8),
  'EMI': Color(0xFFB5654A),
  'Bank Charges': Color(0xFF6E6E6E),
  'ATM Withdrawal': Color(0xFF6E6E6E),
  'Bank Transfer': Color(0xFF9E9E9E),
  'Personal': Color(0xFF7E97B5),
  'Income': Color(0xFF5A8F6E),
  'Other': Color(0xFFA69C94),
};

const Color _defaultCategoryColor = Color(0xFFA69C94); // same as Other

/// Full-strength color for a category — used for selected chip fills,
/// progress bars, and tile accent icons.
Color categoryColor(String category) {
  if (category == transferCategory) return const Color(0xFF9E9E9E);
  return _categoryColors[category] ?? _defaultCategoryColor;
}

/// Soft tint of the category color (for unselected chip backgrounds and
/// tile leading-icon backgrounds), computed at low opacity over white.
Color categorySoftColor(String category) {
  return categoryColor(category).withOpacity(0.14);
}

/// A readable label color for text sitting on top of [categorySoftColor],
/// darker than the base color for contrast on a light tint.
Color categoryLabelColor(String category) {
  final base = categoryColor(category);
  final hsl = HSLColor.fromColor(base);
  final darker = hsl.withLightness((hsl.lightness * 0.72).clamp(0.0, 1.0));
  return darker.toColor();
}