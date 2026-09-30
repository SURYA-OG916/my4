import 'package:another_telephony/telephony.dart' hide SmsFilter;

import '../db/database_helper.dart';
import '../models/transaction.dart';
import 'needs_review_store.dart';
import 'slice_balance.dart';
import 'sms_filter.dart';
import 'sms_parser.dart';
import 'transfer_helper.dart';

/// Day 36: the SMS-to-transactions pipeline, moved out of SmsReaderScreen so
/// it can also run when the app starts or comes back to the foreground.
/// Before this, a bank SMS (for example the SBI "debited by 10.00 ... trf to
/// Mr CHELLAPANDI" alert) only became a transaction if you happened to open
/// SMS Reader.
///
/// Changes compared with the old in-screen version:
///  - Messages are processed OLDEST FIRST. Slice's "received ... Avl Bal
///    Rs. 5,002.14" SMS is now applied before the later "sent Rs. 5,000" SMS,
///    so the Slice balance ends at 2.14 instead of 2.14 - 5000.
///  - A Slice SMS that prints an "Avl Bal" updates the Slice balance.
///  - A Slice bank-account credit that matches a Slice credit-card spend at
///    the user's own name (same amount, same day) is a card top-up, so it is
///    tagged Transfer instead of income.
///  - A bank SMS that matches a payment-app entry with no account (Quick
///    add, Google Pay ...) fills in the account on that entry instead of
///    raising a "possible duplicate".
///  - Only SMS from the last [_processDays] days are processed (older ones
///    were handled long ago); the inbox list on screen still shows all.
class SmsIngestResult {
  final List<SmsMessage> messages;
  final int autoAdded;
  final int enriched;
  final int skipped;
  final List<SmsParseResult> needsReview;

  /// True when the inbox could not be read (permission missing).
  final bool readFailed;

  const SmsIngestResult({
    required this.messages,
    required this.autoAdded,
    required this.enriched,
    required this.skipped,
    required this.needsReview,
    required this.readFailed,
  });
}

class SmsIngestor {
  SmsIngestor._();

  static const int _processDays = 90;

  static Future<SmsIngestResult>? _inFlight;

  /// Safe to call from several places at once: concurrent callers share one
  /// run, so the same SMS can never be added twice.
  static Future<SmsIngestResult> run() {
    final existing = _inFlight;
    if (existing != null) return existing;

    final future = _run().whenComplete(() {
      _inFlight = null;
    });
    _inFlight = future;
    return future;
  }

  static bool looksLikeTransactionSms(SmsMessage msg) {
    return SmsFilter.looksLikeTransaction(
      sender: msg.address ?? '',
      body: msg.body ?? '',
    );
  }

