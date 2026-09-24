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

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MY4',
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

    final now = DateTime.now();
    final txn = Transaction(
      id: now.millisecondsSinceEpoch.toString(),
      title: quick.title,
      source: quick.source,
      amount: quick.amount,
      date: now,
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
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RecurringScreen(transactions: transactions),
      ),
    );
  }

  Future<void> _openNotificationReader() async {
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
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ExportScreen()),
    );
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

  Future<void> _showTransactionOptions(Transaction txn) async {
    final categories = categoriesFrom(transactions);

    await showModalBottomSheet(
      context: context,
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

    // Apply category filter
    final categoryFiltered = selectedCategory == 'All'
        ? monthFiltered
        : monthFiltered.where((t) => t.category == selectedCategory).toList();

    // Then apply search filter (title, source, category — case-insensitive)
    final query = _searchQuery.trim().toLowerCase();
    final filteredTransactions = query.isEmpty
        ? categoryFiltered
        : categoryFiltered.where((t) {
            return t.title.toLowerCase().contains(query) ||
                t.source.toLowerCase().contains(query) ||
                t.category.toLowerCase().contains(query);
          }).toList();

    final grouped = groupTransactionsByDate(filteredTransactions);
    final listItems = buildGroupedListItems(grouped);

    return Scaffold(
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
            : const Text('Transactions'),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            tooltip: _isSearching ? 'Close search' : 'Search',
            onPressed: _toggleSearch,
          ),
          IconButton(
            icon: const Icon(Icons.pie_chart),
            tooltip: 'Category Summary',
            onPressed: () => _openCategorySummary(monthFiltered),
          ),
          IconButton(
            icon: const Icon(Icons.show_chart),
            tooltip: 'Spending Trends',
            onPressed: () async {
              final pickedMonth = await Navigator.push<DateTime>(
                context,
                MaterialPageRoute(builder: (context) => const TrendsScreen()),
              );
              if (pickedMonth != null) {
                setState(() {
                  _selectedMonth = DateTime(pickedMonth.year, pickedMonth.month, 1);
                });
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.repeat),
            tooltip: 'Recurring',
            onPressed: _openRecurringScreen,
          ),
          IconButton(
            icon: const Icon(Icons.notifications_active_outlined),
            tooltip: 'Notification Reader',
            onPressed: _openNotificationReader,
          ),
          IconButton(
            icon: const Icon(Icons.sms_outlined),
            tooltip: 'SMS Reader',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SmsReaderScreen()),
              );
              await _loadTransactions();
            },
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (value) {
              if (value == 'accounts') {
                _openAccountsScreen();
              } else if (value == 'export') {
                _openExportScreen();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'accounts', child: Text('Accounts & balance')),
              PopupMenuItem(value: 'export', child: Text('Export data')),
            ],
          ),
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
          ),
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
          Expanded(
            child: listItems.isEmpty
                ? Center(
                    child: Text(
                      query.isEmpty
                          ? 'No transactions in this category'
                          : 'No transactions match "$_searchQuery"',
                    ),
                  )
                : ListView.builder(
                    itemCount: listItems.length,
                    itemBuilder: (context, index) {
                      final item = listItems[index];

                      if (item is String) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                          child: Text(
                            item,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey,
                            ),
                          ),
                        );
                      }

                      final txn = item as Transaction;
                      return ListTile(
                        onTap: () async {
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
                            await DatabaseHelper.instance
                                .updateTransaction(updated);
                            setState(() {
                              final index = transactions
                                  .indexWhere((t) => t.id == updated.id);
                              if (index != -1) {
                                transactions[index] = updated;
                              }
                            });
                          }
                        },
                        leading: Icon(
                          txn.type == TransactionType.debit
                              ? Icons.arrow_upward
                              : Icons.arrow_downward,
                          color: txn.type == TransactionType.debit
                              ? Colors.red
                              : Colors.green,
                        ),
                        title: Text(txn.title),
                        subtitle: Text('${txn.source} • ${txn.category}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${txn.type == TransactionType.debit ? '-' : '+'}₹${txn.amount.toStringAsFixed(2)}',
                              style: TextStyle(
                                color: txn.type == TransactionType.debit
                                    ? Colors.red
                                    : Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.more_vert),
                              onPressed: () => _showTransactionOptions(txn),
                            ),
                          ],
                        ),
                      );
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