import 'package:sqflite/sqflite.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:path/path.dart';
import '../models/transaction.dart' as model;
import '../models/budget.dart';

/// How many calendar days apart two entries can be and still be considered
/// a potential duplicate. Shared by DatabaseHelper.findPotentialDuplicates()
/// and NeedsReviewStore.findMatching() so both stay in sync — change this
/// one value to widen/narrow the window everywhere at once.
const int dedupWindowDays = 1;

class DatabaseHelper {
  DatabaseHelper._privateConstructor();
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'my4.db');
    return await openDatabase(
      path,
      version: 3,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE transactions (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        source TEXT NOT NULL,
        amount REAL NOT NULL,
        type TEXT NOT NULL,
        date TEXT NOT NULL,
        category TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE budgets (
        category TEXT PRIMARY KEY,
        limit_amount REAL NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE processed_sms (
        sms_hash TEXT PRIMARY KEY,
        processed_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE budgets (
          category TEXT PRIMARY KEY,
          limit_amount REAL NOT NULL
        )
      ''');
    }
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE processed_sms (
          sms_hash TEXT PRIMARY KEY,
          processed_at TEXT NOT NULL
        )
      ''');
    }
  }

  Future<int> insertTransaction(model.Transaction txn) async {
    final db = await instance.database;
    return await db.insert('transactions', txn.toMap());
  }

  Future<int> updateTransaction(model.Transaction txn) async {
    final db = await instance.database;
    return await db.update(
      'transactions',
      txn.toMap(),
      where: 'id = ?',
      whereArgs: [txn.id],
    );
  }

  Future<int> deleteTransaction(String id) async {
    final db = await instance.database;
    return await db.delete(
      'transactions',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<model.Transaction>> getAllTransactions() async {
    final db = await instance.database;
    final result = await db.query('transactions', orderBy: 'date DESC');
    return result.map((map) => model.Transaction.fromMap(map)).toList();
  }

  // --- Duplicate detection ---

  /// True if [a] and [b] fall within [dedupWindowDays] calendar days of
  /// each other. Compares calendar days (not raw Duration), so an SMS
  /// timestamped 11:58pm and a manual entry dated the next morning are
  /// correctly treated as 1 day apart, not 0.
  bool _isWithinDedupWindow(DateTime a, DateTime b) {
    final aDay = DateTime(a.year, a.month, a.day);
    final bDay = DateTime(b.year, b.month, b.day);
    final diff = aDay.difference(bDay).inDays.abs();
    return diff <= dedupWindowDays;
  }

  /// Finds existing transactions that match [amount], [type], and fall
  /// within [dedupWindowDays] calendar days of [date]. Deliberately does
  /// NOT match on title/source — those vary too much between how an SMS
  /// parses a merchant name and how a user manually types one, and fuzzy
  /// string matching there risks false positives (flagging two genuinely
  /// different purchases as duplicates). Amount + type + a tight date
  /// window is a lower-noise signal for "this may already be in the
  /// ledger" — the window (rather than exact-day equality) also catches
  /// cases where an SMS timestamp and a manually-entered date land on
  /// adjacent calendar days for what's really the same transaction.
  Future<List<model.Transaction>> findPotentialDuplicates({
    required double amount,
    required model.TransactionType type,
    required DateTime date,
  }) async {
    final db = await instance.database;
    final rows = await db.query(
      'transactions',
      where: 'amount = ?',
      whereArgs: [amount],
    );

    final candidates = rows.map((r) => model.Transaction.fromMap(r)).toList();

    return candidates
        .where((t) => t.type == type && _isWithinDedupWindow(t.date, date))
        .toList();
  }

  // --- Budget CRUD ---

  Future<int> setBudget(Budget budget) async {
    final db = await instance.database;
    return await db.insert(
      'budgets',
      budget.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> deleteBudget(String category) async {
    final db = await instance.database;
    return await db.delete(
      'budgets',
      where: 'category = ?',
      whereArgs: [category],
    );
  }

  Future<List<Budget>> getAllBudgets() async {
    final db = await instance.database;
    final result = await db.query('budgets');
    return result.map((map) => Budget.fromMap(map)).toList();
  }

  // --- SMS dedup ---

  /// Deterministic fingerprint for an SMS: sender + body + date.
  static String smsHash({
    required String sender,
    required String body,
    required int? dateMillis,
  }) {
    final raw = '$sender|$body|${dateMillis ?? ''}';
    return sha256.convert(utf8.encode(raw)).toString();
  }

  Future<bool> isSmsProcessed(String smsHash) async {
    final db = await instance.database;
    final result = await db.query(
      'processed_sms',
      where: 'sms_hash = ?',
      whereArgs: [smsHash],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  Future<void> markSmsProcessed(String smsHash) async {
    final db = await instance.database;
    await db.insert(
      'processed_sms',
      {
        'sms_hash': smsHash,
        'processed_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }
}