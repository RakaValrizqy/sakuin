import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sakuin/core/constants/app_colors.dart';
import 'package:sakuin/core/db/app_database.dart';
import 'package:sakuin/core/utils/currency_formatter.dart';
import 'package:sakuin/core/utils/date_utils.dart';
import 'package:sakuin/core/widgets/amount_text.dart';
import 'package:sakuin/core/widgets/empty_state.dart';
import 'package:sakuin/features/debt/debt_detail_screen.dart';
import 'package:sakuin/features/debt/debt_form_sheet.dart';
import 'package:sakuin/features/debt/debt_providers.dart';
import 'package:sakuin/features/debt/person_debt_screen.dart';

class DebtListScreen extends ConsumerStatefulWidget {
  const DebtListScreen({super.key});

  @override
  ConsumerState<DebtListScreen> createState() => _DebtListScreenState();
}

class _DebtListScreenState extends ConsumerState<DebtListScreen> {
  String _viewMode = 'they_owe'; // 'they_owe' | 'i_owe' | 'people'
  String _statusFilter = 'open'; // 'open' | 'settled' | 'overdue'

  @override
  Widget build(BuildContext context) {
    final debtsAsync = ref.watch(allDebtsProvider);
    final peopleAsync = ref.watch(personDebtSummariesProvider);
    final totals = ref.watch(debtTotalsProvider);
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Hutang & Piutang')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showDebtFormSheet(
          context,
          initialDirection: _viewMode == 'i_owe' ? 'i_owe' : 'they_owe',
        ),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Catat Hutang'),
      ),
      body: Column(
        children: [
          // Ringkasan Total Hutang & Piutang
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Akan Diterima',
                                style: tt.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 2),
                              AmountText(
                                amount: totals.theyOweTotal,
                                type: 'income',
                                style: tt.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Harus Dibayar',
                                style: tt.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 2),
                              AmountText(
                                amount: totals.iOweTotal,
                                type: 'expense',
                                style: tt.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Saldo Bersih', style: tt.labelMedium),
                        AmountText(
                          amount: totals.net,
                          type: totals.net > 0
                              ? 'income'
                              : (totals.net < 0 ? 'expense' : null),
                          signed: true,
                          style: tt.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Segmented Tab (Mereka Berutang / Saya Berutang / Per Orang)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'they_owe', label: Text('Piutang')),
                ButtonSegment(value: 'i_owe', label: Text('Hutang Saya')),
                ButtonSegment(value: 'people', label: Text('Per Orang')),
              ],
              selected: {_viewMode},
              onSelectionChanged: (s) => setState(() => _viewMode = s.first),
            ),
          ),

          if (_viewMode != 'people') ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text('Aktif'),
                    selected: _statusFilter == 'open',
                    onSelected: (_) => setState(() => _statusFilter = 'open'),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Jatuh Tempo'),
                    selected: _statusFilter == 'overdue',
                    onSelected: (_) =>
                        setState(() => _statusFilter = 'overdue'),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Lunas'),
                    selected: _statusFilter == 'settled',
                    onSelected: (_) =>
                        setState(() => _statusFilter = 'settled'),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),

          Expanded(
            child: _viewMode == 'people'
                ? peopleAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('Error: $e')),
                    data: (people) {
                      if (people.isEmpty) {
                        return EmptyState(
                          icon: Icons.people_outline_rounded,
                          title: 'Belum ada kontak teman',
                          subtitle: 'Kontak teman otomatis tersimpan saat kamu mencatat hutang-piutang.',
                          actionLabel: 'Catat Hutang',
                          onAction: () => showDebtFormSheet(context),
                        );
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                        itemCount: people.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (_, idx) {
                          final summary = people[idx];
                          final net = summary.netTheyOwe;
                          final subtitle = net > 0
                              ? '${summary.person.name} berutang ${CurrencyFormatter.format(net)} ke kamu'
                              : (net < 0
                                    ? 'Kamu berutang ${CurrencyFormatter.format(net.abs())} ke ${summary.person.name}'
                                    : 'Semua lunas');
                          return Card(
                            child: ListTile(
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      PersonDebtScreen(person: summary.person),
                                ),
                              ),
                              leading: CircleAvatar(
                                child: Text(
                                  summary.person.name.isNotEmpty
                                      ? summary.person.name[0].toUpperCase()
                                      : '?',
                                ),
                              ),
                              title: Text(summary.person.name),
                              subtitle: Text(subtitle),
                              trailing: const Icon(Icons.chevron_right_rounded),
                            ),
                          );
                        },
                      );
                    },
                  )
                : debtsAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('Error: $e')),
                    data: (allDebts) {
                      final filtered = allDebts.where((d) {
                        if (d.debt.direction != _viewMode) return false;
                        if (_statusFilter == 'settled') {
                          return d.debt.status == 'settled';
                        }
                        if (_statusFilter == 'overdue') {
                          return d.isOverdue;
                        }
                        return d.debt.status == 'open';
                      }).toList();

                      if (filtered.isEmpty) {
                        return EmptyState(
                          icon: Icons.handshake_outlined,
                          title: 'Tidak ada catatan',
                          subtitle: _statusFilter == 'overdue'
                              ? 'Tidak ada hutang/piutang yang melewati jatuh tempo.'
                              : 'Ketuk tombol "Catat Hutang" untuk menambahkan catatan baru.',
                          actionLabel: 'Catat Hutang',
                          onAction: () => showDebtFormSheet(
                            context,
                            initialDirection: _viewMode,
                          ),
                        );
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, idx) => _DebtCard(item: filtered[idx]),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _DebtCard extends ConsumerWidget {
  const _DebtCard({required this.item});

  final DebtWithSummary item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final isTheyOwe = item.debt.direction == 'they_owe';
    final color = isTheyOwe
        ? AppColors.income(context)
        : AppColors.expense(context);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DebtDetailScreen(debtId: item.debt.id),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: color.withValues(alpha: 0.14),
                    foregroundColor: color,
                    child: Text(
                      item.person.name.isNotEmpty
                          ? item.person.name[0].toUpperCase()
                          : '?',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.person.name, style: tt.titleMedium),
                        if (item.debt.note.isNotEmpty)
                          Text(
                            item.debt.note,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tt.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      AmountText(
                        amount: item.remaining == 0
                            ? item.debt.principal
                            : item.remaining,
                        type: isTheyOwe ? 'income' : 'expense',
                        style: tt.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (item.debt.dueDate != null)
                        Text(
                          'Tempo ${AppDateUtils.formatShortDate(DateTime.fromMillisecondsSinceEpoch(item.debt.dueDate!).toLocal())}',
                          style: tt.labelSmall?.copyWith(
                            color: item.isOverdue
                                ? AppColors.expense(context)
                                : cs.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: item.progress,
                  minHeight: 7,
                  color: color,
                  backgroundColor: cs.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Terbayar ${CurrencyFormatter.format(item.paidTotal)} / ${CurrencyFormatter.format(item.debt.principal)}',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  if (item.remaining > 0)
                    InkWell(
                      onTap: () => ref
                          .read(debtActionsProvider)
                          .shareBillingReminder(item),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.share_rounded,
                              size: 16,
                              color: cs.primary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Ingatkan',
                              style: tt.labelMedium?.copyWith(
                                color: cs.primary,
                              ),
                            ),
                          ],
                        ),
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
