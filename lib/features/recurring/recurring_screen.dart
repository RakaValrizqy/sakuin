import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sakuin/core/utils/date_utils.dart';
import 'package:sakuin/core/widgets/amount_text.dart';
import 'package:sakuin/core/widgets/empty_state.dart';
import 'package:sakuin/features/recurring/recurring_form_sheet.dart';
import 'package:sakuin/features/recurring/recurring_service.dart';

class RecurringScreen extends ConsumerWidget {
  const RecurringScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rulesAsync = ref.watch(recurringRulesProvider);
    final pending = ref.watch(pendingRecurringRulesProvider);
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Transaksi Berulang')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showRecurringFormSheet(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Aturan Baru'),
      ),
      body: rulesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Gagal memuat: $e')),
        data: (rules) {
          if (rules.isEmpty) {
            return EmptyState(
              icon: Icons.event_repeat_rounded,
              title: 'Belum ada transaksi berulang',
              subtitle: 'Atur gaji bulanan, langganan, atau cicilan rutin agar tercatat otomatis tepat waktu.',
              actionLabel: 'Tambah Aturan',
              onAction: () => showRecurringFormSheet(context),
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: [
              if (pending.isNotEmpty) ...[
                Text('Menunggu Konfirmasi', style: tt.titleMedium),
                const SizedBox(height: 8),
                for (final rule in pending)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Card(
                      color: cs.primaryContainer.withValues(alpha: 0.4),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    rule.title,
                                    style: tt.titleMedium,
                                  ),
                                ),
                                AmountText(
                                  amount: rule.amount,
                                  type: rule.type,
                                  signed: true,
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Jatuh tempo ${AppDateUtils.formatShortDate(AppDateUtils.fromDayKey(rule.nextDue))}',
                              style: tt.bodySmall,
                            ),
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  onPressed: () => ref
                                      .read(recurringServiceProvider)
                                      .skipRuleOccurrence(rule),
                                  child: const Text('Lewati'),
                                ),
                                const SizedBox(width: 8),
                                FilledButton(
                                  onPressed: () => ref
                                      .read(recurringServiceProvider)
                                      .confirmRuleNow(rule),
                                  child: const Text('Catat Sekarang'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
              ],
              Text('Semua Aturan', style: tt.titleMedium),
              const SizedBox(height: 8),
              for (final rule in rules)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: ListTile(
                      onTap: () =>
                          showRecurringFormSheet(context, existing: rule),
                      title: Text(rule.title),
                      subtitle: Text(
                        '${frequencyLabel(rule.frequency)} • ${rule.autoCreate ? 'Otomatis' : 'Konfirmasi'} • Berikutnya ${AppDateUtils.formatShortDate(AppDateUtils.fromDayKey(rule.nextDue))}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AmountText(
                            amount: rule.amount,
                            type: rule.type,
                            signed: true,
                          ),
                          Switch(
                            value: rule.isActive,
                            onChanged: (v) => ref
                                .read(recurringServiceProvider)
                                .toggleActive(rule.id, v),
                          ),
                        ],
                      ),
                      onLongPress: () async {
                        await ref
                            .read(recurringServiceProvider)
                            .deleteRule(rule.id);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Aturan "${rule.title}" dihapus'),
                            ),
                          );
                        }
                      },
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
