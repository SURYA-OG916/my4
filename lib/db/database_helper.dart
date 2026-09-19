import 'package:sqflite/sqflite.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:path/path.dart';
import '../models/transaction.dart' as model;
import '../models/budget.dart';
import '../models/bank_account.dart';

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
      version: 4,
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
    await _createV4Tables(db);
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
    if (oldVersion < 4) {
      await _createV4Tables(db);
    }
  }

  /// Version 4: accounts, "my names" (for own-account transfer detection),
  /// which UPI app uses which account, and simple key/value settings
  /// (currently the bank balance snapshot).
  Future<void> _createV4Tables(Database db) async {
    await db.execute('''
      CREATE TABLE accounts (
        id TEXT PRIMARY KEY,
        bank TEXT NOT NULL,
        last4 TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE my_names (
        name TEXT PRIMARY KEY
      )
    ''');
    await db.execute('''
      CREATE TABLE app_links (
        app_key TEXT NOT NULL,
        account_id TEXT NOT NULL,
        PRIMARY KEY (app_key, account_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE app_settings (
        setting_key TEXT PRIMARY KEY,
        setting_value TEXT NOT NULL
      )
    ''');
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

  /// Reverses [markSmsProcessed] — used to undo a needs-review dismissal
  /// (or a resolved add) so the SMS reappears on the next refresh instead
  /// of staying silently marked "done".
  Future<void> unmarkSmsProcessed(String smsHash) async {
    final db = await instance.database;
    await db.delete(
      'processed_sms',
      where: 'sms_hash = ?',
      whereArgs: [smsHash],
    );
  }

  // --- Bank accounts ---

  Future<int> insertAccount(BankAccount account) async {
    final db = await instance.database;
    return await db.insert('accounts', account.toMap());
  }

  /// Also removes the account from any UPI app links.
  Future<void> deleteAccount(String id) async {
    final db = await instance.database;
    await db.delete('accounts', where: 'id = ?', whereArgs: [id]);
    await db.delete('app_links', where: 'account_id = ?', whereArgs: [id]);
  }

  Future<List<BankAccount>> getAllAccounts() async {
    final db = await instance.database;
    final rows = await db.query('accounts', orderBy: 'bank ASC, last4 ASC');
    return rows.map((r) => BankAccount.fromMap(r)).toList();
  }

  // --- My names (own-account transfer detection) ---

  Future<void> addMyName(String name) async {
    final db = await instance.database;
    await db.insert(
      'my_names',
      {'name': name},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> deleteMyName(String name) async {
    final db = await instance.database;
    await db.delete('my_names', where: 'name = ?', whereArgs: [name]);
  }

  Future<List<String>> getMyNames() async {
    final db = await instance.database;
    final rows = await db.query('my_names', orderBy: 'name ASC');
    return rows.map((r) => r['name'] as String).toList();
  }

  // --- UPI app <-> account links ---

  /// app package name -> set of linked account ids.
  Future<Map<String, Set<String>>> getAppLinks() async {
    final db = await instance.database;
    final rows = await db.query('app_links');
    final links = <String, Set<String>>{};
    for (final r in rows) {
      final app = r['app_key'] as String;
      final account = r['account_id'] as String;
      links.putIfAbsent(app, () => <String>{}).add(account);
    }
    return links;
  }

  Future<void> setAppLink({
    required String appKey,
    required String accountId,
    required bool linked,
  }) async {
    final db = await instance.database;
    if (linked) {
      await db.insert(
        'app_links',
        {'app_key': appKey, 'account_id': accountId},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    } else {
      await db.delete(
        'app_links',
        where: 'app_key = ? AND account_id = ?',
        whereArgs: [appKey, accountId],
      );
    }
  }

  // --- Key/value settings ---

  Future<String?> getSetting(String key) async {
    final db = await instance.database;
    final rows = await db.query(
      'app_settings',
      where: 'setting_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['setting_value'] as String?;
  }

  Future<void> setSetting(String key, String value) async {
    final db = await instance.database;
    await db.insert(
      'app_settings',
      {'setting_key': key, 'setting_value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteSetting(String key) async {
    final db = await instance.database;
    await db.delete(
      'app_settings',
      where: 'setting_key = ?',
      whereArgs: [key],
    );
  }
}