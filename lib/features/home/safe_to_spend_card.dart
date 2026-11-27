import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sakuin/core/constants/app_colors.dart';
import 'package:sakuin/core/db/app_database.dart';
import 'package:sakuin/core/db/db_provider.dart';
import 'package:sakuin/core/services/settings_service.dart';
import 'package:sakuin/core/utils/currency_formatter.dart';
import 'package:sakuin/core/utils/date_utils.dart';
import 'package:sakuin/core/utils/spending_insights_calculator.dart';
import 'package:sakuin/features/budget/budget_providers.dart';
import 'package:sakuin/features/transaction/transaction_providers.dart';
import 'package:sakuin/features/wallet/wallet_providers.dart';

final safeToSpendConfigProvider =
    StateNotifierProvider<SafeToSpendConfigNotifier, SafeToSpendConfig>(
      (ref) => SafeToSpendConfigNotifier(),
    );

class SafeToSpendConfigNotifier extends StateNotifier<SafeToSpendConfig> {
  SafeToSpendConfigNotifier() : super(const SafeToSpendConfig()) {
    _load();
  }

  Future<void> _load() async {
    state = await SpendingInsightsCalculator.loadSafeToSpendConfig();
  }

  Future<void> update(SafeToSpendConfig config) async {
    state = config;
    await SpendingInsightsCalculator.saveSafeToSpendConfig(config);
  }
}

final todayExpenseProvider = StreamProvider<int>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final todayKey = AppDateUtils.toDayKey(DateTime.now());
  return db
      .watchPeriodSummary(todayKey, todayKey)
      .map((summary) => summary.expense);
});

class SafeToSpendCard extends ConsumerWidget {
  const SafeToSpendCard({super.key});

