import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:sakuin/core/constants/app_colors.dart';
import 'package:sakuin/core/db/app_database.dart';
import 'package:sakuin/core/db/db_provider.dart';
import 'package:sakuin/core/utils/currency_formatter.dart';
import 'package:sakuin/core/utils/date_utils.dart';
import 'package:sakuin/core/utils/spending_insights_calculator.dart';
import 'package:sakuin/features/transaction/transaction_providers.dart';
import 'package:sakuin/features/transaction/widgets/transaction_tile.dart';

class SpendingHeatmapCard extends ConsumerStatefulWidget {
  const SpendingHeatmapCard({super.key});

  @override
  ConsumerState<SpendingHeatmapCard> createState() =>
      _SpendingHeatmapCardState();
}

class _SpendingHeatmapCardState extends ConsumerState<SpendingHeatmapCard> {
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month, 1);
  }

  void _shiftMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta, 1);
    });
  }

  Future<void> _showDayTransactions(DateTime date, int dayKey) async {
    final db = ref.read(appDatabaseProvider);
    final txs = await db.fetchTransactionsPage(
      limit: 100,
      startDayKey: dayKey,
      endDayKey: dayKey,
    );
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        maxChildSize: 0.85,
        builder: (ctx, scrollCtrl) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    AppDateUtils.formatDayDate(date),
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                  Text(
                    '${txs.length} transaksi',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: txs.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.eco_rounded,
                              size: 36,
                              color: AppColors.income(ctx),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'No-Spend Day! Tidak ada transaksi di hari ini.',
                              style: Theme.of(ctx).textTheme.bodyMedium,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      controller: scrollCtrl,
                      itemCount: txs.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) =>
                          TransactionTile(detail: txs[i], enableSwipe: false),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(appDatabaseProvider);
    ref.watch(transactionRevisionProvider);

    final startDayKey = AppDateUtils.toDayKey(_month);
    final lastDayOfMonth = DateTime(_month.year, _month.month + 1, 0);
    final endDayKey = AppDateUtils.toDayKey(lastDayOfMonth);
    final monthLabel = DateFormat('MMMM yyyy', 'id_ID').format(_month);

    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<List<DailyTrendPoint>>(
          future: db.getDailyTrend(
            startDayKey: startDayKey,
            endDayKey: endDayKey,
          ),
          builder: (context, snap) {
            final points = snap.data ?? const <DailyTrendPoint>[];
            final expenseByDay = {for (final p in points) p.dayKey: p.expense};

            var activeDays = 0;
            var sumActive = 0;
            for (final p in points) {
              if (p.expense > 0) {
                activeDays++;
                sumActive += p.expense;
              }
            }
            final avgActive = activeDays > 0 ? sumActive ~/ activeDays : 0;

            final leadingEmpty = _month.weekday - 1; // Senin = 0
            final totalDays = lastDayOfMonth.day;
            final cellCount = leadingEmpty + totalDays;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Kalender Pengeluaran', style: tt.titleMedium),
                          Text(
                            'Ketuk tanggal untuk melihat transaksi hari itu',
                            style: tt.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Bulan sebelumnya',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.chevron_left_rounded),
                      onPressed: () => _shiftMonth(-1),
                    ),
                    Text(
                      monthLabel,
                      style: tt.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Bulan berikutnya',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.chevron_right_rounded),
                      onPressed: () => _shiftMonth(1),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    for (final label in const [
                      'Sen',
                      'Sel',
                      'Rab',
                      'Kam',
                      'Jum',
                      'Sab',
                      'Min',
                    ])
                      Expanded(
                        child: Center(
                          child: Text(
                            label,
                            style: tt.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                    childAspectRatio: 0.95,
                  ),
                  itemCount: cellCount,
                  itemBuilder: (_, idx) {
                    if (idx < leadingEmpty) return const SizedBox.shrink();
                    final dayNum = idx - leadingEmpty + 1;
                    final date = DateTime(_month.year, _month.month, dayNum);
                    final dayKey = AppDateUtils.toDayKey(date);
                    final isFuture = date.isAfter(todayOnly);
                    final isToday = date == todayOnly;
                    final exp = expenseByDay[dayKey] ?? 0;
                    final level = isFuture
                        ? -1
                        : SpendingInsightsCalculator.heatmapLevel(
                            exp,
                            avgActive,
                          );

                    final bgColor = switch (level) {
                      -1 => cs.surfaceContainerLowest,
                      0 => AppColors.income(context).withValues(alpha: 0.14),
                      1 => AppColors.warning(context).withValues(alpha: 0.22),
                      2 => AppColors.warning(context).withValues(alpha: 0.5),
                      _ => AppColors.expense(context).withValues(alpha: 0.42),
                    };

                    return InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: isFuture
                          ? null
                          : () => _showDayTransactions(date, dayKey),
                      child: Container(
                        decoration: BoxDecoration(
                          color: bgColor,
                          borderRadius: BorderRadius.circular(10),
                          border: isToday
                              ? Border.all(color: cs.primary, width: 1.6)
                              : null,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '$dayNum',
                              style: tt.labelMedium?.copyWith(
                                fontWeight: isToday
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                color: isFuture
                                    ? cs.onSurfaceVariant.withValues(alpha: 0.4)
                                    : cs.onSurface,
                              ),
                            ),
                            if (!isFuture && exp > 0)
                              Text(
                                CurrencyFormatter.formatCompact(exp)
                                    .replaceFirst('Rp ', ''),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: tt.labelSmall?.copyWith(fontSize: 9),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    _LegendDot(
                      color: AppColors.income(context).withValues(alpha: 0.25),
                      label: 'No-Spend',
                    ),
                    _LegendDot(
                      color: AppColors.warning(context).withValues(alpha: 0.28),
                      label: 'Ringan',
                    ),
                    _LegendDot(
                      color: AppColors.warning(context).withValues(alpha: 0.6),
                      label: 'Sedang',
                    ),
                    _LegendDot(
                      color: AppColors.expense(context).withValues(alpha: 0.48),
                      label: 'Tinggi',
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 5),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}
