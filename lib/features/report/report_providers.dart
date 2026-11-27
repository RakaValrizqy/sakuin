import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sakuin/core/db/app_database.dart';
import 'package:sakuin/core/db/db_provider.dart';
import 'package:sakuin/core/services/settings_service.dart';
import 'package:sakuin/core/utils/date_utils.dart';
import 'package:sakuin/core/utils/spending_insights_calculator.dart';
import 'package:sakuin/features/transaction/transaction_providers.dart';
import 'package:sakuin/features/wallet/wallet_providers.dart';

class ReportPeriodSelection {
  const ReportPeriodSelection({
    this.preset = ReportPeriodPreset.thisPeriod,
    this.customStart,
    this.customEnd,
  });

  final ReportPeriodPreset preset;
  final DateTime? customStart;
  final DateTime? customEnd;
}

final reportPeriodSelectionProvider = StateProvider<ReportPeriodSelection>(
  (ref) => const ReportPeriodSelection(),
);

final reportTypeProvider = StateProvider<String>((ref) => 'expense');

final activeReportPeriodProvider = Provider<DatePeriod>((ref) {
  final startDay = ref.watch(settingsProvider.select((s) => s.periodStartDay));
  final sel = ref.watch(reportPeriodSelectionProvider);
  return AppDateUtils.periodForPreset(
    sel.preset,
    startDay,
    customStart: sel.customStart,
    customEnd: sel.customEnd,
  );
});

class ReportData {
  const ReportData({
    required this.period,
    required this.previousPeriod,
    required this.summary,
    required this.previousSummary,
    required this.categories,
    required this.trend,
  });

  final DatePeriod period;
  final DatePeriod previousPeriod;
  final PeriodSummary summary;
  final PeriodSummary previousSummary;
  final List<CategoryAggregate> categories;
  final List<DailyTrendPoint> trend;

  int get dailyAverageExpense {
    final days = period.totalDays <= 0 ? 1 : period.totalDays;
    return summary.expense ~/ days;
  }

  /// Perubahan persentase dibanding periode sebelumnya (null jika periode lalu 0).
  double? percentChange(int current, int previous) {
    if (previous == 0) return current == 0 ? 0 : null;
    return ((current - previous) / previous) * 100;
  }
}

final reportDataProvider = FutureProvider<ReportData>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  final startDay = ref.watch(settingsProvider.select((s) => s.periodStartDay));
  final sel = ref.watch(reportPeriodSelectionProvider);
  final period = ref.watch(activeReportPeriodProvider);
  final type = ref.watch(reportTypeProvider);
  ref.watch(transactionRevisionProvider);

  final isMonthly =
      sel.preset == ReportPeriodPreset.thisPeriod ||
      sel.preset == ReportPeriodPreset.lastPeriod;
  final prevPeriod = AppDateUtils.previousPeriod(
    period,
    startDay,
    isMonthlyCycle: isMonthly,
  );

  final summary = await db.getPeriodSummary(
    period.startDayKey,
    period.endDayKey,
  );
  final prevSummary = await db.getPeriodSummary(
    prevPeriod.startDayKey,
    prevPeriod.endDayKey,
  );
  final categories = await db.getCategoryBreakdown(
    startDayKey: period.startDayKey,
    endDayKey: period.endDayKey,
    type: type,
  );
  final trend = await db.getDailyTrend(
    startDayKey: period.startDayKey,
    endDayKey: period.endDayKey,
  );

  return ReportData(
    period: period,
    previousPeriod: prevPeriod,
    summary: summary,
    previousSummary: prevSummary,
    categories: categories,
    trend: trend,
  );
});

final periodInsightsProvider = FutureProvider<PeriodInsights>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  final startDay = ref.watch(settingsProvider.select((s) => s.periodStartDay));
  final sel = ref.watch(reportPeriodSelectionProvider);
  final period = ref.watch(activeReportPeriodProvider);
  ref.watch(transactionRevisionProvider);

  final isMonthly =
      sel.preset == ReportPeriodPreset.thisPeriod ||
      sel.preset == ReportPeriodPreset.lastPeriod;
  final prevPeriod = AppDateUtils.previousPeriod(
    period,
    startDay,
    isMonthlyCycle: isMonthly,
  );

  final trend = await db.getDailyTrend(
    startDayKey: period.startDayKey,
    endDayKey: period.endDayKey,
  );
  final currentExpenseCats = await db.getCategoryBreakdown(
    startDayKey: period.startDayKey,
    endDayKey: period.endDayKey,
    type: 'expense',
  );
  final prevExpenseCats = await db.getCategoryBreakdown(
    startDayKey: prevPeriod.startDayKey,
    endDayKey: prevPeriod.endDayKey,
    type: 'expense',
  );
  final currentTxs = await db.fetchTransactionsPage(
    limit: 500,
    startDayKey: period.startDayKey,
    endDayKey: period.endDayKey,
    type: 'expense',
  );

  return SpendingInsightsCalculator.computePeriodInsights(
    now: DateTime.now(),
    period: period,
    trend: trend,
    currentTransactions: currentTxs,
    currentExpenseCategories: currentExpenseCats,
    previousExpenseCategories: prevExpenseCats,
  );
});