  static Future<SmsIngestResult> _run() async {
    List<SmsMessage> messages;
    try {
      messages = await Telephony.instance.getInboxSms(
        columns: [
          SmsColumn.ADDRESS,
          SmsColumn.BODY,
          SmsColumn.DATE,
        ],
        sortOrder: [
          OrderBy(SmsColumn.DATE, sort: Sort.DESC),
        ],
      );
    } catch (_) {
      return const SmsIngestResult(
        messages: [],
        autoAdded: 0,
        enriched: 0,
        skipped: 0,
        needsReview: [],
        readFailed: true,
      );
    }

    final cutoff = DateTime.now()
        .subtract(const Duration(days: _processDays))
        .millisecondsSinceEpoch;

    // Oldest first, so a balance printed in an earlier SMS is applied before
    // a later payment is subtracted from it.
    final flagged = messages
        .where(looksLikeTransactionSms)
        .where((m) => m.date == null || m.date! >= cutoff)
        .toList()
      ..sort((a, b) => (a.date ?? 0).compareTo(b.date ?? 0));

    final db = DatabaseHelper.instance;
    final ownNames = await db.getMyNames();

    var autoAdded = 0;
    var enriched = 0;
    var skipped = 0;
    final reviewList = <SmsParseResult>[];

    for (final msg in flagged) {
      final hash = DatabaseHelper.smsHash(
        sender: msg.address ?? '',
        body: msg.body ?? '',
        dateMillis: msg.date,
      );

      if (await db.isSmsProcessed(hash)) {
        skipped++;
        continue;
      }

      final result = SmsParser.parse(
        sender: msg.address ?? '',
        body: msg.body ?? '',
        dateMillis: msg.date,
      );

      if (!result.isSuccess) {
        reviewList.add(result);
        continue;
      }

      var txn = _tagOwnNameTransfer(result.transaction!, ownNames);
      final isSlice = isSliceSource(txn.source);
      final isCard = txn.source.toLowerCase().contains('card');

      final duplicates = await db.findPotentialDuplicates(
        amount: txn.amount,
        type: txn.type,
        date: txn.date,
      );

      // Slice bank-account credit that matches a Slice credit-card spend at
      // the user's own name: the money went card -> Slice account, so it is a
      // top-up between their own places, not income.
      if (isSlice &&
          !isCard &&
          txn.type == TransactionType.credit &&
          txn.category != transferCategory) {
        final cardLegs = await db.findPotentialDuplicates(
          amount: txn.amount,
          type: TransactionType.debit,
          date: txn.date,
        );
        final hasCardLeg = cardLegs.any((t) =>
            isSliceSource(t.source) &&
            t.source.toLowerCase().contains('card') &&
            t.category == transferCategory);
        if (hasCardLeg) {
          txn = _asTransfer(txn);
        }
      }

      // Slice is only compared with other Slice entries, so a same-amount
      // payment from another app or bank isn't flagged as its duplicate.
      final similar = isSlice
          ? duplicates.where((t) => isSliceSource(t.source)).toList()
          : duplicates;

      // A bank SMS for a payment already recorded from a payment app / Quick
      // add (which never know the account): fill in the account instead of
      // asking about a duplicate.
      if (!isSlice && result.accountLast4 != null && similar.length == 1) {
        final other = similar.first;
        final bankOnly = txn.source
            .replaceAll(RegExp(r'\s*\d{4}$'), '')
            .trim()
            .toLowerCase();
        final otherHasAccount = RegExp(r'\d{4}').hasMatch(other.source);
        final otherIsBank = bankOnly.isNotEmpty &&
            other.source.toLowerCase().startsWith(bankOnly);
        if (!otherHasAccount && !otherIsBank && other.type == txn.type) {
          await db.updateTransaction(Transaction(
            id: other.id,
            title: other.title,
            source: '${other.source} • ${txn.source}',
            amount: other.amount,
            date: other.date,
            type: other.type,
            category: other.category,
          ));
          await db.markSmsProcessed(hash);
          enriched++;
          continue;
        }
      }

      if (similar.isNotEmpty) {
        reviewList.add(SmsParseResult.failure(
          'Possible duplicate of an existing transaction (same '
          'amount, type, and date)',
          result.rawBody,
          result.sender,
          partialAmount: txn.amount,
          partialType: txn.type,
          partialMerchant: txn.title,
          bankName: txn.source,
          smsDate: txn.date,
        ));
        continue;
      }

      await db.insertTransaction(txn);
      await db.markSmsProcessed(hash);
      autoAdded++;

      if (isSlice && !isCard) {
        final balance = result.availableBalance;
        if (balance != null) {
          // The SMS states the balance outright: trust it.
          await SliceBalance.saveIfNewer(balance, txn.date);
        } else if (txn.type == TransactionType.debit) {
          await SliceBalance.applyPayment(
            signedAmount: -txn.amount,
            date: txn.date,
          );
        }
      }
    }

    NeedsReviewStore.instance.setAll(reviewList);

    return SmsIngestResult(
      messages: messages,
      autoAdded: autoAdded,
      enriched: enriched,
      skipped: skipped,
      needsReview: reviewList,
      readFailed: false,
    );
  }

  /// Returns [txn] retagged as Transfer when its title matches one of the
  /// user's own names; otherwise returns it unchanged.
  static Transaction _tagOwnNameTransfer(Transaction txn, List<String> ownNames) {
    if (txn.category == transferCategory) return txn;
    if (!matchesOwnName(txn.title, ownNames)) return txn;
    return _asTransfer(txn);
  }

  static Transaction _asTransfer(Transaction txn) {
    return Transaction(
      id: txn.id,
      title: txn.title,
      source: txn.source,
      amount: txn.amount,
      date: txn.date,
      type: txn.type,
      category: transferCategory,
    );
  }
}