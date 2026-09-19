// Day 26: parse UPI app notification text (GPay, PhonePe, Paytm, ...).
//
// Self-contained on purpose: it depends on no MY4 models, so it can be tuned
// against real notification wording without touching the rest of the app.

enum NotificationDirection { debit, credit }

// Package name -> friendly app name. Keep in sync with ALLOWED_PACKAGES in
// MyNotificationListenerService.kt.
const Map<String, String> upiAppLabels = {
  'com.google.android.apps.nbu.paisa.user': 'Google Pay',
  'com.phonepe.app': 'PhonePe',
  'net.one97.paytm': 'Paytm',
  'in.org.npci.upiapp': 'BHIM',
  'com.dreamplug.androidapp': 'CRED',
  'com.android.shell': 'Test (adb shell)',
};

class NotificationParseResult {
  final bool success;
  final String appLabel;
  final double? amount;
  final NotificationDirection? direction;
  final String? merchant;
  final String? bankName;
  final String? accountLast4;
  final String? failureReason;

  const NotificationParseResult({
    required this.success,
    required this.appLabel,
    this.amount,
    this.direction,
    this.merchant,
    this.bankName,
    this.accountLast4,
    this.failureReason,
  });

  // Used as the transaction "source", e.g. "Paytm • SBI 3835".
  String get sourceLabel {
    final bank = bankName;
    final last4 = accountLast4;
    final account = [
      if (bank != null && bank.isNotEmpty) bank,
      if (last4 != null && last4.isNotEmpty) last4,
    ].join(' ');
    return account.isEmpty ? appLabel : '$appLabel • $account';
  }

  // One-line description used for the preview under each captured notification.
  String get summary {
    if (!success) {
      return failureReason ?? 'Could not parse';
    }
    final kind = direction == NotificationDirection.debit ? 'Debit' : 'Credit';
    final amountText = '₹${amount!.toStringAsFixed(2)}';
    return '$kind $amountText • ${merchant ?? 'merchant not found'}';
  }
}

class NotificationParser {
  // Amount: ₹250, Rs 250, Rs. 1,250.50, INR 99
  static final RegExp _amount = RegExp(
    r"(?:₹|\brs\.?|\binr)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)",
    caseSensitive: false,
  );

  // Notifications that are NOT a completed payment.
  static final RegExp _skip = RegExp(
    r"\b(?:failed|declined|unsuccessful|pending|requests?|requested|reminder|overdue|scheduled|upcoming|offers?|cashback|rewards?|scratch|coupons?)\b",
    caseSensitive: false,
  );

  static final RegExp _credit = RegExp(
    r"\b(?:received|credited|refund(?:ed)?|deposited)\b|\b(?:sent|paid)\s+you\b",
    caseSensitive: false,
  );

  static final RegExp _debit = RegExp(
    r"\b(?:paid(?!\s+you)|sent(?!\s+you)|debited|spent|payment\s+(?:of|to|successful)|transferred|withdrawn|purchase)\b",
    caseSensitive: false,
  );

  // "Ravi Kumar sent you ₹500" -> Ravi Kumar
  static final RegExp _leadingSender = RegExp(
    r"^(?:you\s+)?(.+?)\s+(?:has\s+)?(?:sent|paid)\s+you\b",
    caseSensitive: false,
  );

  // "... to Zomato", "... from Ravi", "... at Amazon", "... to 9876543210@ybl"
  static final RegExp _candidate = RegExp(
    r"\b(?:to|from|at)\s+([A-Za-z][A-Za-z0-9 &'._@-]*?|[0-9]{6,}[A-Za-z0-9@._-]*?)(?=\s+(?:using|via|through|on|for|with|at|successful|successfully|is|was|has|from|to|ref|upi|txn)\b|\s+(?:₹|rs\.?|inr)\s*\d|\.(?=\s|$)|[!,;:()\n]|$)",
    caseSensitive: false,
  );

  // Candidates like "your account" / "bank" are not merchants.
  static final RegExp _badMerchant = RegExp(
    r"^(?:your|you|a/c|ac|account|bank|the)\b",
    caseSensitive: false,
  );

  // "Deposited in your State Bank Of India - 3835 on 19 September ..."
  static final RegExp _accountWithBank = RegExp(
    r"\byour\s+([A-Za-z][A-Za-z .&]*?)\s*[-–:]\s*(?:xx+|\*+)?(\d{4})\b",
    caseSensitive: false,
  );

  // "... account XX3835", "... A/c ending 4321" (no bank name available)
  static final RegExp _accountOnly = RegExp(
    r"\b(?:a/c|acct?|account)\s*(?:no\.?)?\s*(?:xx+|\*+|ending(?:\s+with)?\s*)?(\d{4})\b",
    caseSensitive: false,
  );

