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
    'SLCBNK': 'Slice',
  };

  // Amount with a currency marker: "Rs.500", "Rs 500.00", "INR 500",
  // "₹500.50" etc. The \b stops "rs" inside ordinary words from matching.
  static final RegExp _amountPattern = RegExp(
    r'(?:\brs\.?|\binr|₹)\s*([\d,]+(?:\.\d{1,2})?)',
    caseSensitive: false,
  );

  // Day 27: SBI-style UPI alerts put the amount straight after the verb with
  // no currency marker: "debited by 398.00 on date 20Sep26 ...". Because it
  // is tied to the debit/credit verb, it is tried BEFORE the currency
  // pattern so a later "Avl Bal Rs 1200" can never be mistaken for the amount.
  static final RegExp _amountAfterVerbPattern = RegExp(
    r'\b(?:debited|credited)\s+(?:by|with|for|of)\s+([\d,]+(?:\.\d{1,2})?)',
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

  // Day 28: "credit card" / "debit card" name the card, not the direction of
  // the money. Without this, "Rs. 2,000 spent on your credit card xx0678"
  // matched both a debit ("spent") and a credit ("credit") and failed.
  static final RegExp _cardWords = RegExp(
    r'\b(?:credit|debit)\s+cards?\b',
    caseSensitive: false,
  );

  // Merchant: text after "to", "at", "towards", or a VPA-looking token
  // (name@bank). Tries the SBI "trf to/from NAME Refno" form first, then
  // VPA (most reliable generic signal), then keyword-prefixed text.
  static final RegExp _trfPattern = RegExp(
    r'\btrf\s+(?:to|from)\s+([A-Za-z0-9@.\-_ ]{2,40}?)\s+ref(?:\s?no)?\b',
    caseSensitive: false,
  );
  static final RegExp _vpaPattern = RegExp(
    r'([a-zA-Z0-9.\-_]{2,})@([a-zA-Z]{2,})',
  );
  static final RegExp _merchantAfterKeyword = RegExp(
    r'\b(?:to|at|towards)\s+([A-Za-z0-9@.\-_ ]{2,40}?)(?:\s+(?:on|for|dt|ref|refno|txn|a\/c)\b|[.,]|$)',
    caseSensitive: false,
  );

  // ---- Day 28: Slice SMS (sender "AD-SLCBNK-S" / "VM-SLCBNK-T") ----------
  // Slice sends an SMS for money you SEND, e.g.
  //   "Rs. 5,000 sent from a/c xx9809 on 11-Sep-26 to Mr Ramanan Duraisamy
  //    (UPI Ref: 625405453535). Not you? Call 08048329999 - slice"
  // plus received-money, credit-card spend and credit-card repayment messages.
  static const String _sliceAmount =
      r'(?:rs\.?|inr|₹)\s*([\d,]+(?:\.\d{1,2})?)';

  // groups: 1 = amount, 2 = last 4 digits, 3 = name
  static final RegExp _sliceSent = RegExp(
    _sliceAmount +
        r'\s+sent\s+from\s+a/c\s*(?:xx+|\*+)?(\d{4})?[\s\S]*?\bto\s+([\s\S]+?)\s*(?:\(|\bupi\s+ref\b|\bnot you\b|$)',
    caseSensitive: false,
  );

  // groups: 1 = amount, 2 = last 4 digits, 3 = name
  static final RegExp _sliceReceived = RegExp(
    _sliceAmount +
        r'\s+received\s+in\s+slice\s+a/c\s*(?:xx+|\*+)?(\d{4})?[\s\S]*?\bfrom\s+([\s\S]+?)\s*(?:\(|\bupi\s+ref\b|\bnot you\b|\.\s|\.$|$)',
    caseSensitive: false,
  );

  // "Rs. 2,000 spent on your credit card xx0678 at MR Surya Sivakumar on
  // 06-Sep-26. Not you? Call 080-4832-9999 - slice"
  // groups: 1 = amount, 2 = card last 4 digits, 3 = merchant
  static final RegExp _sliceCardSpent = RegExp(
    _sliceAmount +
        r'\s+spent\s+on\s+your\s+credit\s+card\s*(?:xx+|\*+)?(\d{4})?[\s\S]*?\bat\s+([\s\S]+?)(?=\s+on\s+\d|\.\s|\(|$)',
    caseSensitive: false,
  );

  // "Repayment of Rs.2,059 received for the slice credit card."
  static final RegExp _sliceRepayment = RegExp(
    r'repayment\s+of\s+' + _sliceAmount + r'\s+received',
    caseSensitive: false,
  );

  static bool _isSliceSender(String sender) =>
      sender.toUpperCase().contains('SLCBNK');

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

    // Slice has its own wording; use it first and fall back to the generic
    // parser below if none of the Slice forms match.
    if (_isSliceSender(sender)) {
      final sliceResult =
          _parseSliceSms(sender: sender, body: body, smsDate: smsDate);
      if (sliceResult != null) return sliceResult;
    }

    // Direction is judged with "credit card" / "debit card" wording removed.
    final String directionText = body.replaceAll(_cardWords, ' ');
    final bool isDebit = _debitPattern.hasMatch(directionText);
    final bool isCredit = _creditPattern.hasMatch(directionText);
    final TransactionType? detectedType = (isDebit != isCredit)
        ? (isDebit ? TransactionType.debit : TransactionType.credit)
        : null;

    final String? merchantGuess = _extractMerchant(body);

    final amountMatch = _amountAfterVerbPattern.firstMatch(body) ??
        _amountPattern.firstMatch(body);
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
    final String category = CategoryMatcher.categorize(merchant, bankName: bankName);

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

  /// Slice SMS: money sent, money received, credit-card spending and
  /// credit-card repayments. Returns null when the message matches none of
  /// these forms.
  ///
  /// Credit-card items get a source like "Slice credit card (xx0678)" so they
  /// are told apart from the Slice bank account ("Slice • 9809"): card
  /// spending is charged to the card, not to the Slice bank balance.
  static SmsParseResult? _parseSliceSms({
    required String sender,
    required String body,
    required DateTime smsDate,
  }) {
    double? amount;
    String? last4;
    String? merchant;
    TransactionType? type;
    var isCard = false;

    final repayment = _sliceRepayment.firstMatch(body);
    final cardSpent = _sliceCardSpent.firstMatch(body);
    final sent = _sliceSent.firstMatch(body);
    final received = _sliceReceived.firstMatch(body);

    if (repayment != null) {
      amount = _toAmount(repayment.group(1));
      type = TransactionType.credit;
      merchant = 'Slice credit card repayment';
      isCard = true;
    } else if (cardSpent != null) {
      amount = _toAmount(cardSpent.group(1));
      last4 = cardSpent.group(2);
      merchant = _cleanName(cardSpent.group(3));
      type = TransactionType.debit;
      isCard = true;
    } else if (sent != null) {
      amount = _toAmount(sent.group(1));
      last4 = sent.group(2);
      merchant = _cleanName(sent.group(3));
      type = TransactionType.debit;
    } else if (received != null) {
      amount = _toAmount(received.group(1));
      last4 = received.group(2);
      merchant = _cleanName(received.group(3));
      type = TransactionType.credit;
    } else {
      return null;
    }

    if (amount == null || amount <= 0 || type == null) return null;

    final String source;
    if (isCard) {
      source =
          last4 == null ? 'Slice credit card' : 'Slice credit card (xx$last4)';
    } else {
      source = last4 == null ? 'Slice' : 'Slice • $last4';
    }
    final String title = merchant ?? 'Slice';
    final String category = CategoryMatcher.categorize(title, bankName: 'Slice');

    final transaction = Transaction(
      id: '${smsDate.millisecondsSinceEpoch}_${body.hashCode}',
      title: title,
      source: source,
      amount: amount,
      date: smsDate,
      type: type,
      category: category,
    );

    return SmsParseResult.success(
      transaction,
      body,
      sender,
      bankName: source,
      smsDate: smsDate,
    );
  }

  static double? _toAmount(String? raw) {
    if (raw == null) return null;
    return double.tryParse(raw.replaceAll(',', ''));
  }

  static String? _cleanName(String? raw) {
    if (raw == null) return null;
    var value = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    while (value.endsWith('.') || value.endsWith(',')) {
      value = value.substring(0, value.length - 1).trim();
    }
    if (value.length > 40) {
      value = value.substring(0, 40).trim();
    }
    return value.isEmpty ? null : value;
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
    final trfMatch = _trfPattern.firstMatch(body);
    if (trfMatch != null) {
      final String candidate = trfMatch.group(1)!.trim();
      if (candidate.isNotEmpty) {
        return candidate;
      }
    }

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