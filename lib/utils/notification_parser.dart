// Day 26: parse UPI app notification text (GPay, PhonePe, Paytm, ...).
// Day 27: added Samsung Wallet and WhatsApp Pay ("X sent ₹1.00 to You").
// Day 28: added Slice ("You've got ₹1 from <name> in your slice bank a/c
//         xx9809. Avl. Bal. ₹2.14"). Slice payments must be approved by the
//         user before they are added (see approvalRequiredPackages), and the
//         "Avl. Bal." figure is read separately so it is never mistaken for
//         the payment amount.
// Day 32: PhonePe ("Money received" / "X has sent ₹1 to your bank account
//         State Bank of India-3835"): the sender name is now read, and the
//         words "bank account" are no longer part of the bank name.
//
// Self-contained on purpose: it depends on no MY4 models, so it can be tuned
// against real notification wording without touching the rest of the app.

enum NotificationDirection { debit, credit }

const String slicePackage = 'indwin.c3.shareapp';

// Apps whose payments are NEVER added automatically: they always wait for the
// user to tap Add in the Notification Reader.
const Set<String> approvalRequiredPackages = {slicePackage};

// Package name -> friendly app name. Keep in sync with ALLOWED_PACKAGES in
// MyNotificationListenerService.kt.
const Map<String, String> upiAppLabels = {
  'com.google.android.apps.nbu.paisa.user': 'Google Pay',
  'com.phonepe.app': 'PhonePe',
  'net.one97.paytm': 'Paytm',
  'in.org.npci.upiapp': 'BHIM',
  'com.dreamplug.androidapp': 'CRED',
  'com.samsung.android.spaymini': 'Samsung Wallet',
  'com.samsung.android.spay': 'Samsung Wallet',
  slicePackage: 'Slice',
  'com.whatsapp': 'WhatsApp Pay',
  'com.whatsapp.w4b': 'WhatsApp Pay',
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

  /// The "Avl. Bal." figure quoted in the notification, when there is one
  /// (Slice includes it). Not part of the payment amount.
  final double? availableBalance;
  final String? failureReason;

  const NotificationParseResult({
    required this.success,
    required this.appLabel,
    this.amount,
    this.direction,
    this.merchant,
    this.bankName,
    this.accountLast4,
    this.availableBalance,
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

  // Day 28: "Avl. Bal. ₹2.14", "Avl Bal: Rs 120.50", "Available balance ₹50".
  // Read first and cut out of the text so it can never be taken as the
  // payment amount.
  static final RegExp _availableBalance = RegExp(
    r"\b(?:avl|available)\.?\s*bal(?:ance)?\.?\s*(?:is|:)?\s*(?:₹|rs\.?|inr)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)",
    caseSensitive: false,
  );

  // Notifications that are NOT a completed payment.
  static final RegExp _skip = RegExp(
    r"\b(?:failed|declined|unsuccessful|pending|requests?|requested|reminder|overdue|scheduled|upcoming|offers?|cashback|rewards?|scratch|coupons?)\b",
    caseSensitive: false,
  );

  // Credit wording. The last alternative is WhatsApp Pay's
  // "Name sent ₹1.00 to You" form.
  static final RegExp _credit = RegExp(
    r"\b(?:received|credited|refund(?:ed)?|deposited)\b|\b(?:sent|paid)\s+you\b|\b(?:sent|paid)\s+(?:₹|rs\.?|inr)\s*[0-9][0-9,]*(?:\.[0-9]{1,2})?\s+to\s+you\b",
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

  // WhatsApp Pay: "MsYogarathinamK sent ₹1.00 to You" -> MsYogarathinamK
  static final RegExp _leadingSenderAmount = RegExp(
    r"^(?:you\s+)?(.+?)\s+(?:has\s+)?(?:sent|paid)\s+(?:₹|rs\.?|inr)\s*[0-9][0-9,]*(?:\.[0-9]{1,2})?\s+to\s+you\b",
    caseSensitive: false,
  );

  // Day 32, PhonePe: "Vinith Veeramuthu has sent ₹1 to your bank account
  // State Bank of India-3835" -> Vinith Veeramuthu
  static final RegExp _leadingSenderToYour = RegExp(
    r"^(?:you\s+)?(.+?)\s+(?:has\s+)?(?:sent|paid)\s+(?:₹|rs\.?|inr)\s*[0-9][0-9,]*(?:\.[0-9]{1,2})?\s+to\s+your\b",
    caseSensitive: false,
  );

  // Samsung Wallet: "sharaj7106@pingpay has sent money on your ... account."
  static final RegExp _vpaSentMoney = RegExp(
    r"([A-Za-z0-9._-]+@[A-Za-z0-9.-]+)\s+has\s+sent\s+money",
    caseSensitive: false,
  );

  // Slice received: "You've got ₹1 from Sridharan in your slice bank a/c ..."
  static final RegExp _fromInYour = RegExp(
    r"\bfrom\s+(.+?)\s+in\s+your\b",
    caseSensitive: false,
  );

  // Slice sent (best guess until a real sample is seen):
  // "... paid ₹1 to Ravi from your slice bank a/c ..."
  static final RegExp _toFromYour = RegExp(
    r"\bto\s+(.+?)\s+(?:from|using|via|in|on)\s+your\b",
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
  // Day 32: also matches PhonePe's "... to your bank account State Bank of
  // India-3835"; the leading "bank account" is stripped afterwards.
  static final RegExp _accountWithBank = RegExp(
    r"\byour\s+([A-Za-z][A-Za-z .&]*?)\s*[-–:]\s*(?:xx+|\*+)?(\d{4})\b",
    caseSensitive: false,
  );

  // Samsung Wallet: "... on your STATE BANK OF INDIA account."
  static final RegExp _bankOnYourAccount = RegExp(
    r"\bon\s+your\s+([A-Za-z][A-Za-z .&]*?)\s+account\b",
    caseSensitive: false,
  );

  // "... account XX3835", "... A/c ending 4321" (no bank name available)
  static final RegExp _accountOnly = RegExp(
    r"\b(?:a/c|acct?|account)\s*(?:no\.?)?\s*(?:xx+|\*+|ending(?:\s+with)?\s*)?(\d{4})\b",
    caseSensitive: false,
  );

  // Day 32: "bank account" on its own is also a generic word, not a bank name.
  static final RegExp _genericBankWord = RegExp(
    r"^(?:bank\s+)?(?:a/c|ac|acct|account|bank)$",
    caseSensitive: false,
  );

  // Day 32: leading "bank account " / "account " / "a/c " in front of a bank
  // name ("bank account State Bank of India" -> "State Bank of India").
  static final RegExp _leadingAccountWords = RegExp(
    r"^(?:bank\s+)?(?:account|a/c|acct?)\s+",
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
    final rawCombined = _collapse('$cleanTitle. $cleanText');

    // Pull out "Avl. Bal. ₹x" first and remove it from the text, so the
    // balance is never mistaken for the payment amount.
    double? availableBalance;
    var combined = rawCombined;
    final balanceMatch = _availableBalance.firstMatch(rawCombined);
    if (balanceMatch != null) {
      availableBalance =
          double.tryParse(balanceMatch.group(1)!.replaceAll(',', ''));
      combined = _collapse(rawCombined.replaceFirst(balanceMatch.group(0)!, ' '));
    }

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

    // Debit vs credit: whichever keyword appears first wins. On a tie
    // (WhatsApp's "sent ₹1.00 to You" matches both at the same spot) credit
    // wins, because the credit form is the more specific one.
    final creditMatch = _credit.firstMatch(combined);
    final debitMatch = _debit.firstMatch(combined);
    NotificationDirection? direction;
    if (creditMatch != null && debitMatch != null) {
      direction = creditMatch.start <= debitMatch.start
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

    // Slice: "from <name> in your ..." (received) / "to <name> from your ..."
    // (sent).
    if (packageName == slicePackage) {
      final pattern =
          direction == NotificationDirection.credit ? _fromInYour : _toFromYour;
      final m = pattern.firstMatch(combined);
      if (m != null) {
        merchant = _cleanMerchant(m.group(1)!);
      }
    }

    if (merchant == null && direction == NotificationDirection.credit) {
      for (final source in [cleanTitle, cleanText]) {
        for (final pattern in [
          _leadingSender,
          _leadingSenderAmount,
          _leadingSenderToYour,
        ]) {
          final m = pattern.firstMatch(source);
          if (m != null) {
            merchant = _cleanMerchant(m.group(1)!);
            if (merchant != null) break;
          }
        }
        if (merchant != null) break;
      }
      if (merchant == null) {
        final vpa = _vpaSentMoney.firstMatch(combined);
        if (vpa != null) {
          merchant = _cleanMerchant(vpa.group(1)!);
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
      final rawBank = _stripAccountWords(withBank.group(1)!.trim());
      accountLast4 = withBank.group(2);
      if (rawBank.isNotEmpty && !_genericBankWord.hasMatch(rawBank)) {
        bankName = _shortBankName(rawBank);
      }
    } else {
      final plain = _accountOnly.firstMatch(combined);
      if (plain != null) {
        accountLast4 = plain.group(1);
      }
    }

    // "... on your STATE BANK OF INDIA account." (no digits given)
    if (bankName == null) {
      final onYour = _bankOnYourAccount.firstMatch(combined);
      if (onYour != null) {
        final rawBank = onYour.group(1)!.trim();
        final lowerBank = rawBank.toLowerCase();
        if (!_genericBankWord.hasMatch(rawBank) &&
            (lowerBank.contains('bank') ||
                _shortBankNames.containsKey(lowerBank))) {
          bankName = _shortBankName(rawBank);
        }
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
      availableBalance: availableBalance,
    );
  }

  static String _collapse(String input) {
    return input.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _stripAccountWords(String raw) {
    return raw.replaceFirst(_leadingAccountWords, '').trim();
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
    final normalized =
        _collapse(raw.toLowerCase().replaceAll(RegExp(r'[^a-z ]'), ' '));
    return _shortBankNames[normalized] ?? _collapse(raw);
  }
}