  static final RegExp _genericBankWord = RegExp(
    r"^(?:a/c|ac|acct|account|bank)$",
    caseSensitive: false,
  );

  static const Map<String, String> _shortBankNames = {
    'state bank of india': 'SBI',
    'sbi': 'SBI',
    'hdfc bank': 'HDFC Bank',
    'icici bank': 'ICICI Bank',
    'axis bank': 'Axis Bank',
    'kotak mahindra bank': 'Kotak',
    'punjab national bank': 'PNB',
    'bank of baroda': 'Bank of Baroda',
    'canara bank': 'Canara Bank',
    'union bank of india': 'Union Bank',
    'indian bank': 'Indian Bank',
    'idfc first bank': 'IDFC FIRST',
  };

  static NotificationParseResult parse({
    required String packageName,
    required String title,
    required String text,
  }) {
    final appLabel = upiAppLabels[packageName] ?? packageName;
    final cleanTitle = _collapse(title);
    final cleanText = _collapse(text);
    final combined = _collapse('$cleanTitle. $cleanText');

    final amountMatch = _amount.firstMatch(combined);
    if (amountMatch == null) {
      return NotificationParseResult(
        success: false,
        appLabel: appLabel,
        failureReason: 'No amount found',
      );
    }
    final amount = double.tryParse(amountMatch.group(1)!.replaceAll(',', ''));
    if (amount == null || amount <= 0) {
      return NotificationParseResult(
        success: false,
        appLabel: appLabel,
        failureReason: 'Amount could not be read',
      );
    }

    if (_skip.hasMatch(combined)) {
      return NotificationParseResult(
        success: false,
        appLabel: appLabel,
        amount: amount,
        failureReason:
            'Not a completed payment (failed, pending, request or promotional)',
      );
    }

    // Debit vs credit: whichever keyword appears first wins.
    final creditMatch = _credit.firstMatch(combined);
    final debitMatch = _debit.firstMatch(combined);
    NotificationDirection? direction;
    if (creditMatch != null && debitMatch != null) {
      direction = creditMatch.start < debitMatch.start
          ? NotificationDirection.credit
          : NotificationDirection.debit;
    } else if (creditMatch != null) {
      direction = NotificationDirection.credit;
    } else if (debitMatch != null) {
      direction = NotificationDirection.debit;
    }

    if (direction == null) {
      return NotificationParseResult(
        success: false,
        appLabel: appLabel,
        amount: amount,
        failureReason: 'Could not tell if money was sent or received',
      );
    }

    String? merchant;

    if (direction == NotificationDirection.credit) {
      for (final source in [cleanTitle, cleanText]) {
        final m = _leadingSender.firstMatch(source);
        if (m != null) {
          merchant = _cleanMerchant(m.group(1)!);
          if (merchant != null) break;
        }
      }
    }

    if (merchant == null) {
      for (final m in _candidate.allMatches(combined)) {
        final candidate = m.group(1)!.trim();
        if (_badMerchant.hasMatch(candidate)) continue;
        merchant = _cleanMerchant(candidate);
        if (merchant != null) break;
      }
    }

    // Bank + last 4 digits of the account, when the notification mentions them.
    String? bankName;
    String? accountLast4;
    final withBank = _accountWithBank.firstMatch(combined);
    if (withBank != null) {
      final rawBank = withBank.group(1)!.trim();
      accountLast4 = withBank.group(2);
      if (!_genericBankWord.hasMatch(rawBank)) {
        bankName = _shortBankName(rawBank);
      }
    } else {
      final plain = _accountOnly.firstMatch(combined);
      if (plain != null) {
        accountLast4 = plain.group(1);
      }
    }

    return NotificationParseResult(
      success: true,
      appLabel: appLabel,
      amount: amount,
      direction: direction,
      merchant: merchant,
      bankName: bankName,
      accountLast4: accountLast4,
    );
  }

  static String _collapse(String input) {
    return input.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String? _cleanMerchant(String raw) {
    var value = _collapse(raw);
    while (value.endsWith('.') || value.endsWith(',')) {
      value = value.substring(0, value.length - 1).trim();
    }
    if (value.length > 40) {
      value = value.substring(0, 40).trim();
    }
    return value.isEmpty ? null : value;
  }

  static String _shortBankName(String raw) {
    final normalized = _collapse(raw.toLowerCase().replaceAll(RegExp(r'[^a-z ]'), ' '));
    return _shortBankNames[normalized] ?? _collapse(raw);
  }
}