  Future<void> _openConfigSheet(
    BuildContext context,
    WidgetRef ref,
    List<PocketWithBalance> allPockets,
  ) async {
    final current = ref.read(safeToSpendConfigProvider);
    final grouped = SpendingInsightsCalculator.groupPocketsByName(allPockets);
    var mode = current.mode;

    // Migrasi otomatis pilihan ID lama ke kunci nama pos gabungan
    final selectedNames = Set<String>.from(current.selectedPocketNames);
    if (selectedNames.isEmpty && current.selectedPocketIds.isNotEmpty) {
      for (final g in grouped) {
        if (g.pocketIds.any(current.selectedPocketIds.contains)) {
          selectedNames.add(g.normalizedKey);
        }
      }
    }

    final saved = await showModalBottomSheet<SafeToSpendConfig>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final tt = Theme.of(ctx).textTheme;
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Sumber Batas Aman Harian', style: tt.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                    'Pilih sumber dana yang dibagi rata ke sisa hari periode ini.',
                    style: tt.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  _ModeOptionTile(
                    selected: mode == SafeToSpendMode.auto,
                    title: 'Otomatis (Direkomendasikan)',
                    subtitle: 'Pakai sisa Anggaran Bulanan jika ada, atau Pos Harian, atau Total Saldo',
                    onTap: () =>
                        setModalState(() => mode = SafeToSpendMode.auto),
                  ),
                  _ModeOptionTile(
                    selected: mode == SafeToSpendMode.budgets,
                    title: 'Dari Sisa Anggaran Bulanan',
                    subtitle:
                        'Menghitung total sisa batas anggaran periode ini',
                    onTap: () =>
                        setModalState(() => mode = SafeToSpendMode.budgets),
                  ),
                  if (grouped.isNotEmpty)
                    _ModeOptionTile(
                      selected: mode == SafeToSpendMode.pockets,
                      title: 'Dari Pos Budget Pilihan',
                      subtitle: 'Pos bernama sama lintas saku otomatis digabung jadi 1 pilihan',
                      onTap: () =>
                          setModalState(() => mode = SafeToSpendMode.pockets),
                    ),
                  _ModeOptionTile(
                    selected: mode == SafeToSpendMode.totalBalance,
                    title: 'Dari Total Saldo Aktif',
                    subtitle: 'Seluruh saldo dompet yang termasuk total saldo',
                    onTap: () => setModalState(
                      () => mode = SafeToSpendMode.totalBalance,
                    ),
                  ),
                  if (mode == SafeToSpendMode.pockets &&
                      grouped.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Pilih Pos Budget (Gabungan Semua Saku):',
                      style: tt.labelMedium,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        for (final g in grouped)
                          FilterChip(
                            label: Text(
                              g.walletCount > 1
                                  ? '${g.displayName} (${CurrencyFormatter.formatCompact(g.totalBalance)} • ${g.walletCount} saku)'
                                  : '${g.displayName} (${CurrencyFormatter.formatCompact(g.totalBalance)})',
                            ),
                            selected: selectedNames.contains(g.normalizedKey),
                            onSelected: (sel) {
                              setModalState(() {
                                if (sel) {
                                  selectedNames.add(g.normalizedKey);
                                } else {
                                  selectedNames.remove(g.normalizedKey);
                                }
                              });
                            },
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        final matchedIds = <int>{};
                        for (final g in grouped) {
                          if (selectedNames.contains(g.normalizedKey)) {
                            matchedIds.addAll(g.pocketIds);
                          }
                        }
                        Navigator.pop(
                          ctx,
                          SafeToSpendConfig(
                            mode: mode,
                            selectedPocketIds: matchedIds,
                            selectedPocketNames: selectedNames,
                          ),
                        );
                      },
                      child: const Text('Simpan Sumber'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (saved != null) {
      await ref.read(safeToSpendConfigProvider.notifier).update(saved);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(safeToSpendConfigProvider);
    final totalBalance = ref.watch(totalBalanceProvider);
    final allPockets =
        ref.watch(allActivePocketsProvider).valueOrNull ?? const [];
    final budgets =
        ref.watch(budgetProgressListProvider).valueOrNull ?? const [];
    final spentToday = ref.watch(todayExpenseProvider).valueOrNull ?? 0;
    final hideBalances = ref.watch(
      settingsProvider.select((s) => s.hideBalances),
    );
    final startDay = ref.watch(
      settingsProvider.select((s) => s.periodStartDay),
    );
    // Pastikan rebuild saat transaksi berubah
    ref.watch(transactionRevisionProvider);

    final now = DateTime.now();
    final period = AppDateUtils.periodForDate(now, startDay);

    final globalBudget = budgets
        .where((b) => b.budget.categoryId == null)
        .firstOrNull;
    final totalBudgetRemaining = globalBudget != null
        ? (globalBudget.remaining < 0 ? 0 : globalBudget.remaining)
        : budgets.fold<int>(
            0,
            (sum, b) => sum + (b.remaining < 0 ? 0 : b.remaining),
          );
    final hasBudgets = budgets.isNotEmpty;

    int poolAmount;
    String sourceLabel;

    final effectiveMode = config.mode == SafeToSpendMode.auto
        ? (hasBudgets
              ? SafeToSpendMode.budgets
              : (allPockets.isNotEmpty
                    ? SafeToSpendMode.pockets
                    : SafeToSpendMode.totalBalance))
        : config.mode;

    switch (effectiveMode) {
      case SafeToSpendMode.budgets:
        poolAmount = totalBudgetRemaining;
        sourceLabel = hasBudgets
            ? 'Sisa Anggaran (${budgets.length} kategori)'
            : 'Belum ada anggaran';
      case SafeToSpendMode.pockets:
        final grouped = SpendingInsightsCalculator.groupPocketsByName(
          allPockets,
        );
        List<GroupedPocketSummary> chosenGroups;
        if (config.selectedPocketNames.isNotEmpty) {
          chosenGroups = grouped
              .where(
                (g) => config.selectedPocketNames.contains(g.normalizedKey),
              )
              .toList();
        } else if (config.selectedPocketIds.isNotEmpty) {
          chosenGroups = grouped
              .where((g) => g.pocketIds.any(config.selectedPocketIds.contains))
              .toList();
        } else {
          // Otomatis cari pos bernama Harian/Jajan/Makan; jika tak ada, gunakan semua pos
          final dailyLike = grouped.where((g) {
            final n = g.displayName.toLowerCase();
            return n.contains('harian') ||
                n.contains('jajan') ||
                n.contains('makan') ||
                n.contains('daily');
          }).toList();
          chosenGroups = dailyLike.isNotEmpty ? dailyLike : grouped;
        }
        poolAmount = chosenGroups.fold<int>(0, (s, g) => s + g.totalBalance);
        sourceLabel = chosenGroups.length == 1
            ? (chosenGroups.first.walletCount > 1
                  ? 'Pos ${chosenGroups.first.displayName} (${chosenGroups.first.walletCount} saku)'
                  : 'Pos ${chosenGroups.first.displayName}')
            : 'Pos Budget (${chosenGroups.length} pos)';
      case SafeToSpendMode.totalBalance:
      case SafeToSpendMode.auto:
        poolAmount = totalBalance;
        sourceLabel = 'Total Saldo Aktif';
    }

    final result = SpendingInsightsCalculator.calculateSafeToSpend(
      now: now,
      period: period,
      remainingPool: poolAmount,
      spentToday: spentToday,
      sourceLabel: sourceLabel,
    );

    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final statusColor = result.isOverDailyLimit
        ? AppColors.expense(context)
        : (result.todayRatio >= 0.8
              ? AppColors.warning(context)
              : AppColors.income(context));

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _openConfigSheet(context, ref, allPockets),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.shield_outlined, size: 18, color: statusColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Aman Dipakai Hari Ini',
                      style: tt.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    '${result.daysRemaining} hari lagi',
                    style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.tune_rounded,
                    size: 16,
                    color: cs.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    hideBalances
                        ? CurrencyFormatter.masked
                        : (result.isOverDailyLimit
                              ? 'Lewat ${CurrencyFormatter.format(result.remainingToday.abs())}'
                              : CurrencyFormatter.format(
                                  result.remainingToday,
                                )),
                    style: tt.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: statusColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      hideBalances
                          ? ''
                          : 'dari jatah ${CurrencyFormatter.formatCompact(result.dailyAllowance)}/hari',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: result.todayRatio.clamp(0.0, 1.0),
                  minHeight: 7,
                  color: statusColor,
                  backgroundColor: cs.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Sumber: ${result.sourceLabel}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                  Text(
                    hideBalances
                        ? ''
                        : 'Terpakai ${CurrencyFormatter.formatCompact(result.spentToday)}',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeOptionTile extends StatelessWidget {
  const _ModeOptionTile({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        selected
            ? Icons.radio_button_checked_rounded
            : Icons.radio_button_off_rounded,
        color: selected ? cs.primary : cs.onSurfaceVariant,
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      onTap: onTap,
    );
  }
}
