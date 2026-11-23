import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sakuin/core/constants/app_colors.dart';
import 'package:sakuin/core/db/app_database.dart';
import 'package:sakuin/core/utils/currency_formatter.dart';
import 'package:sakuin/core/utils/date_utils.dart';
import 'package:sakuin/core/widgets/amount_text.dart';
import 'package:sakuin/features/debt/debt_detail_screen.dart';
import 'package:sakuin/features/debt/debt_form_sheet.dart';
import 'package:sakuin/features/debt/debt_providers.dart';

class PersonDebtScreen extends ConsumerWidget {
  const PersonDebtScreen({super.key, required this.person});

  final Person person;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allDebts = ref.watch(allDebtsProvider).valueOrNull ?? const [];
    final personDebts = allDebts
        .where((d) => d.person.id == person.id)
        .toList();

    var iOwe = 0;
    var theyOwe = 0;
    for (final d in personDebts) {
      if (d.debt.status != 'open') continue;
      if (d.debt.direction == 'i_owe') {
        iOwe += d.remaining;
      } else {
        theyOwe += d.remaining;
      }
    }
    final net = theyOwe - iOwe;

    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    String summaryLine;
    if (net > 0) {
      summaryLine =
          '${person.name} berutang ${CurrencyFormatter.format(net)} ke kamu';
    } else if (net < 0) {
      summaryLine =
          'Kamu berutang ${CurrencyFormatter.format(net.abs())} ke ${person.name}';
    } else {
      summaryLine = 'Tidak ada sisa hutang aktif dengan ${person.name}';
    }

    return Scaffold(
      appBar: AppBar(title: Text(person.name)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            showDebtFormSheet(context, prefillPersonName: person.name),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Catat Baru'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          Card(
            color:
                (net > 0
                        ? AppColors.income(context)
                        : (net < 0 ? AppColors.expense(context) : cs.primary))
                    .withValues(alpha: 0.12),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Saldo Bersih', style: tt.labelMedium),
                  const SizedBox(height: 6),
                  Text(summaryLine, style: tt.titleLarge),
                  if (person.phone != null && person.phone!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      person.phone!,
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Semua Catatan (${personDebts.length})', style: tt.titleMedium),
          const SizedBox(height: 8),
          for (final item in personDebts)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                child: ListTile(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => DebtDetailScreen(debtId: item.debt.id),
                    ),
                  ),
                  title: Text(
                    item.debt.note.isNotEmpty
                        ? item.debt.note
                        : (item.debt.direction == 'they_owe'
                              ? 'Piutang dari ${person.name}'
                              : 'Hutang ke ${person.name}'),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${item.debt.status == 'settled' ? 'Lunas' : 'Aktif'} • ${AppDateUtils.formatShortDate(DateTime.fromMillisecondsSinceEpoch(item.debt.createdAt).toLocal())}',
                      ),
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                        value: item.progress,
                        minHeight: 6,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ],
                  ),
                  trailing: AmountText(
                    amount: item.remaining == 0
                        ? item.debt.principal
                        : item.remaining,
                    type: item.debt.direction == 'they_owe'
                        ? 'income'
                        : 'expense',
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
