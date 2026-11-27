import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sakuin/core/db/app_database.dart';
import 'package:sakuin/core/db/db_provider.dart';
import 'package:sakuin/core/services/notification_service.dart';
import 'package:sakuin/core/services/settings_service.dart';
import 'package:sakuin/core/utils/date_utils.dart';

class TransactionFilter {
  const TransactionFilter({
    this.startDayKey,
    this.endDayKey,
    this.type,
    this.categoryId,
    this.walletId,
    this.searchQuery = '',
  });

  final int? startDayKey;
  final int? endDayKey;
  final String? type; // 'expense' | 'income' | 'transfer' | null
  final int? categoryId;
  final int? walletId;
  final String searchQuery;

  bool get hasActiveFilters =>
      startDayKey != null ||
      endDayKey != null ||
      type != null ||
      categoryId != null ||
      walletId != null ||
      searchQuery.trim().isNotEmpty;

  TransactionFilter copyWith({
    int? startDayKey,
    bool clearStart = false,
    int? endDayKey,
    bool clearEnd = false,
    String? type,
    bool clearType = false,
    int? categoryId,
    bool clearCategory = false,
    int? walletId,
    bool clearWallet = false,
    String? searchQuery,
  }) {
    return TransactionFilter(
      startDayKey: clearStart ? null : (startDayKey ?? this.startDayKey),
      endDayKey: clearEnd ? null : (endDayKey ?? this.endDayKey),
      type: clearType ? null : (type ?? this.type),
      categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
      walletId: clearWallet ? null : (walletId ?? this.walletId),
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }
}

class PaginatedTransactionsState {
  const PaginatedTransactionsState({
    this.items = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.error,
  });

  final List<TransactionDetail> items;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final String? error;

  PaginatedTransactionsState copyWith({
    List<TransactionDetail>? items,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    String? error,
  }) {
    return PaginatedTransactionsState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: error,
    );
  }
}

final transactionFilterProvider = StateProvider<TransactionFilter>(
  (ref) => const TransactionFilter(),
);

/// Counter untuk memicu reload daftar terpaginasi saat transaksi ditambah/diubah/dihapus.
final transactionRevisionProvider = StateProvider<int>((ref) => 0);

final recentTransactionsProvider = StreamProvider<List<TransactionDetail>>((
  ref,
) {
  return ref.watch(appDatabaseProvider).watchRecentTransactions(limit: 8);
});

final quickItemsProvider = StreamProvider<List<ItemMemoryData>>((ref) {
  return ref.watch(appDatabaseProvider).watchQuickItems(limit: 12);
});

final merchantMemoryListProvider = StreamProvider<List<MerchantMemoryData>>((
  ref,
) {
  return ref.watch(appDatabaseProvider).watchAllMerchantMemory();
});

class PaginatedTransactionsNotifier
    extends StateNotifier<PaginatedTransactionsState> {
  PaginatedTransactionsNotifier(this._db, this._filter)
    : super(const PaginatedTransactionsState(isLoading: true)) {
    refresh();
  }

  static const int _pageSize = 35;
  final AppDatabase _db;
  final TransactionFilter _filter;

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final page = await _db.fetchTransactionsPage(
        limit: _pageSize,
        startDayKey: _filter.startDayKey,
        endDayKey: _filter.endDayKey,
        type: _filter.type,
        categoryId: _filter.categoryId,
        walletId: _filter.walletId,
        searchQuery: _filter.searchQuery,
      );
      if (!mounted) return;
      state = PaginatedTransactionsState(
        items: page,
        isLoading: false,
        hasMore: page.length == _pageSize,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(isLoading: false, error: '$e');
    }
  }

  Future<void> loadMore() async {
    if (state.isLoading || state.isLoadingMore || !state.hasMore) return;
    if (state.items.isEmpty) return;

    state = state.copyWith(isLoadingMore: true);
    final last = state.items.last.transaction;
    try {
      final page = await _db.fetchTransactionsPage(
        limit: _pageSize,
        cursorOccurredAt: last.occurredAt,
        cursorId: last.id,
        startDayKey: _filter.startDayKey,
        endDayKey: _filter.endDayKey,
        type: _filter.type,
        categoryId: _filter.categoryId,
        walletId: _filter.walletId,
        searchQuery: _filter.searchQuery,
      );
      if (!mounted) return;
      state = state.copyWith(
        items: [...state.items, ...page],
        isLoadingMore: false,
        hasMore: page.length == _pageSize,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(isLoadingMore: false, error: '$e');
    }
  }
}

final paginatedTransactionsProvider =
    StateNotifierProvider<
      PaginatedTransactionsNotifier,
      PaginatedTransactionsState
    >((ref) {
      final db = ref.watch(appDatabaseProvider);
      final filter = ref.watch(transactionFilterProvider);
      ref.watch(transactionRevisionProvider);
      return PaginatedTransactionsNotifier(db, filter);
    });

final transactionActionsProvider = Provider<TransactionActions>((ref) {
  return TransactionActions(ref);
});

class TransactionActions {
  TransactionActions(this._ref);

  final Ref _ref;

  AppDatabase get _db => _ref.read(appDatabaseProvider);

  void _bumpRevision() {
    _ref.read(transactionRevisionProvider.notifier).state++;
  }

