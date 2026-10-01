import 'package:flutter/material.dart';
import 'models/transaction.dart';
import 'db/database_helper.dart';
import 'summary_header.dart';
import 'utils/transaction_grouping.dart';
import 'utils/date_range_helper.dart';
import 'utils/category_helper.dart';
import 'utils/duplicate_helper.dart';
import 'utils/needs_review_store.dart';
import 'utils/notification_ingestor.dart';
import 'utils/balance_helper.dart';
import 'utils/category_matcher.dart';
import 'utils/transfer_helper.dart';
import 'utils/category_colors.dart';
import 'screens/transaction_detail_screen.dart';
import 'screens/add_transaction_screen.dart';
import 'screens/category_summary_screen.dart';
import 'screens/sms_reader_screen.dart';
import 'screens/notification_reader_screen.dart';
import 'screens/accounts_screen.dart';
import 'screens/trends_screen.dart';
import 'screens/export_screen.dart';
import 'screens/recurring_screen.dart';
import 'widgets/category_filter_chips.dart';
import 'widgets/lock_gate.dart';
import 'widgets/month_selector.dart';
import 'widgets/quick_add_sheet.dart';

// Day 38: app-wide palette, shared with the Accounts screen.
const Color _navy = Color(0xFF1F2A44);
const Color _navySoft = Color(0xFF3B4A6B);
const Color _accent = Color(0xFF6B8CAE);
const Color _debitColor = Color(0xFFB5654A);
const Color _creditColor = Color(0xFF5A8F6E);
const Color _transferColor = Color(0xFF9E9E9E);

void main() {
  runApp(const MyApp());
}

// Day 33: direction filter on the main screen. Received = credits,
// Sent = debits. It combines with the month, category chips and search.
enum DirectionFilter { all, received, sent }

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MY4',
      // Day 35: a quiet, elegant Material theme. Day 38: the seed and primary
      // are now the deep navy used on the Accounts screen, so buttons, chips
      // and floating buttons stop coming out stock blue/cyan.
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _navySoft,
          brightness: Brightness.light,
        ).copyWith(
          primary: _navy,
          onPrimary: Colors.white,
        ),
        scaffoldBackgroundColor: const Color(0xFFFAFAF8),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFFAFAF8),
          foregroundColor: Color(0xFF2B2B2B),
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: Color(0xFF2B2B2B),
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        listTileTheme: const ListTileThemeData(
          iconColor: Color(0xFF5C5C5C),
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: _navy,
          foregroundColor: Colors.white,
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: _navy,
          contentTextStyle: const TextStyle(color: Colors.white),
          actionTextColor: const Color(0xFFBFD3EA),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      // Day 27: LockGate sits above the Navigator so it also covers every
      // screen that has been pushed, not just the home screen.
      builder: (context, child) =>
          LockGate(child: child ?? const SizedBox.shrink()),
      home: const TransactionListScreen(),
    );
  }
}

class TransactionListScreen extends StatefulWidget {
  const TransactionListScreen({super.key});

  @override
  State<TransactionListScreen> createState() => _TransactionListScreenState();
}

