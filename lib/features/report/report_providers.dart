import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sakuin/core/db/app_database.dart';
import 'package:sakuin/core/db/db_provider.dart';
import 'package:sakuin/core/services/settings_service.dart';
import 'package:sakuin/core/utils/date_utils.dart';
import 'package:sakuin/features/transaction/transaction_providers.dart';

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
