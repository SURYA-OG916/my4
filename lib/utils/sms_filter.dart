/// Day 28: decides whether an inbox SMS is a real money-movement alert
/// (as opposed to a promo, OTP, bill-due reminder, etc.).
///
/// An SMS is "transaction-like" only if ALL of these hold:
///   1. The sender looks like a DLT header (e.g. "VM-SBIINB", "JD-SBIUPI-S")
///      and is not a promotional header (suffix "-P").
///   2. The sender is not an app that MY4 reads from notifications instead
///      (none at the moment: Slice sends an SMS for money you SEND, so its
///      SMS are read, and the SMS reader always asks before adding them).
///   3. The body has no hard-block wording (OTP, pre-approved offers,
///      "avoid disconnection", due reminders, future debits, failures...).
///   4. A debit/credit verb sits next to an amount ("debited ... Rs.500",
///      "Rs 500 credited", "Rs. 5,000 sent from a/c ...", or the SBI form
///      "debited by 398.00").
///   5. The body has bank/UPI context (a/c, UPI, card, XX1234, VPA, ...).
class SmsFilter {
  SmsFilter._();

  static const String _verbs =
      r'(?:debited|credited|withdrawn|deposited|spent|paid|received|sent|transferred)';
  static const String _amount =
      r'(?:\brs\.?|\binr|₹)\s*[\d,]+(?:\.\d{1,2})?';

  // Same sender shape the app has used since Day 14.
  static final RegExp _senderShape = RegExp(r'^[A-Z]{2}-?[A-Z0-9]{3,}');

  // Indian DLT sender headers end in -P (promotional), -S (service),
  // -T (transactional) or -G (government). Promotional is never a transaction.
  static final RegExp _promoSenderSuffix = RegExp(r'-P$');

  // Apps whose payments MY4 captures from notifications only. Their SMS
  // alerts would be ignored here so the same payment is never added twice.
  // Empty on purpose: Slice's notifications only cover money you RECEIVE, and
  // its SMS cover money you send, so both are read (see sms_reader_screen).
  static const List<String> _notificationOnlySenders = <String>[];

  // Wording that means "this is NOT a completed transaction", even if an
  // amount and a verb also appear in the message.
  static final RegExp _hardBlock = RegExp(
    r'\botp\b|one[\s-]?time password|verification code|\bpre[\s-]?approved\b|'
    r'avoid (?:service )?(?:disconnection|suspension|late fee)|apply now|'
    r'click (?:here|below|the link)|download (?:the )?app|'
    r'requested (?:money|rs\.?|₹|inr|you)|collect request|payment request|'
    r'will be (?:debited|charged|deducted)|\b(?:is|are) due\b|'
    r'\b(?:min(?:imum)?|total)\.?\s+(?:amt\.?\s+|amount\s+)?due\b|'
    r'\bdue (?:date|on|by)\b|transaction (?:has )?(?:failed|declined)|'
    r'unsuccessful|declined',
    caseSensitive: false,
  );

  // "debited from a/c XX1234 for Rs.500", "spent on card ... Rs 250"
  static final RegExp _verbThenAmount = RegExp(
    r'\b' + _verbs + r'\b[\s\S]{0,80}?' + _amount,
    caseSensitive: false,
  );

  // "Rs.500.00 debited", "Rs 500 has been credited", "Rs. 5,000 sent from"
  static final RegExp _amountThenVerb = RegExp(
    _amount + r'\s*(?:has been\s+|have been\s+|is\s+|was\s+)?' + _verbs + r'\b',
    caseSensitive: false,
  );

  // SBI UPI form: "debited by 398.00", no currency marker.
  static final RegExp _verbByAmount = RegExp(
    r'\b(?:debited|credited)\s+(?:by|with|for|of)\s+[\d,]+',
    caseSensitive: false,
  );

  // Something that ties the message to an account / card / UPI handle.
  static final RegExp _bankContext = RegExp(
    r'\b(?:a\/c|acct|account|upi|card|imps|neft|rtgs|vpa|wallet|atm)\b|'
    r'\bx+\d{2,}|@[a-z]{2,}|\brefno\b|\bref\b|\btxn\b',
    caseSensitive: false,
  );

  static bool looksLikeTransaction({
    required String sender,
    required String body,
  }) {
    final String address = sender.trim().toUpperCase();
    final String text = body.trim();

    if (text.isEmpty) return false;
    if (!_senderShape.hasMatch(address)) return false;
    if (_promoSenderSuffix.hasMatch(address)) return false;
    for (final String blocked in _notificationOnlySenders) {
      if (address.contains(blocked)) return false;
    }
    if (_hardBlock.hasMatch(text)) return false;

    final bool movesMoney = _verbThenAmount.hasMatch(text) ||
        _amountThenVerb.hasMatch(text) ||
        _verbByAmount.hasMatch(text);
    if (!movesMoney) return false;

    return _bankContext.hasMatch(text);
  }

  /// Day 29 cleanup: true if [text] carries the same hard-block promo/OTP/
  /// due-reminder wording that [looksLikeTransaction] rejects live SMS for.
  /// Transactions already in the database don't keep the original SMS body,
  /// only a title/source, so this is checked against those fields instead —
  /// it reuses the exact same [_hardBlock] pattern so cleanup and the live
  /// filter can never disagree on what counts as "promo-looking".
  static bool looksLikePromo(String text) {
    if (text.trim().isEmpty) return false;
    return _hardBlock.hasMatch(text);
  }
}