class _TransactionListScreenState extends State<TransactionListScreen>
    with WidgetsBindingObserver {
  String selectedCategory = 'All';
  List<Transaction> transactions = [];
  bool _isLoading = true;

  // Day 33: All / Received / Sent selector state.
  DirectionFilter _direction = DirectionFilter.all;

  // Bank balance the user set on the Accounts screen (null = not set).
  BalanceSnapshot? _balanceSnapshot;

  // --- Month filter state ---
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);

  // --- Search state ---
  bool _isSearching = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startUp();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
  }

  // When the app comes back to the foreground, pick up any UPI-app
  // notifications captured in the background.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncNotifications();
    }
  }

  Future<void> _startUp() async {
    try {
      await NotificationIngestor.run();
    } catch (_) {
      // Notification capture is optional; never block the app on it.
    }
    await _loadTransactions();
  }

  Future<void> _syncNotifications() async {
    try {
      final result = await NotificationIngestor.run();
      if (result.addedCount > 0 && mounted) {
        await _loadTransactions();
      }
    } catch (_) {
      // Notification capture is optional.
    }
  }

  Future<void> _loadTransactions() async {
    final loaded = await DatabaseHelper.instance.getAllTransactions();
    final snapshot = await BalanceHelper.loadSnapshot();
    setState(() {
      transactions = loaded;
      _balanceSnapshot = snapshot;
      _isLoading = false;
    });
  }

  Future<void> _openAddTransactionScreen() async {
    final categories = categoriesFrom(transactions);

    final result = await Navigator.push<Transaction>(
      context,
      MaterialPageRoute(
        builder: (context) => AddTransactionScreen(
          existingCategories: categories,
        ),
      ),
    );

    if (result != null) {
      final duplicates = await DatabaseHelper.instance.findPotentialDuplicates(
        amount: result.amount,
        type: result.type,
        date: result.date,
      );

      // Also check unresolved SMS still sitting in Needs Review — previously
      // only the database was checked, so a manual "+" add for the same
      // transaction a pending needs-review SMS represents went through with
      // no warning at all.
      final needsReviewDuplicates = NeedsReviewStore.instance.findMatching(
        amount: result.amount,
        type: result.type,
        date: result.date,
      );

      if (duplicates.isNotEmpty || needsReviewDuplicates.isNotEmpty) {
        if (!mounted) return;
        final proceed = await confirmPossibleDuplicate(
          context,
          existingDuplicates: duplicates,
          needsReviewDuplicates: needsReviewDuplicates,
        );
        if (!proceed) return;
      }

      await DatabaseHelper.instance.insertTransaction(result);
      setState(() {
        transactions.add(result);
      });
    }
  }

  // Fast path for payments the UPI apps never notify about (money you send).
  Future<void> _openQuickAdd() async {
    final quick = await showQuickAddSheet(context);
    if (quick == null) return;

    final ownNames = await DatabaseHelper.instance.getMyNames();
    final category = matchesOwnName(quick.title, ownNames)
        ? transferCategory
        : CategoryMatcher.categorize(quick.title);

    // Day 36: uses the date/time the user picked in the sheet, not always
    // "now" — a Quick Add is often entered after the fact.
    final txn = Transaction(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: quick.title,
      source: quick.source,
      amount: quick.amount,
      date: quick.date,
      type: quick.type,
      category: category,
    );

    final duplicates = await DatabaseHelper.instance.findPotentialDuplicates(
      amount: txn.amount,
      type: txn.type,
      date: txn.date,
    );
    final needsReviewDuplicates = NeedsReviewStore.instance.findMatching(
      amount: txn.amount,
      type: txn.type,
      date: txn.date,
    );

    if (duplicates.isNotEmpty || needsReviewDuplicates.isNotEmpty) {
      if (!mounted) return;
      final proceed = await confirmPossibleDuplicate(
        context,
        existingDuplicates: duplicates,
        needsReviewDuplicates: needsReviewDuplicates,
      );
      if (!proceed) return;
    }

    await DatabaseHelper.instance.insertTransaction(txn);
    if (!mounted) return;
    setState(() {
      transactions.add(txn);
    });
  }

  void _openCategorySummary(List<Transaction> monthFiltered) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CategorySummaryScreen(
          transactions: monthFiltered,
          monthLabel: _monthLabel(_selectedMonth),
        ),
      ),
    );
  }

  void _openRecurringScreen() {
    Navigator.pop(context); // close the drawer first
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RecurringScreen(transactions: transactions),
      ),
    );
  }

  Future<void> _openNotificationReader() async {
    Navigator.pop(context); // close the drawer first
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const NotificationReaderScreen(),
      ),
    );
    // The screen may have added transactions (auto-ingest or "Add anyway").
    await _loadTransactions();
  }

  Future<void> _openAccountsScreen() async {
    Navigator.pop(context); // close the drawer first
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AccountsScreen(),
      ),
    );
    // Balance, names and transfer tagging may have changed.
    await _loadTransactions();
  }

  void _openExportScreen() {
    Navigator.pop(context); // close the drawer first
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ExportScreen()),
    );
  }

  Future<void> _openTrendsScreen() async {
    Navigator.pop(context); // close the drawer first
    final pickedMonth = await Navigator.push<DateTime>(
      context,
      MaterialPageRoute(builder: (context) => const TrendsScreen()),
    );
    if (pickedMonth != null) {
      setState(() {
        _selectedMonth = DateTime(pickedMonth.year, pickedMonth.month, 1);
      });
    }
  }

  Future<void> _openSmsReaderScreen() async {
    Navigator.pop(context); // close the drawer first
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SmsReaderScreen()),
    );
    await _loadTransactions();
  }

  String _monthLabel(DateTime month) {
    const monthNames = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${monthNames[month.month - 1]} ${month.year}';
  }

  // Day 32: delete now shows an UNDO Snackbar instead of asking for
  // confirmation first. The full Transaction object is kept in memory, so
  // UNDO re-inserts it with its original id, date, category and source.
  Future<void> _deleteTransaction(Transaction txn) async {
    // Capture the messenger before any await so it stays valid.
    final messenger = ScaffoldMessenger.of(context);

    await DatabaseHelper.instance.deleteTransaction(txn.id);
    if (!mounted) return;
    setState(() {
      transactions.removeWhere((t) => t.id == txn.id);
    });

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text('Deleted "${txn.title}"'),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'UNDO',
          onPressed: () => _undoDelete(txn),
        ),
      ),
    );
  }

  Future<void> _undoDelete(Transaction txn) async {
    // Guard against a double tap re-inserting the same id twice.
    if (transactions.any((t) => t.id == txn.id)) return;

    await DatabaseHelper.instance.insertTransaction(txn);
    if (!mounted) return;
    setState(() {
      transactions.add(txn);
    });
  }

  // Day 38: the tap-to-open-detail logic, shared by the whole row.
  Future<void> _openTransactionDetail(
    Transaction txn,
    List<String> categories,
  ) async {
    final updated = await Navigator.push<Transaction>(
      context,
      MaterialPageRoute(
        builder: (context) => TransactionDetailScreen(
          transaction: txn,
          existingCategories: categories,
        ),
      ),
    );

    if (updated != null) {
      await DatabaseHelper.instance.updateTransaction(updated);
      setState(() {
        final index = transactions.indexWhere((t) => t.id == updated.id);
        if (index != -1) {
          transactions[index] = updated;
        }
      });
    }
  }

  Future<void> _showTransactionOptions(Transaction txn) async {
    final categories = categoriesFrom(transactions);

    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Edit'),
                onTap: () async {
                  Navigator.pop(ctx); // close the sheet first
                  final updated = await Navigator.push<Transaction>(
                    context,
                    MaterialPageRoute(
                      builder: (context) => TransactionDetailScreen(
                        transaction: txn,
                        existingCategories: categories,
                      ),
                    ),
                  );
                  if (updated != null) {
                    await DatabaseHelper.instance.updateTransaction(updated);
                    setState(() {
                      final index =
                          transactions.indexWhere((t) => t.id == updated.id);
                      if (index != -1) {
                        transactions[index] = updated;
                      }
                    });
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Delete', style: TextStyle(color: Colors.red)),
                onTap: () async {
                  Navigator.pop(ctx); // close the sheet first
                  await _deleteTransaction(txn);
                },
              ),
              ListTile(
                leading: const Icon(Icons.close),
                title: const Text('Cancel'),
                onTap: () => Navigator.pop(ctx),
              ),
            ],
          ),
        );
      },
    );
  }

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchQuery = '';
        _searchController.clear();
      }
    });
  }

  void _onMonthChanged(DateTime newMonth) {
    setState(() {
      _selectedMonth = newMonth;
    });
  }

  // Day 33: tapping Income / Spent on the summary card. Tapping the one that
  // is already active goes back to All.
  void _toggleDirection(DirectionFilter target) {
    setState(() {
      _direction = _direction == target ? DirectionFilter.all : target;
    });
  }

  // Day 33: the All / Received / Sent selector, shown under the summary card.
  // Day 38: selected segment is filled navy; unselected sit on white.
  Widget _buildDirectionSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<DirectionFilter>(
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.grey.shade700,
            selectedBackgroundColor: _navy,
            selectedForegroundColor: Colors.white,
            side: BorderSide(color: Colors.grey.shade300),
            textStyle: const TextStyle(fontWeight: FontWeight.w600),
          ),
          segments: const [
            ButtonSegment(
              value: DirectionFilter.all,
              label: Text('All'),
            ),
            ButtonSegment(
              value: DirectionFilter.received,
              label: Text('Received'),
            ),
            ButtonSegment(
              value: DirectionFilter.sent,
              label: Text('Sent'),
            ),
          ],
          selected: {_direction},
          onSelectionChanged: (selection) {
            setState(() {
              _direction = selection.first;
            });
          },
        ),
      ),
    );
  }

  // Day 33: one-line total for whatever the list is currently showing, for
  // example "15 transactions · ₹19636.00 received · 1 transfer (₹8847.00)
  // not counted". The count is every row in the list. The money totals leave
  // out own-account transfers so they agree with the summary card, unless the
  // Transfer chip itself is selected (then they are the whole point). Any
  // transfers left out are named at the end so the numbers can be checked
  // against the rows on screen.
  String _filteredSummaryText(List<Transaction> list) {
    final showTransfers = selectedCategory == transferCategory;
    final counted = showTransfers ? list : withoutTransfers(list).toList();
    final countedIds = counted.map((t) => t.id).toSet();
    final excluded = list.where((t) => !countedIds.contains(t.id)).toList();

    var received = 0.0;
    var sent = 0.0;
    for (final t in counted) {
      if (t.type == TransactionType.credit) {
        received += t.amount;
      } else {
        sent += t.amount;
      }
    }

    final total = list.length;
    final parts = <String>['$total transaction${total == 1 ? '' : 's'}'];
    if (received > 0) parts.add('₹${received.toStringAsFixed(2)} received');
    if (sent > 0) parts.add('₹${sent.toStringAsFixed(2)} sent');

    if (excluded.isNotEmpty) {
      final n = excluded.length;
      final label = '$n transfer${n == 1 ? '' : 's'}';
      final hasCredit = excluded.any((t) => t.type == TransactionType.credit);
      final hasDebit = excluded.any((t) => t.type == TransactionType.debit);
      if (hasCredit && hasDebit) {
        // Money in and money out mixed: one total would mislead.
        parts.add('$label not counted');
      } else {
        final amount = excluded.fold(0.0, (sum, t) => sum + t.amount);
        parts.add('$label (₹${amount.toStringAsFixed(2)}) not counted');
      }
    }
    return parts.join(' · ');
  }

  // Day 35: the app's secondary screens, moved out of the AppBar (which was
  // getting crowded with six+ icons) into a Drawer. Search and Category
  // Summary stay in the AppBar since they're used every session; everything
  // else here is opened less often.
  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: const Color(0xFFFAFAF8),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // Day 38: navy header instead of a plain title.
          Container(
            padding: EdgeInsets.fromLTRB(
              20,
              MediaQuery.of(context).padding.top + 28,
              20,
              24,
            ),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_navy, _navySoft],
              ),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MY4',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Your money, in one place',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _drawerItem(
            icon: Icons.show_chart,
            label: 'Spending Trends',
            color: const Color(0xFF6B8CAE),
            onTap: _openTrendsScreen,
          ),
          _drawerItem(
            icon: Icons.repeat,
            label: 'Recurring',
            color: const Color(0xFF9B7EBD),
            onTap: _openRecurringScreen,
          ),
          _drawerItem(
            icon: Icons.notifications_active_outlined,
            label: 'Notification Reader',
            color: const Color(0xFF5A8F6E),
            onTap: _openNotificationReader,
          ),
          _drawerItem(
            icon: Icons.sms_outlined,
            label: 'SMS Reader',
            color: const Color(0xFFC9A227),
            onTap: _openSmsReaderScreen,
          ),
          const SizedBox(height: 8),
          const Divider(height: 1, indent: 20, endIndent: 20),
          const SizedBox(height: 8),
          _drawerItem(
            icon: Icons.account_balance_outlined,
            label: 'Accounts & balance',
            color: const Color(0xFF6C6FA8),
            onTap: _openAccountsScreen,
          ),
          _drawerItem(
            icon: Icons.ios_share,
            label: 'Export data',
            color: const Color(0xFF6E6E6E),
            onTap: _openExportScreen,
          ),
        ],
      ),
    );
  }

  Widget _drawerItem({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: color.withOpacity(0.14),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
      onTap: onTap,
    );
  }

  // Day 38: one transaction row as a soft white card. Title stays on one
  // line, the category is a small coloured pill, and the amount sits on the
  // right next to the menu. Own-account transfers are drawn in grey.
  Widget _buildTransactionRow(Transaction txn, List<String> categories) {
    final isDebit = txn.type == TransactionType.debit;
    final isTransferTx = txn.category == transferCategory;
    final catColor = categoryColor(txn.category);
    final amountColor =
        isTransferTx ? _transferColor : (isDebit ? _debitColor : _creditColor);

    // Day 36: each row shows the time of day, not just the date the section
    // header groups by — needed to check the real order of same-day entries.
    final time = '${txn.date.hour.toString().padLeft(2, '0')}:'
        '${txn.date.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openTransactionDetail(txn, categories),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 2, 10),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: catColor.withOpacity(0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isDebit ? Icons.arrow_upward : Icons.arrow_downward,
                    color: catColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        txn.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        txn.source,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: categorySoftColor(txn.category),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                txn.category,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: categoryLabelColor(txn.category),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            time,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${isDebit ? '-' : '+'}₹${txn.amount.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: amountColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  padding: EdgeInsets.zero,
                  icon: Icon(
                    Icons.more_vert,
                    size: 20,
                    color: Colors.grey.shade600,
                  ),
                  onPressed: () => _showTransactionOptions(txn),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: _accent.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.receipt_long_outlined,
                size: 28,
                color: _navySoft,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Apply month filter first — everything downstream (header, chips, list,
    // category summary) is scoped to the selected month.
    final monthFiltered = transactions
        .where((t) => DateRangeHelper.isInMonth(t.date, _selectedMonth))
        .toList();

    // Real bank balance, based on the snapshot the user set (transfers ignored):
    //  - current month: today's balance ("Balance")
    //  - past month:    the balance at the end of that month ("Closing")
    //  - future month:  none, the header falls back to "Net"
    final snapshot = _balanceSnapshot;
    final now = DateTime.now();
    final selectedIndex = _selectedMonth.year * 12 + _selectedMonth.month;
    final currentIndex = now.year * 12 + now.month;
    double? bankBalance;
    String balanceLabel = 'Balance';
    if (snapshot != null) {
      if (selectedIndex == currentIndex) {
        bankBalance = BalanceHelper.currentBalance(snapshot, transactions);
      } else if (selectedIndex < currentIndex) {
        bankBalance = BalanceHelper.balanceAt(
          snapshot,
          transactions,
          BalanceHelper.endOfMonth(_selectedMonth),
        );
        balanceLabel = 'Closing';
      }
    }

    // Build category list dynamically from the month-filtered data
    final categories = categoriesFrom(monthFiltered);

    // Day 33: direction filter (Received = credits, Sent = debits).
    final directionFiltered = _direction == DirectionFilter.all
        ? monthFiltered
        : monthFiltered.where((t) {
            return _direction == DirectionFilter.received
                ? t.type == TransactionType.credit
                : t.type == TransactionType.debit;
          }).toList();

    // Apply category filter
    final categoryFiltered = selectedCategory == 'All'
        ? directionFiltered
        : directionFiltered
            .where((t) => t.category == selectedCategory)
            .toList();

    // Then apply search filter (title, source, category — case-insensitive)
    final query = _searchQuery.trim().toLowerCase();
    final filteredTransactions = query.isEmpty
        ? categoryFiltered
        : categoryFiltered.where((t) {
            return t.title.toLowerCase().contains(query) ||
                t.source.toLowerCase().contains(query) ||
                t.category.toLowerCase().contains(query);
          }).toList();

    // Day 33: the total line is shown only while some filter is active.
    final isFiltered = _direction != DirectionFilter.all ||
        selectedCategory != 'All' ||
        query.isNotEmpty;

    final grouped = groupTransactionsByDate(filteredTransactions);
    final listItems = buildGroupedListItems(grouped);

    return Scaffold(
      drawer: _buildDrawer(),
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search transactions...',
                  border: InputBorder.none,
                ),
                style: const TextStyle(fontSize: 18),
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                  });
                },
              )
            : const Text('MY4'),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            tooltip: _isSearching ? 'Close search' : 'Search',
            onPressed: _toggleSearch,
          ),
          IconButton(
            icon: const Icon(Icons.pie_chart_outline),
            tooltip: 'Category Summary',
            onPressed: () => _openCategorySummary(monthFiltered),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          MonthSelector(
            selectedMonth: _selectedMonth,
            onMonthChanged: _onMonthChanged,
          ),
          SummaryHeader(
            transactions: monthFiltered,
            bankBalance: bankBalance,
            balanceLabel: balanceLabel,
            onIncomeTap: () => _toggleDirection(DirectionFilter.received),
            onSpentTap: () => _toggleDirection(DirectionFilter.sent),
            incomeSelected: _direction == DirectionFilter.received,
            spentSelected: _direction == DirectionFilter.sent,
          ),
          const SizedBox(height: 8),
          _buildDirectionSelector(),
          const SizedBox(height: 8),
          CategoryFilterChips(
            categories: categories,
            selectedCategory: selectedCategory,
            onCategorySelected: (category) {
              setState(() {
                selectedCategory = category;
              });
            },
          ),
          const SizedBox(height: 8),
          if (isFiltered && filteredTransactions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _filteredSummaryText(filteredTransactions),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
              ),
            ),
          Expanded(
            child: listItems.isEmpty
                ? _buildEmptyState(
                    query.isNotEmpty
                        ? 'No transactions match "$_searchQuery"'
                        : (_direction == DirectionFilter.all
                            ? 'No transactions in this category'
                            : 'No transactions for this filter'),
                  )
                : ListView.builder(
                    // Extra bottom space so the floating buttons never cover
                    // the last row.
                    padding: const EdgeInsets.only(bottom: 120),
                    itemCount: listItems.length,
                    itemBuilder: (context, index) {
                      final item = listItems[index];

                      if (item is String) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(18, 14, 16, 8),
                          child: Text(
                            item,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.3,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        );
                      }

                      final txn = item as Transaction;
                      return _buildTransactionRow(txn, categories);
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.small(
            heroTag: 'quick_add',
            tooltip: 'Quick add',
            backgroundColor: const Color(0xFFDDE5EF),
            foregroundColor: _navy,
            elevation: 1,
            onPressed: _openQuickAdd,
            child: const Icon(Icons.bolt),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'add_transaction',
            tooltip: 'Add transaction',
            onPressed: _openAddTransactionScreen,
            child: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}