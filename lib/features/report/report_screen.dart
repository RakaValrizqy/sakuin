import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sakuin/core/constants/app_colors.dart';
import 'package:sakuin/core/db/app_database.dart';
import 'package:sakuin/core/db/db_provider.dart';
import 'package:sakuin/core/utils/currency_formatter.dart';
import 'package:sakuin/core/utils/date_utils.dart';
import 'package:sakuin/core/utils/spending_insights_calculator.dart';
import 'package:sakuin/core/widgets/amount_text.dart';
import 'package:sakuin/core/widgets/category_icon.dart';
import 'package:sakuin/features/budget/budget_providers.dart';
import 'package:sakuin/features/budget/budget_screen.dart';
import 'package:sakuin/features/report/export_service.dart';
import 'package:sakuin/features/report/report_providers.dart';
import 'package:sakuin/features/report/widgets/donut_chart.dart';
import 'package:sakuin/features/report/widgets/spending_heatmap_card.dart';
import 'package:sakuin/features/report/widgets/trend_chart.dart';
import 'package:sakuin/features/transaction/widgets/transaction_tile.dart';

class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({super.key});

  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  int? _selectedCategoryId;
  bool _exporting = false;

  Future<void> _pickCustomRange() async {
    final current = ref.read(activeReportPeriodProvider);
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(start: current.start, end: current.end),
    );
    if (range != null) {
      ref
          .read(reportPeriodSelectionProvider.notifier)
          .state = ReportPeriodSelection(
        preset: ReportPeriodPreset.custom,
        customStart: range.start,
        customEnd: range.end,
      );
    }
  }

  Future<void> _drillDownCategory(
    CategoryAggregate category,
    DatePeriod period,
    String type,
  ) async {
    setState(() => _selectedCategoryId = category.categoryId);
    final db = ref.read(appDatabaseProvider);
    final txs = await db.fetchTransactionsPage(
      limit: 100,
      startDayKey: period.startDayKey,
      endDayKey: period.endDayKey,
      type: type,
      categoryId: category.categoryId,
    );
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.65,
        maxChildSize: 0.9,
        builder: (ctx, scrollCtrl) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Row(
                children: [
                  CategoryIconBadge(
                    iconKey: category.icon,
                    colorValue: category.color,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          category.categoryName,
                          style: Theme.of(ctx).textTheme.titleLarge,
                        ),
                        Text(
                          '${category.count} transaksi • ${period.label}',
                          style: Theme.of(ctx).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  AmountText(
                    amount: category.total,
                    type: type,
                    style: Theme.of(ctx).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: txs.isEmpty
                  ? const Center(
                      child: Text(
                        'Termasuk biaya admin transfer (lihat daftar transaksi)',
                      ),
                    )
                  : ListView.separated(
                      controller: scrollCtrl,
                      itemCount: txs.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, idx) =>
                          TransactionTile(detail: txs[idx], enableSwipe: false),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _export(String format, ReportData data) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final service = ref.read(reportExportServiceProvider);
      if (format == 'csv') {
        await service.exportCsvAndShare(data.period);
      } else {
        await service.exportPdfAndShare(data);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal mengekspor: $e')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selection = ref.watch(reportPeriodSelectionProvider);
    final reportType = ref.watch(reportTypeProvider);
    final reportAsync = ref.watch(reportDataProvider);
    final insightsAsync = ref.watch(periodInsightsProvider);
    final budgetsAsync = ref.watch(budgetProgressListProvider);

    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Laporan'),
        actions: [
          if (reportAsync.valueOrNull != null)
            PopupMenuButton<String>(
              tooltip: 'Ekspor laporan',
              icon: _exporting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.ios_share_rounded),
              onSelected: (fmt) => _export(fmt, reportAsync.valueOrNull!),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'csv',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.table_chart_outlined),
                    title: Text('Ekspor CSV'),
                  ),
                ),
                PopupMenuItem(
                  value: 'pdf',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.picture_as_pdf_outlined),
                    title: Text('Ekspor PDF'),
                  ),
                ),
              ],
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 100),
        children: [
          // Preset Periode Cepat
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _PeriodChip(
                  label: 'Periode ini',
                  selected: selection.preset == ReportPeriodPreset.thisPeriod,
                  onTap: () =>
                      ref
                          .read(reportPeriodSelectionProvider.notifier)
                          .state = const ReportPeriodSelection(
                        preset: ReportPeriodPreset.thisPeriod,
                      ),
                ),
                const SizedBox(width: 8),
                _PeriodChip(
                  label: 'Periode lalu',
                  selected: selection.preset == ReportPeriodPreset.lastPeriod,
                  onTap: () =>
                      ref
                          .read(reportPeriodSelectionProvider.notifier)
                          .state = const ReportPeriodSelection(
                        preset: ReportPeriodPreset.lastPeriod,
                      ),
                ),
                const SizedBox(width: 8),
                _PeriodChip(
                  label: '7 Hari',
                  selected: selection.preset == ReportPeriodPreset.last7Days,
                  onTap: () =>
                      ref
                          .read(reportPeriodSelectionProvider.notifier)
                          .state = const ReportPeriodSelection(
                        preset: ReportPeriodPreset.last7Days,
                      ),
                ),
                const SizedBox(width: 8),
                _PeriodChip(
                  label: '30 Hari',
                  selected: selection.preset == ReportPeriodPreset.last30Days,
                  onTap: () =>
                      ref
                          .read(reportPeriodSelectionProvider.notifier)
                          .state = const ReportPeriodSelection(
                        preset: ReportPeriodPreset.last30Days,
                      ),
                ),
                const SizedBox(width: 8),
                _PeriodChip(
                  label: 'Tahun ini',
                  selected: selection.preset == ReportPeriodPreset.thisYear,
                  onTap: () =>
                      ref
                          .read(reportPeriodSelectionProvider.notifier)
                          .state = const ReportPeriodSelection(
                        preset: ReportPeriodPreset.thisYear,
                      ),
                ),
                const SizedBox(width: 8),
                _PeriodChip(
                  label: 'Kustom',
                  selected: selection.preset == ReportPeriodPreset.custom,
                  onTap: _pickCustomRange,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          reportAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Center(child: Text('Gagal memuat laporan: $e')),
            data: (data) {
              final expChange = data.percentChange(
                data.summary.expense,
                data.previousSummary.expense,
              );
              final incChange = data.percentChange(
                data.summary.income,
                data.previousSummary.income,
              );
              final chartTotal = reportType == 'expense'
                  ? data.summary.expense
                  : data.summary.income;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Ringkasan Periode + Perbandingan
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(data.period.label, style: tt.titleMedium),
                              Text(
                                '${data.period.totalDays} hari',
                                style: tt.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: _MetricColumn(
                                  label: 'Pemasukan',
                                  amount: data.summary.income,
                                  type: 'income',
                                  deltaPercent: incChange,
                                  lowerIsBetter: false,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _MetricColumn(
                                  label: 'Pengeluaran',
                                  amount: data.summary.expense,
                                  type: 'expense',
                                  deltaPercent: expChange,
                                  lowerIsBetter: true,
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 22),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Selisih Arus Kas',
                                    style: tt.bodySmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                  AmountText(
                                    amount: data.summary.net,
                                    type: data.summary.net >= 0
                                        ? 'income'
                                        : 'expense',
                                    signed: true,
                                    style: tt.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    'Rata-rata Pengeluaran / Hari',
                                    style: tt.bodySmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                  AmountText(
                                    amount: data.dailyAverageExpense,
                                    style: tt.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Grafik Donut per Kategori
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Per Kategori', style: tt.titleMedium),
                              SegmentedButton<String>(
                                showSelectedIcon: false,
                                style: const ButtonStyle(
                                  visualDensity: VisualDensity.compact,
                                ),
                                segments: const [
                                  ButtonSegment(
                                    value: 'expense',
                                    label: Text('Keluar'),
                                  ),
                                  ButtonSegment(
                                    value: 'income',
                                    label: Text('Masuk'),
                                  ),
                                ],
                                selected: {reportType},
                                onSelectionChanged: (s) {
                                  setState(() => _selectedCategoryId = null);
                                  ref.read(reportTypeProvider.notifier).state =
                                      s.first;
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Center(
                            child: CategoryDonutChart(
                              items: data.categories,
                              total: chartTotal,
                              centerLabel: reportType == 'expense'
                                  ? 'Pengeluaran'
                                  : 'Pemasukan',
                              selectedCategoryId: _selectedCategoryId,
                              onSliceTap: (cat) => _drillDownCategory(
                                cat,
                                data.period,
                                reportType,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (data.categories.isEmpty)
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Text(
                                  'Belum ada transaksi pada periode ini',
                                  style: tt.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            )
                          else ...[
                            Center(
                              child: Text(
                                'Ketuk grafik atau kategori untuk melihat rincian transaksi',
                                style: tt.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            for (final cat in data.categories)
                              _CategoryBarRow(
                                item: cat,
                                total: chartTotal,
                                type: reportType,
                                onTap: () => _drillDownCategory(
                                  cat,
                                  data.period,
                                  reportType,
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Grafik Tren Harian
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Tren Harian', style: tt.titleMedium),
                          const SizedBox(height: 12),
                          PeriodTrendChart(points: data.trend),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Insight & Perbandingan Periode Otomatis
                  if (insightsAsync.valueOrNull != null) ...[
                    _PeriodInsightsCard(insights: insightsAsync.valueOrNull!),
                    const SizedBox(height: 16),
                  ],

                  // Kalender Pengeluaran Interaktif (Spending Heatmap)
                  const SpendingHeatmapCard(),
                  const SizedBox(height: 16),

                  // Ringkasan Anggaran
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Anggaran Periode Ini', style: tt.titleMedium),
                      TextButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const BudgetScreen(),
                          ),
                        ),
                        child: const Text('Kelola'),
                      ),
                    ],
                  ),
                  budgetsAsync.when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, _) => const SizedBox.shrink(),
                    data: (budgets) {
                      if (budgets.isEmpty) {
                        return Card(
                          child: ListTile(
                            leading: const Icon(
                              Icons.pie_chart_outline_rounded,
                            ),
                            title: const Text('Belum ada anggaran bulanan'),
                            subtitle: const Text(
                              'Atur batas pengeluaran agar dapat peringatan 80% & 100%',
                            ),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const BudgetScreen(),
                              ),
                            ),
                          ),
                        );
                      }
                      return Column(
                        children: [
                          for (final b in budgets.take(3))
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: BudgetProgressCard(item: b),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PeriodInsightsCard extends StatelessWidget {
  const _PeriodInsightsCard({required this.insights});

  final PeriodInsights insights;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_graph_rounded, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                Text('Insight Periode', style: tt.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _InsightStatBox(
                    icon: Icons.eco_outlined,
                    iconColor: AppColors.income(context),
                    label: 'No-Spend Day',
                    value: '${insights.noSpendDays} hari',
                    sub: 'dari ${insights.elapsedDays} hari berjalan',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _InsightStatBox(
                    icon: Icons.trending_up_rounded,
                    iconColor: cs.primary,
                    label: 'Proyeksi Akhir Periode',
                    value: CurrencyFormatter.formatCompact(
                      insights.projectedExpense,
                    ),
                    sub: 'estimasi ${insights.totalDays} hari',
                  ),
                ),
              ],
            ),
            if (insights.busiestWeekdayName != null ||
                insights.topItemName != null ||
                insights.topRisingCategory != null ||
                insights.topFallingCategory != null) ...[
              const Divider(height: 22),
              if (insights.busiestWeekdayName != null)
                _InsightBullet(
                  icon: Icons.calendar_view_week_outlined,
                  text:
                      'Hari paling boros: ${insights.busiestWeekdayName} (rata-rata ${CurrencyFormatter.format(insights.busiestWeekdayAverage)}/hari)',
                ),
              if (insights.topItemName != null)
                _InsightBullet(
                  icon: Icons.repeat_rounded,
                  text:
                      'Item tersering: ${insights.topItemName} (${insights.topItemCount}x • total ${CurrencyFormatter.format(insights.topItemTotal)})',
                ),
              if (insights.topRisingCategory != null)
                _InsightBullet(
                  icon: Icons.arrow_upward_rounded,
                  iconColor: AppColors.expense(context),
                  text:
                      'Paling naik vs periode lalu: ${insights.topRisingCategory!.categoryName} (+${CurrencyFormatter.format(insights.topRisingCategory!.deltaAmount)}${insights.topRisingCategory!.deltaPercent != null ? ' / +${insights.topRisingCategory!.deltaPercent!.round()}%' : ''})',
                ),
              if (insights.topFallingCategory != null)
                _InsightBullet(
                  icon: Icons.arrow_downward_rounded,
                  iconColor: AppColors.income(context),
                  text:
                      'Paling hemat vs periode lalu: ${insights.topFallingCategory!.categoryName} (-${CurrencyFormatter.format(insights.topFallingCategory!.deltaAmount.abs())}${insights.topFallingCategory!.deltaPercent != null ? ' / ${insights.topFallingCategory!.deltaPercent!.round()}%' : ''})',
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InsightStatBox extends StatelessWidget {
  const _InsightStatBox({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.sub,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final String sub;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: iconColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          Text(sub, style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _InsightBullet extends StatelessWidget {
  const _InsightBullet({
    required this.icon,
    required this.text,
    this.iconColor,
  });

  final IconData icon;
  final String text;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: iconColor ?? cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

class _PeriodChip extends StatelessWidget {
  const _PeriodChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }
}

class _MetricColumn extends StatelessWidget {
  const _MetricColumn({
    required this.label,
    required this.amount,
    required this.type,
    required this.deltaPercent,
    required this.lowerIsBetter,
  });

  final String label;
  final int amount;
  final String type;
  final double? deltaPercent;
  final bool lowerIsBetter;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    String? deltaText;
    Color? deltaColor;
    if (deltaPercent != null) {
      final sign = deltaPercent! > 0 ? '+' : '';
      deltaText = '$sign${deltaPercent!.toStringAsFixed(0)}% vs lalu';
      final isGood = lowerIsBetter ? deltaPercent! <= 0 : deltaPercent! >= 0;
      deltaColor = isGood
          ? AppColors.income(context)
          : AppColors.expense(context);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        const SizedBox(height: 2),
        AmountText(
          amount: amount,
          type: type,
          style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        if (deltaText != null)
          Text(deltaText, style: tt.labelSmall?.copyWith(color: deltaColor)),
      ],
    );
  }
}

class _CategoryBarRow extends StatelessWidget {
  const _CategoryBarRow({
    required this.item,
    required this.total,
    required this.type,
    required this.onTap,
  });

  final CategoryAggregate item;
  final int total;
  final String type;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ratio = total <= 0 ? 0.0 : (item.total / total).clamp(0.0, 1.0);
    final pct = (ratio * 100).toStringAsFixed(1);
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            CategoryIconBadge(
              iconKey: item.icon,
              colorValue: item.color,
              size: 38,
              iconSize: 18,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          item.categoryName,
                          style: tt.titleSmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${CurrencyFormatter.format(item.total)} ($pct%)',
                        style: tt.labelLarge?.copyWith(
                          color: type == 'expense'
                              ? AppColors.expense(context)
                              : AppColors.income(context),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: ratio,
                      minHeight: 6,
                      color: Color(item.color),
                      backgroundColor: cs.surfaceContainerHighest,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
