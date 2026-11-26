import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sakuin/core/constants/app_colors.dart';
import 'package:sakuin/core/db/app_database.dart';
import 'package:sakuin/core/services/settings_service.dart';
import 'package:sakuin/core/utils/date_utils.dart';
import 'package:sakuin/core/utils/haptics.dart';
import 'package:sakuin/core/widgets/amount_text.dart';
import 'package:sakuin/core/widgets/empty_state.dart';
import 'package:sakuin/features/category/category_providers.dart';
import 'package:sakuin/features/transaction/split_transaction_sheet.dart';
import 'package:sakuin/features/transaction/transaction_form_sheet.dart';
import 'package:sakuin/features/transaction/transaction_providers.dart';
import 'package:sakuin/features/transaction/widgets/transaction_tile.dart';
import 'package:sakuin/features/wallet/wallet_providers.dart';

class TransactionListScreen extends ConsumerStatefulWidget {
  const TransactionListScreen({super.key});

  @override
  ConsumerState<TransactionListScreen> createState() =>
      _TransactionListScreenState();
}

class _TransactionListScreenState extends ConsumerState<TransactionListScreen> {
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final Set<int> _selectedIds = {};
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 320) {
      ref.read(paginatedTransactionsProvider.notifier).loadMore();
    }
  }

  Future<void> _deleteWithUndo(List<Transaction> txs) async {
    final actions = ref.read(transactionActionsProvider);
    final haptics = ref.read(settingsProvider).hapticsEnabled;
    AppHaptics.medium(haptics);
    await actions.deleteTransactions(txs);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            txs.length == 1
                ? 'Transaksi dihapus'
                : '${txs.length} transaksi dihapus',
          ),
          action: SnackBarAction(
            label: 'Urungkan',
            onPressed: () => actions.undoDelete(txs),
          ),
        ),
      );
  }

  Future<void> _showTransactionMenu(TransactionDetail detail) async {
    final tx = detail.transaction;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit transaksi'),
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
            if (tx.type != 'transfer')
              ListTile(
                leading: const Icon(Icons.call_split_rounded),
                title: Text(
                  tx.splitGroupId != null
                      ? 'Edit pecahan transaksi'
                      : 'Pecah jadi beberapa komponen',
                ),
                onTap: () => Navigator.pop(ctx, 'split'),
              ),
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('Duplikat ke hari ini'),
              onTap: () => Navigator.pop(ctx, 'duplicate'),
            ),
            if (tx.type != 'transfer')
              ListTile(
                leading: const Icon(Icons.push_pin_outlined),
                title: const Text('Jadikan Item Cepat di Beranda'),
                onTap: () => Navigator.pop(ctx, 'pin'),
              ),
            ListTile(
              leading: Icon(
                Icons.delete_outline_rounded,
                color: AppColors.expense(ctx),
              ),
              title: Text(
                'Hapus transaksi',
                style: TextStyle(color: AppColors.expense(ctx)),
              ),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'edit':
        await showTransactionFormSheet(context, existing: detail);
      case 'split':
        await showSplitExistingTransactionSheet(context, detail: detail);
      case 'duplicate':
        await showTransactionFormSheet(context, duplicateFrom: detail);
      case 'pin':
        await ref
            .read(transactionActionsProvider)
            .pinTransactionAsQuickItem(detail);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Disematkan ke Item Cepat di Beranda'),
            ),
          );
        }
      case 'delete':
        await _deleteWithUndo([tx]);
    }
  }

  Future<void> _showFilterSheet() async {
    final current = ref.read(transactionFilterProvider);
    final wallets =
        ref.read(walletsWithBalancesProvider).valueOrNull ?? const [];
    final categories = ref.read(allCategoriesProvider).valueOrNull ?? const [];

    String? type = current.type;
    int? walletId = current.walletId;
    int? categoryId = current.categoryId;
    int? startDay = current.startDayKey;
    int? endDay = current.endDayKey;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final tt = Theme.of(ctx).textTheme;
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Filter Transaksi', style: tt.titleLarge),
                    TextButton(
                      onPressed: () {
                        setModalState(() {
                          type = null;
                          walletId = null;
                          categoryId = null;
                          startDay = null;
                          endDay = null;
                        });
                      },
                      child: const Text('Reset'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text('Tipe', style: tt.labelMedium),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Semua'),
                      selected: type == null,
                      onSelected: (_) => setModalState(() => type = null),
                    ),
                    ChoiceChip(
                      label: const Text('Pengeluaran'),
                      selected: type == 'expense',
                      onSelected: (_) => setModalState(() => type = 'expense'),
                    ),
                    ChoiceChip(
                      label: const Text('Pemasukan'),
                      selected: type == 'income',
                      onSelected: (_) => setModalState(() => type = 'income'),
                    ),
                    ChoiceChip(
                      label: const Text('Transfer'),
                      selected: type == 'transfer',
                      onSelected: (_) => setModalState(() => type = 'transfer'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text('Rentang Tanggal', style: tt.labelMedium),
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  onPressed: () async {
                    final range = await showDateRangePicker(
                      context: ctx,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                      initialDateRange: startDay != null && endDay != null
                          ? DateTimeRange(
                              start: AppDateUtils.fromDayKey(startDay!),
                              end: AppDateUtils.fromDayKey(endDay!),
                            )
                          : null,
                    );
                    if (range != null) {
                      setModalState(() {
                        startDay = AppDateUtils.toDayKey(range.start);
                        endDay = AppDateUtils.toDayKey(range.end);
                      });
                    }
                  },
                  icon: const Icon(Icons.date_range_rounded),
                  label: Text(
                    startDay != null && endDay != null
                        ? '${AppDateUtils.formatShortDate(AppDateUtils.fromDayKey(startDay!))} – ${AppDateUtils.formatShortDate(AppDateUtils.fromDayKey(endDay!))}'
                        : 'Pilih rentang tanggal',
                  ),
                ),
                const SizedBox(height: 12),
                Text('Dompet', style: tt.labelMedium),
                const SizedBox(height: 6),
                DropdownButtonFormField<int?>(
                  initialValue: walletId,
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('Semua dompet'),
                    ),
                    for (final wb in wallets)
                      DropdownMenuItem<int?>(
                        value: wb.wallet.id,
                        child: Text(wb.wallet.name),
                      ),
                  ],
                  onChanged: (v) => setModalState(() => walletId = v),
                ),
                const SizedBox(height: 12),
                Text('Kategori', style: tt.labelMedium),
                const SizedBox(height: 6),
                DropdownButtonFormField<int?>(
                  initialValue: categoryId,
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('Semua kategori'),
                    ),
                    for (final c in categories.where((e) => !e.isArchived))
                      DropdownMenuItem<int?>(value: c.id, child: Text(c.name)),
                  ],
                  onChanged: (v) => setModalState(() => categoryId = v),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      ref
                          .read(transactionFilterProvider.notifier)
                          .state = TransactionFilter(
                        startDayKey: startDay,
                        endDayKey: endDay,
                        type: type,
                        categoryId: categoryId,
                        walletId: walletId,
                        searchQuery: current.searchQuery,
                      );
                      Navigator.pop(ctx);
                    },
                    child: const Text('Terapkan Filter'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(paginatedTransactionsProvider);
    final filter = ref.watch(transactionFilterProvider);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final selectionMode = _selectedIds.isNotEmpty;

    // Kelompokkan transaksi per dayKey (pertahankan urutan terbaru -> terlama)
    final grouped = <int, List<TransactionDetail>>{};
    for (final item in state.items) {
      grouped.putIfAbsent(item.transaction.dayKey, () => []).add(item);
    }
    final dayKeys = grouped.keys.toList();

    return Scaffold(
      floatingActionButton: selectionMode
          ? null
          : FloatingActionButton.extended(
              tooltip: 'Tambah transaksi',
              onPressed: () {
                AppHaptics.light(ref.read(settingsProvider).hapticsEnabled);
                showTransactionFormSheet(context);
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text('Catat'),
            ),
      appBar: selectionMode
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => setState(() => _selectedIds.clear()),
              ),
              title: Text('${_selectedIds.length} dipilih'),
              actions: [
                IconButton(
                  tooltip: 'Hapus terpilih',
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    color: AppColors.expense(context),
                  ),
                  onPressed: () async {
                    final toDelete = state.items
                        .where((e) => _selectedIds.contains(e.transaction.id))
                        .map((e) => e.transaction)
                        .toList();
                    setState(() => _selectedIds.clear());
                    await _deleteWithUndo(toDelete);
                  },
                ),
              ],
            )
          : AppBar(
              title: _searching
                  ? TextField(
                      controller: _searchCtrl,
                      autofocus: true,
                      decoration: const InputDecoration(
                        hintText: 'Cari item, catatan, kategori...',
                        border: InputBorder.none,
                        filled: false,
                      ),
                      onChanged: (val) {
                        ref.read(transactionFilterProvider.notifier).state =
                            filter.copyWith(searchQuery: val);
                      },
                    )
                  : const Text('Transaksi'),
              actions: [
                IconButton(
                  tooltip: _searching ? 'Tutup pencarian' : 'Cari transaksi',
                  icon: Icon(
                    _searching ? Icons.close_rounded : Icons.search_rounded,
                  ),
                  onPressed: () {
                    setState(() => _searching = !_searching);
                    if (!_searching) {
                      _searchCtrl.clear();
                      ref.read(transactionFilterProvider.notifier).state =
                          filter.copyWith(searchQuery: '');
                    }
                  },
                ),
                IconButton(
                  tooltip: 'Filter',
                  icon: Badge(
                    isLabelVisible: filter.hasActiveFilters,
                    child: const Icon(Icons.filter_list_rounded),
                  ),
                  onPressed: _showFilterSheet,
                ),
              ],
            ),
      body: Column(
        children: [
          if (filter.hasActiveFilters)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: cs.primaryContainer.withValues(alpha: 0.35),
              child: Row(
                children: [
                  const Icon(Icons.filter_alt_rounded, size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Filter aktif', style: tt.labelMedium)),
                  TextButton(
                    onPressed: () {
                      _searchCtrl.clear();
                      ref.read(transactionFilterProvider.notifier).state =
                          const TransactionFilter();
                    },
                    child: const Text('Hapus Filter'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: state.isLoading && state.items.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : state.items.isEmpty
                ? EmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: filter.hasActiveFilters
                        ? 'Tidak ada transaksi yang cocok'
                        : 'Belum ada transaksi',
                    subtitle: filter.hasActiveFilters
                        ? 'Coba ubah atau hapus filter pencarian.'
                        : 'Ketuk tombol + di bawah untuk mencatat transaksi pertamamu.',
                    actionLabel: filter.hasActiveFilters
                        ? 'Reset Filter'
                        : 'Catat Transaksi',
                    onAction: () {
                      if (filter.hasActiveFilters) {
                        _searchCtrl.clear();
                        ref.read(transactionFilterProvider.notifier).state =
                            const TransactionFilter();
                      } else {
                        showTransactionFormSheet(context);
                      }
                    },
                  )
                : RefreshIndicator(
                    onRefresh: () => ref
                        .read(paginatedTransactionsProvider.notifier)
                        .refresh(),
                    child: ListView.builder(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.only(bottom: 100),
                      itemCount: dayKeys.length + (state.hasMore ? 1 : 0),
                      itemBuilder: (ctx, idx) {
                        if (idx >= dayKeys.length) {
                          return const Padding(
                            padding: EdgeInsets.all(20),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }

                        final dayKey = dayKeys[idx];
                        final dayItems = grouped[dayKey]!;
                        var dayIncome = 0;
                        var dayExpense = 0;
                        for (final d in dayItems) {
                          if (d.transaction.type == 'income') {
                            dayIncome += d.transaction.amount;
                          } else if (d.transaction.type == 'expense') {
                            dayExpense += d.transaction.amount;
                          } else if (d.transaction.type == 'transfer' &&
                              d.transaction.fee > 0) {
                            dayExpense += d.transaction.fee;
                          }
                        }
                        final dayNet = dayIncome - dayExpense;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                              color: Theme.of(context).scaffoldBackgroundColor,
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    AppDateUtils.formatRelativeHeader(dayKey),
                                    style: tt.titleSmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                  AmountText(
                                    amount: dayNet,
                                    type: dayNet < 0
                                        ? 'expense'
                                        : (dayNet > 0 ? 'income' : null),
                                    signed: true,
                                    style: tt.labelLarge,
                                  ),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: Card(
                                clipBehavior: Clip.antiAlias,
                                child: Column(
                                  children: [
                                    for (
                                      var i = 0;
                                      i < dayItems.length;
                                      i++
                                    ) ...[
                                      if (i > 0) const Divider(height: 1),
                                      TransactionTile(
                                        detail: dayItems[i],
                                        selectionMode: selectionMode,
                                        isSelected: _selectedIds.contains(
                                          dayItems[i].transaction.id,
                                        ),
                                        onTap: () {
                                          final id = dayItems[i].transaction.id;
                                          if (selectionMode) {
                                            setState(() {
                                              if (_selectedIds.contains(id)) {
                                                _selectedIds.remove(id);
                                              } else {
                                                _selectedIds.add(id);
                                              }
                                            });
                                          } else {
                                            _showTransactionMenu(dayItems[i]);
                                          }
                                        },
                                        onLongPress: () {
                                          AppHaptics.selection(
                                            ref
                                                .read(settingsProvider)
                                                .hapticsEnabled,
                                          );
                                          setState(() {
                                            _selectedIds.add(
                                              dayItems[i].transaction.id,
                                            );
                                          });
                                        },
                                        onDelete: () => _deleteWithUndo([
                                          dayItems[i].transaction,
                                        ]),
                                        onDuplicate: () =>
                                            showTransactionFormSheet(
                                              context,
                                              duplicateFrom: dayItems[i],
                                            ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
