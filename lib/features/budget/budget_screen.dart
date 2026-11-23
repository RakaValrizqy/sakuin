import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sakuin/core/constants/app_colors.dart';
import 'package:sakuin/core/services/settings_service.dart';
import 'package:sakuin/core/utils/currency_formatter.dart';
import 'package:sakuin/core/utils/date_utils.dart';
import 'package:sakuin/core/widgets/category_icon.dart';
import 'package:sakuin/core/widgets/empty_state.dart';
import 'package:sakuin/features/budget/budget_form_sheet.dart';
import 'package:sakuin/features/budget/budget_providers.dart';

class BudgetScreen extends ConsumerWidget {
  const BudgetScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budgetsAsync = ref.watch(budgetProgressListProvider);
    final startDay = ref.watch(
      settingsProvider.select((s) => s.periodStartDay),
    );
    final period = AppDateUtils.periodForDate(DateTime.now(), startDay);
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Anggaran')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showBudgetFormSheet(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Tambah Anggaran'),
      ),
      body: budgetsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Gagal memuat anggaran: $e')),
        data: (items) {
          if (items.isEmpty) {
            return EmptyState(
              icon: Icons.pie_chart_outline_rounded,
              title: 'Belum ada anggaran',
              subtitle: 'Tetapkan batas pengeluaran bulanan total atau per kategori agar keuangan tetap terkontrol.',
              actionLabel: 'Buat Anggaran',
              onAction: () => showBudgetFormSheet(context),
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 96),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  'Periode aktif: ${period.label} (sisa ${period.remainingDaysFrom(DateTime.now())} hari)',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
              for (final item in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: BudgetProgressCard(
                    item: item,
                    onEdit: () =>
                        showBudgetFormSheet(context, existing: item.budget),
                    onDelete: () => ref
                        .read(budgetActionsProvider)
                        .deleteBudget(item.budget.id),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class BudgetProgressCard extends StatelessWidget {
  const BudgetProgressCard({
    super.key,
    required this.item,
    this.onEdit,
    this.onDelete,
  });

  final BudgetProgress item;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    final barColor = item.isExceeded
        ? AppColors.expense(context)
        : (item.isWarning
              ? AppColors.warning(context)
              : AppColors.income(context));

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CategoryIconBadge(
                    iconKey: item.icon,
                    colorValue: item.color,
                    size: 40,
                    iconSize: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.label, style: tt.titleMedium),
                        Text(
                          '${CurrencyFormatter.format(item.spent)} / ${CurrencyFormatter.format(item.budget.amount)}',
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: barColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${item.percent}%',
                      style: tt.labelLarge?.copyWith(color: barColor),
                    ),
                  ),
                  if (onDelete != null)
                    IconButton(
                      tooltip: 'Hapus anggaran',
                      icon: const Icon(Icons.delete_outline_rounded, size: 20),
                      onPressed: onDelete,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: item.ratio.clamp(0.0, 1.0),
                  minHeight: 10,
                  color: barColor,
                  backgroundColor: cs.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    item.remaining >= 0
                        ? 'Sisa ${CurrencyFormatter.format(item.remaining)}'
                        : 'Melebihi ${CurrencyFormatter.format(item.remaining.abs())}',
                    style: tt.bodySmall?.copyWith(
                      color: item.remaining < 0
                          ? AppColors.expense(context)
                          : cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (item.remaining > 0)
                    Text(
                      'Aman ${CurrencyFormatter.format(item.safeDailySpend)}/hari',
                      style: tt.bodySmall?.copyWith(
                        color: AppColors.income(context),
                        fontWeight: FontWeight.w600,
                      ),
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
