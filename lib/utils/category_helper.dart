import '../models/transaction.dart';

/// Single source of truth for deriving the category list (with a leading
/// 'All') from a set of transactions. Used by both the main transaction
/// list/add/edit flows and the SMS needs-review draft flow, so every
/// screen that offers a category dropdown agrees on what's available.
List<String> categoriesFrom(List<Transaction> transactions) {
  return ['All', ...{for (final t in transactions) t.category}];
}