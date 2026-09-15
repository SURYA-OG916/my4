import 'package:flutter/material.dart';
import '../models/transaction.dart';
import '../utils/sms_parser.dart';

/// Shows a confirmation dialog listing possible duplicates — existing
/// transactions already in the database, unresolved SMS still sitting in
/// Needs Review, or both — with the same amount/type/date as the one about
/// to be added. Returns true if the user chooses to add anyway (false if
/// they cancel or the dialog is dismissed).
///
/// Pass whichever lists apply; an empty list is simply omitted from the
/// message. Callers should still only invoke this when at least one of the
/// two lists is non-empty.
Future<bool> confirmPossibleDuplicate(
  BuildContext context, {
  List<Transaction> existingDuplicates = const [],
  List<SmsParseResult> needsReviewDuplicates = const [],
}) async {
  final parts = <String>[];

  if (existingDuplicates.isNotEmpty) {
    parts.add(
      existingDuplicates.length == 1
          ? 'A transaction with the same amount, type, and date already '
              'exists:\n"${existingDuplicates.first.title}" • '
              '${existingDuplicates.first.source}'
          : 'Found ${existingDuplicates.length} existing transactions with '
              'the same amount, type, and date.',
    );
  }

  if (needsReviewDuplicates.isNotEmpty) {
    parts.add(
      needsReviewDuplicates.length == 1
          ? 'There is also an unresolved SMS in Needs Review for the same '
              'amount, type, and date (from '
              '${needsReviewDuplicates.first.sender}).'
          : 'There are also ${needsReviewDuplicates.length} unresolved SMS '
              'in Needs Review for the same amount, type, and date.',
    );
  }

  final message = '${parts.join('\n\n')}\n\nAdd this one anyway?';

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Possible duplicate'),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Add Anyway'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}