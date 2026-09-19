import '../models/transaction.dart';

/// Category name for money moved between the user's own accounts.
/// Transfers are shown in the transaction list but must not count as
/// Income or Spent, otherwise every own-account move inflates both totals.
const String transferCategory = 'Transfer';

/// Case-insensitive so a hand-typed "transfer" in the category field works too.
bool isTransfer(Transaction t) {
  return t.category.trim().toLowerCase() == transferCategory.toLowerCase();
}

/// [transactions] without any transfers. Use this before computing totals.
List<Transaction> withoutTransfers(List<Transaction> transactions) {
  return transactions.where((t) => !isTransfer(t)).toList();
}

String _normalizeName(String input) {
  return input
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// True if [text] (a payer/payee name) contains one of [ownNames].
///
/// Matching goes one way only: the name shown on the payment must contain a
/// saved name. So a saved "Surya Narayanan Sivakumar" matches only that full
/// name, and never a shorter name such as a parent's "Sivakumar". If your
/// bank shows your name in more than one form, save each form. Names
/// shorter than 4 letters are ignored to avoid accidental matches.
bool matchesOwnName(String text, Iterable<String> ownNames) {
  final t = _normalizeName(text);
  if (t.length < 4) return false;
  for (final name in ownNames) {
    final n = _normalizeName(name);
    if (n.length < 4) continue;
    if (t.contains(n)) return true;
  }
  return false;
}