class PocketReportSummary {
  const PocketReportSummary({
    required this.group,
    required this.spentInPeriod,
    required this.txCount,
    required this.targetAmount,
  });

  final GroupedPocketSummary group;
  final int spentInPeriod;
  final int txCount;
  final int targetAmount;

  double get usedRatio {
    final totalAvailable = group.totalBalance + spentInPeriod;
    if (totalAvailable <= 0) return spentInPeriod > 0 ? 1.0 : 0.0;
    return (spentInPeriod / totalAvailable).clamp(0.0, 1.0);
  }
}

final pocketReportProvider = FutureProvider<List<PocketReportSummary>>((
  ref,
) async {
  final db = ref.watch(appDatabaseProvider);
  final period = ref.watch(activeReportPeriodProvider);
  final allPockets =
      ref.watch(allActivePocketsProvider).valueOrNull ?? const [];
  ref.watch(transactionRevisionProvider);

  if (allPockets.isEmpty) return const [];
  final grouped = SpendingInsightsCalculator.groupPocketsByName(allPockets);
  final targetByKey = <String, int>{};
  for (final p in allPockets) {
    final key = SpendingInsightsCalculator.normalizePocketGroupKey(
      p.pocket.name,
    );
    targetByKey[key] = (targetByKey[key] ?? 0) + (p.pocket.targetAmount ?? 0);
  }

  final periodTxs = await db.fetchTransactionsPage(
    limit: 1000,
    startDayKey: period.startDayKey,
    endDayKey: period.endDayKey,
  );

  final list = <PocketReportSummary>[];
  for (final g in grouped) {
    var spent = 0;
    var cnt = 0;
    for (final d in periodTxs) {
      final tx = d.transaction;
      if (tx.pocketId == null || !g.pocketIds.contains(tx.pocketId)) continue;
      if (tx.type == 'expense') {
        spent += tx.amount;
        cnt++;
      } else if (tx.type == 'transfer' && tx.fee > 0) {
        spent += tx.fee;
      }
    }
    list.add(
      PocketReportSummary(
        group: g,
        spentInPeriod: spent,
        txCount: cnt,
        targetAmount: targetByKey[g.normalizedKey] ?? 0,
      ),
    );
  }
  list.sort((a, b) => b.spentInPeriod.compareTo(a.spentInPeriod));
  return list;
});

class MonthlyGrowthPoint {
  const MonthlyGrowthPoint({
    required this.label,
    required this.income,
    required this.expense,
    required this.net,
    required this.estimatedEndingBalance,
  });

  final String label;
  final int income;
  final int expense;
  final int net;
  final int estimatedEndingBalance;
}

final savingsGrowthProvider = FutureProvider<List<MonthlyGrowthPoint>>((
  ref,
) async {
  final db = ref.watch(appDatabaseProvider);
  final startDay = ref.watch(settingsProvider.select((s) => s.periodStartDay));
  final currentTotalBalance = ref.watch(totalBalanceProvider);
  ref.watch(transactionRevisionProvider);

  // Kumpulkan 6 periode bulanan terakhir (dari terbaru ke terlama, lalu dibalik)
  final periods = <DatePeriod>[];
  var cursor = AppDateUtils.periodForDate(DateTime.now(), startDay);
  periods.add(cursor);
  for (var i = 1; i < 6; i++) {
    cursor = AppDateUtils.previousPeriod(
      cursor,
      startDay,
      isMonthlyCycle: true,
    );
    periods.add(cursor);
  }

  final summaries = <PeriodSummary>[];
  for (final p in periods) {
    summaries.add(await db.getPeriodSummary(p.startDayKey, p.endDayKey));
  }

  // Hitung mundur perkiraan saldo akhir tiap bulan dari total saldo saat ini
  final pointsReversed = <MonthlyGrowthPoint>[];
  var runningBalance = currentTotalBalance;
  for (var i = 0; i < periods.length; i++) {
    final s = summaries[i];
    final shortLabel = periods[i].label.split(' ').first;
    pointsReversed.add(
      MonthlyGrowthPoint(
        label: shortLabel.length > 3 ? shortLabel.substring(0, 3) : shortLabel,
        income: s.income,
        expense: s.expense,
        net: s.net,
        estimatedEndingBalance: runningBalance,
      ),
    );
    runningBalance -= s.net;
  }

  return pointsReversed.reversed.toList();
});