  Future<int> saveTransaction({
    required String type,
    required int amount,
    required int walletId,
    int? categoryId,
    int? toWalletId,
    int? pocketId,
    int? toPocketId,
    int fee = 0,
    String note = '',
    String? itemName,
    String? merchantName,
    required DateTime occurredAt,
    int? existingId,
  }) async {
    final id = await _db.saveTransactionWithMemory(
      type: type,
      amount: amount,
      walletId: walletId,
      categoryId: categoryId,
      toWalletId: toWalletId,
      pocketId: pocketId,
      toPocketId: toPocketId,
      fee: fee,
      note: note,
      itemName: itemName,
      merchantName: merchantName,
      occurredAt: occurredAt,
      existingId: existingId,
    );
    await _ref.read(settingsProvider.notifier).setLastWalletId(walletId);
    _bumpRevision();

    // Cek peringatan anggaran 80% / 100% jika pengeluaran
    if (type == 'expense') {
      await _checkBudgetThresholds(categoryId);
    }
    return id;
  }

  Future<String> saveSplitTransactions({
    required String type,
    required int walletId,
    required DateTime occurredAt,
    required List<SplitComponentInput> components,
    int? replaceSingleTransactionId,
    String? existingSplitGroupId,
    String? externalRef,
  }) async {
    final groupId = await _db.saveSplitTransactions(
      type: type,
      walletId: walletId,
      occurredAt: occurredAt,
      components: components,
      replaceSingleTransactionId: replaceSingleTransactionId,
      existingSplitGroupId: existingSplitGroupId,
      externalRef: externalRef,
    );
    await _ref.read(settingsProvider.notifier).setLastWalletId(walletId);
    _bumpRevision();

    if (type == 'expense') {
      final uniqueCats = components
          .map((c) => c.categoryId)
          .whereType<int>()
          .toSet();
      if (uniqueCats.isEmpty) {
        await _checkBudgetThresholds(null);
      } else {
        for (final catId in uniqueCats) {
          await _checkBudgetThresholds(catId);
        }
      }
    }
    return groupId;
  }

  Future<void> _checkBudgetThresholds(int? categoryId) async {
    final budgets = await _db.select(_db.budgets).get();
    if (budgets.isEmpty) return;

    final startDay = _ref.read(settingsProvider).periodStartDay;
    final period = AppDateUtils.periodForDate(DateTime.now(), startDay);
    final notif = _ref.read(notificationServiceProvider);

    for (final budget in budgets) {
      if (budget.categoryId != null && budget.categoryId != categoryId) {
        continue;
      }
      if (budget.amount <= 0) continue;
      final spent = await _db.getCategorySpentInPeriod(
        categoryId: budget.categoryId,
        startDayKey: period.startDayKey,
        endDayKey: period.endDayKey,
      );
      final pct = ((spent / budget.amount) * 100).round();
      if (pct >= 80) {
        String label = 'Total Bulanan';
        if (budget.categoryId != null) {
          final cat = await (_db.select(
            _db.categories,
          )..where((c) => c.id.equals(budget.categoryId!))).getSingleOrNull();
          if (cat != null) label = cat.name;
        }
        await notif.showBudgetAlert(
          budgetId: budget.id,
          label: label,
          percent: pct,
          spent: spent,
          limit: budget.amount,
        );
      }
    }
  }

  Future<void> deleteTransaction(Transaction tx) async {
    await _db.deleteTransactionsByIds([tx.id]);
    _bumpRevision();
  }

  Future<void> deleteTransactions(List<Transaction> txs) async {
    await _db.deleteTransactionsByIds(txs.map((e) => e.id).toList());
    _bumpRevision();
  }

  Future<void> undoDelete(List<Transaction> txs) async {
    for (final tx in txs) {
      await _db.restoreDeletedTransaction(tx);
    }
    _bumpRevision();
  }

  /// Simpan langsung dari Item Cepat (1 ketukan jika quickSaveMode aktif).
  Future<Transaction?> quickSaveItem(ItemMemoryData item) async {
    final wallets = await _db.getWalletsWithBalances();
    if (wallets.isEmpty) return null;
    final walletId =
        item.lastWalletId != null &&
            wallets.any((w) => w.wallet.id == item.lastWalletId)
        ? item.lastWalletId!
        : (_ref.read(settingsProvider).lastWalletId ?? wallets.first.wallet.id);

    final id = await saveTransaction(
      type: item.type,
      amount: item.lastAmount,
      walletId: walletId,
      categoryId: item.lastCategoryId,
      pocketId: item.lastPocketId,
      itemName: item.displayName,
      merchantName: item.lastMerchantName,
      note: item.lastNote,
      occurredAt: DateTime.now(),
    );
    return (_db.select(
      _db.transactions,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<void> pinTransactionAsQuickItem(TransactionDetail detail) async {
    final tx = detail.transaction;
    if (tx.type == 'transfer') return;
    final label = (tx.itemName != null && tx.itemName!.trim().isNotEmpty)
        ? tx.itemName!.trim()
        : (detail.category?.name ?? 'Transaksi');
    await _db.upsertItemMemory(
      displayName: label,
      type: tx.type,
      amount: tx.amount,
      merchantName: tx.merchantName,
      categoryId: tx.categoryId,
      walletId: tx.walletId,
      pocketId: tx.pocketId,
      note: tx.note,
      isPinned: true,
    );
  }
}
