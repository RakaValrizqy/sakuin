import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sakuin/core/db/app_database.dart';
import 'package:sakuin/core/db/db_provider.dart';
import 'package:sakuin/core/services/settings_service.dart';
import 'package:sakuin/core/utils/date_utils.dart';
import 'package:sakuin/features/transaction/transaction_providers.dart';

class BudgetProgress {
  const BudgetProgress({
    required this.budget,
    required this.label,
    required this.icon,
    required this.color,
    required this.spent,
    required this.remainingDays,
  });

  final Budget budget;
  final String label;
  final String icon;
  final int color;
  final int spent;
  final int remainingDays;

  int get remaining => budget.amount - spent;
  double get ratio => budget.amount <= 0 ? 0 : (spent / budget.amount);
  int get percent => (ratio * 100).round();
  bool get isWarning => ratio >= 0.8 && ratio < 1.0;
  bool get isExceeded => ratio >= 1.0;

  /// Sisa anggaran per hari yang aman dibelanjakan.
  int get safeDailySpend {
    if (remaining <= 0) return 0;
    final days = remainingDays <= 0 ? 1 : remainingDays;
    return remaining ~/ days;
  }
}

final budgetProgressListProvider = FutureProvider<List<BudgetProgress>>((
  ref,
) async {
  final db = ref.watch(appDatabaseProvider);
  final startDay = ref.watch(settingsProvider.select((s) => s.periodStartDay));
  ref.watch(transactionRevisionProvider);
  ref.watch(budgetsRevisionProvider);

  final now = DateTime.now();
  final period = AppDateUtils.periodForDate(now, startDay);
  final remainingDays = period.remainingDaysFrom(now);

  final budgets = await db.select(db.budgets).get();
  final cats = await db.select(db.categories).get();
  final catMap = {for (final c in cats) c.id: c};

  final result = <BudgetProgress>[];
  for (final b in budgets) {
    final spent = await db.getCategorySpentInPeriod(
      categoryId: b.categoryId,
      startDayKey: period.startDayKey,
      endDayKey: period.endDayKey,
    );
    final cat = b.categoryId == null ? null : catMap[b.categoryId];
    result.add(
      BudgetProgress(
        budget: b,
        label: cat?.name ?? 'Total Pengeluaran Bulanan',
        icon: cat?.icon ?? 'wallet',
        color: cat?.color ?? 0xFF0F766E,
        spent: spent,
        remainingDays: remainingDays,
      ),
    );
  }

  // Letakkan total budget (categoryId == null) di urutan paling atas
  result.sort((a, b) {
    if (a.budget.categoryId == null && b.budget.categoryId != null) return -1;
    if (a.budget.categoryId != null && b.budget.categoryId == null) return 1;
    return b.ratio.compareTo(a.ratio);
  });
  return result;
});

final budgetsRevisionProvider = StateProvider<int>((ref) => 0);

final budgetActionsProvider = Provider<BudgetActions>((ref) {
  return BudgetActions(ref);
});

class BudgetActions {
  BudgetActions(this._ref);

  final Ref _ref;
  AppDatabase get _db => _ref.read(appDatabaseProvider);

  Future<void> saveBudget({
    int? existingId,
    required int? categoryId,
    required int amount,
  }) async {
    if (existingId != null) {
      await (_db.update(
        _db.budgets,
      )..where((b) => b.id.equals(existingId))).write(
        BudgetsCompanion(categoryId: Value(categoryId), amount: Value(amount)),
      );
    } else {
      // Cegah duplikat budget untuk kategori yang sama
      final existing = categoryId == null
          ? await (_db.select(
              _db.budgets,
            )..where((b) => b.categoryId.isNull())).getSingleOrNull()
          : await (_db.select(
              _db.budgets,
            )..where((b) => b.categoryId.equals(categoryId))).getSingleOrNull();
      if (existing != null) {
        await (_db.update(_db.budgets)..where((b) => b.id.equals(existing.id)))
            .write(BudgetsCompanion(amount: Value(amount)));
      } else {
        await _db
            .into(_db.budgets)
            .insert(
              BudgetsCompanion.insert(
                categoryId: Value(categoryId),
                amount: amount,
              ),
            );
      }
    }
    _ref.read(budgetsRevisionProvider.notifier).state++;
  }

  Future<void> deleteBudget(int id) async {
    await (_db.delete(_db.budgets)..where((b) => b.id.equals(id))).go();
    _ref.read(budgetsRevisionProvider.notifier).state++;
  }
}
