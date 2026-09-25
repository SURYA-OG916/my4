import '../models/transaction.dart';
import 'category_matcher.dart';

/// Single source of truth for deriving the category list (with a leading
/// 'All') from a set of transactions. Used by both the main transaction
/// list/add/edit flows and the SMS needs-review draft flow, so every
/// screen that offers a category dropdown agrees on what's available.
///
/// Day 30: previously this only returned categories actually present in
/// [transactions], so a newly-added CategoryMatcher category (e.g.
/// Petrol, Groceries, Health, Entertainment) wouldn't appear in the Add
/// Transaction dropdown until at least one transaction already carried
/// it. Now the full known category list is always included, in addition
/// to any categories seen in the data (which covers free-text "Other"
/// entries the user typed manually).
List<String> categoriesFrom(List<Transaction> transactions) {
  final Set<String> known = {
    ...CategoryMatcher.allCategories,
    for (final t in transactions) t.category,
  };
  final List<String> sorted = known.toList()..sort();
  return ['All', ...sorted];
}