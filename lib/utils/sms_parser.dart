import '../models/transaction.dart';
import 'category_matcher.dart';

/// Result of attempting to parse a bank/UPI SMS into a transaction.
/// Either [transaction] is non-null (success) or [failureReason] explains
/// why parsing failed (so the UI can show it under "Needs review").
///
/// On failure, whatever fields the parser *did* manage to recover are
/// carried in [partialAmount] / [partialType] / [partialMerchant] / [bankName]
/// / [smsDate] so the UI can prefill an AddTransactionScreen instead of
/// making the user start from a blank form.
class SmsParseResult {
  final Transaction? transaction;
  final String? failureReason;
  final String rawBody;
  final String sender;

  final double? partialAmount;
  final TransactionType? partialType;
  final String? partialMerchant;
  final String bankName;
  final DateTime? smsDate;

  SmsParseResult.success(
    this.transaction,
    this.rawBody,
    this.sender, {
    this.bankName = '',
    this.smsDate,
  })  : failureReason = null,
        partialAmount = null,
        partialType = null,
        partialMerchant = null;

  SmsParseResult.failure(
    this.failureReason,
    this.rawBody,
    this.sender, {
    this.partialAmount,
    this.partialType,
    this.partialMerchant,
    this.bankName = '',
    this.smsDate,
  }) : transaction = null;

  bool get isSuccess => transaction != null;
}

class SmsParser {
  // Sender ID -> readable bank name. Extend as you encounter more banks.
  // Matching is done against the SMS sender address (case-insensitive,
  // substring match), since real sender IDs look like "HDFCBK", "VM-SBIINB",
  // "AD-ICICIB" etc.
  static const Map<String, String> _senderToBank = {
    'HDFC': 'HDFC Bank',
    'SBIINB': 'SBI',
    'SBI': 'SBI',
    'ICICI': 'ICICI Bank',
    'AXIS': 'Axis Bank',
    'KOTAK': 'Kotak Bank',
    'PNB': 'PNB',
    'YESBANK': 'Yes Bank',
    'YBL': 'Yes Bank',
    'IDFC': 'IDFC First Bank',
    'BOI': 'Bank of India',
    'CANARA': 'Canara Bank',
    'UNION': 'Union Bank',
  };

  // Amount: matches "Rs.500", "Rs 500.00", "INR 500", "₹500.50" etc.
  static final RegExp _amountPattern = RegExp(
    r'(?:rs\.?|inr|₹)\s*([\d,]+(?:\.\d{1,2})?)',
    caseSensitive: false,
  );

  // Debit / credit keywords.
  static final RegExp _debitPattern = RegExp(
    r'\b(debited|spent|paid|withdrawn|debit)\b',
    caseSensitive: false,
  );
  static final RegExp _creditPattern = RegExp(
    r'\b(credited|received|deposited|credit)\b',
    caseSensitive: false,
  );

  // Merchant: text after "to", "at", "towards", or a VPA-looking token
  // (name@bank). Tries VPA first since it's the most reliable signal,
  // then falls back to keyword-prefixed text.
  static final RegExp _vpaPattern = RegExp(
    r'([a-zA-Z0-9.\-_]{2,})@([a-zA-Z]{2,})',
  );
  static final RegExp _merchantAfterKeyword = RegExp(
    r'\b(?:to|at|towards)\s+([A-Za-z0-9@.\-_ ]{2,40}?)(?:\s+(?:on|for|dt|ref|txn|a\/c)\b|[.,]|$)',
    caseSensitive: false,
  );

  /// Attempts to parse a single SMS (sender + body) into a Transaction.
  /// [dateMillis] should be the SMS's own timestamp (msg.date) so the
  /// resulting transaction — or the partial data on failure — reflects
  /// when the SMS actually arrived, not when parsing happened to run.
  /// Returns a [SmsParseResult] indicating success or failure with a reason.
  static SmsParseResult parse({
    required String sender,
    required String body,
    int? dateMillis,
  }) {
    final String bankName = _detectBank(sender);
    final DateTime smsDate = dateMillis != null
        ? DateTime.fromMillisecondsSinceEpoch(dateMillis)
        : DateTime.now();

    final bool isDebit = _debitPattern.hasMatch(body);
    final bool isCredit = _creditPattern.hasMatch(body);
    final TransactionType? detectedType = (isDebit != isCredit)
        ? (isDebit ? TransactionType.debit : TransactionType.credit)
        : null;

    final String? merchantGuess = _extractMerchant(body);

    final amountMatch = _amountPattern.firstMatch(body);
    if (amountMatch == null) {
      return SmsParseResult.failure(
        'Could not find an amount in the message',
        body,
        sender,
        partialType: detectedType,
        partialMerchant: merchantGuess,
        bankName: bankName,
        smsDate: smsDate,
      );
    }

    final String amountStr = amountMatch.group(1)!.replaceAll(',', '');
    final double? amount = double.tryParse(amountStr);
    if (amount == null || amount <= 0) {
      return SmsParseResult.failure(
        'Amount "$amountStr" could not be parsed as a valid number',
        body,
        sender,
        partialType: detectedType,
        partialMerchant: merchantGuess,
        bankName: bankName,
        smsDate: smsDate,
      );
    }

    if (detectedType == null) {
      // Either neither debit/credit keyword matched, or (rarely) both did.
      return SmsParseResult.failure(
        'Could not determine debit or credit from the message',
        body,
        sender,
        partialAmount: amount,
        partialMerchant: merchantGuess,
        bankName: bankName,
        smsDate: smsDate,
      );
    }

    final String merchant = merchantGuess ?? bankName;
    final String category = CategoryMatcher.categorize(merchant);

    final transaction = Transaction(
      id: DateTime.now().millisecondsSinceEpoch.toString() +
          '_${sender.hashCode}',
      title: merchant,
      source: bankName,
      amount: amount,
      date: smsDate,
      type: detectedType,
      category: category,
    );

    return SmsParseResult.success(
      transaction,
      body,
      sender,
      bankName: bankName,
      smsDate: smsDate,
    );
  }

  static String _detectBank(String sender) {
    final String upperSender = sender.toUpperCase();

    for (final entry in _senderToBank.entries) {
      if (upperSender.contains(entry.key)) {
        return entry.value;
      }
    }

    return sender.isNotEmpty ? sender : 'Unknown Bank';
  }

  static String? _extractMerchant(String body) {
    final vpaMatch = _vpaPattern.firstMatch(body);
    if (vpaMatch != null) {
      return vpaMatch.group(0);
    }

    final keywordMatch = _merchantAfterKeyword.firstMatch(body);
    if (keywordMatch != null) {
      final String candidate = keywordMatch.group(1)!.trim();
      if (candidate.isNotEmpty) {
        return candidate;
      }
    }

    return null;
  }
}