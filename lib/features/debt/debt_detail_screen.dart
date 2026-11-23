import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sakuin/core/constants/app_colors.dart';
import 'package:sakuin/core/db/app_database.dart';
import 'package:sakuin/core/services/settings_service.dart';
import 'package:sakuin/core/utils/amount_parser.dart';
import 'package:sakuin/core/utils/currency_formatter.dart';
import 'package:sakuin/core/utils/date_utils.dart';
import 'package:sakuin/core/utils/haptics.dart';
import 'package:sakuin/core/widgets/amount_text.dart';
import 'package:sakuin/features/debt/debt_form_sheet.dart';
import 'package:sakuin/features/debt/debt_providers.dart';
import 'package:sakuin/features/wallet/wallet_providers.dart';

class DebtDetailScreen extends ConsumerWidget {
  const DebtDetailScreen({super.key, required this.debtId});

  final int debtId;

  Future<void> _showAddPaymentSheet(
    BuildContext context,
    WidgetRef ref,
    DebtWithSummary item,
  ) async {
    final amountCtrl = TextEditingController(
      text: CurrencyFormatter.format(item.remaining, withSymbol: false),
    );
    final noteCtrl = TextEditingController();
    final wallets =
        ref.read(walletsWithBalancesProvider).valueOrNull ?? const [];
    var affectWallet = item.debt.walletId != null;
    int? walletId =
        item.debt.walletId ??
        (wallets.isNotEmpty ? wallets.first.wallet.id : null);
    var paidAt = DateTime.now();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Catat Pembayaran / Cicilan',
                  style: Theme.of(ctx).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  'Sisa saat ini: ${CurrencyFormatter.format(item.remaining)}',
                  style: Theme.of(ctx).textTheme.bodyMedium,
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: amountCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Nominal bayar',
                    prefixText: 'Rp ',
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    ActionChip(
                      label: const Text('Lunas penuh'),
                      onPressed: () {
                        amountCtrl.text = CurrencyFormatter.format(
                          item.remaining,
                          withSymbol: false,
                        );
                      },
                    ),
                    if (item.remaining >= 2)
                      ActionChip(
                        label: const Text('50%'),
                        onPressed: () {
                          amountCtrl.text = CurrencyFormatter.format(
                            item.remaining ~/ 2,
                            withSymbol: false,
                          );
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_today_rounded),
                  title: const Text('Tanggal bayar'),
                  trailing: Text(AppDateUtils.formatShortDate(paidAt)),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: paidAt,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setModalState(() => paidAt = picked);
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Catat ke dompet'),
                  value: affectWallet,
                  onChanged: wallets.isEmpty
                      ? null
                      : (v) => setModalState(() => affectWallet = v),
                ),
                if (affectWallet && wallets.isNotEmpty) ...[
                  DropdownButtonFormField<int>(
                    initialValue: walletId,
                    decoration: const InputDecoration(labelText: 'Dompet'),
                    items: [
                      for (final wb in wallets)
                        DropdownMenuItem(
                          value: wb.wallet.id,
                          child: Text(wb.wallet.name),
                        ),
                    ],
                    onChanged: (v) => setModalState(() => walletId = v),
                  ),
                  const SizedBox(height: 10),
                ],
                TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Catatan (opsional)',
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () async {
                      final amount = AmountParser.parse(amountCtrl.text) ?? 0;
                      if (amount <= 0) return;
                      await ref
                          .read(debtActionsProvider)
                          .addPayment(
                            debtSummary: item,
                            amount: amount,
                            paidAt: paidAt,
                            walletId: affectWallet ? walletId : null,
                            note: noteCtrl.text.trim(),
                          );
                      AppHaptics.medium(
                        ref.read(settingsProvider).hapticsEnabled,
                      );
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    child: const Text('Simpan Pembayaran'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    amountCtrl.dispose();
    noteCtrl.dispose();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final debts = ref.watch(allDebtsProvider).valueOrNull ?? const [];
    final item = debts.where((d) => d.debt.id == debtId).firstOrNull;
    final paymentsAsync = ref.watch(debtPaymentsProvider(debtId));
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    if (item == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Detail Hutang')),
        body: const Center(child: Text('Catatan tidak ditemukan')),
      );
    }

    final isTheyOwe = item.debt.direction == 'they_owe';
    final statusColor = item.debt.status == 'settled'
        ? AppColors.income(context)
        : (isTheyOwe ? AppColors.income(context) : AppColors.expense(context));

    return Scaffold(
      appBar: AppBar(
        title: Text(item.person.name),
        actions: [
          if (item.remaining > 0)
            IconButton(
              tooltip: 'Bagikan pengingat penagihan',
              icon: const Icon(Icons.share_rounded),
              onPressed: () =>
                  ref.read(debtActionsProvider).shareBillingReminder(item),
            ),
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => showDebtFormSheet(context, existing: item),
          ),
          IconButton(
            tooltip: 'Hapus',
            icon: Icon(
              Icons.delete_outline_rounded,
              color: AppColors.expense(context),
            ),
            onPressed: () async {
              await ref.read(debtActionsProvider).deleteDebt(item.debt.id);
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
        ],
      ),
      floatingActionButton: item.remaining > 0
          ? FloatingActionButton.extended(
              onPressed: () => _showAddPaymentSheet(context, ref, item),
              icon: const Icon(Icons.payments_rounded),
              label: const Text('Catat Cicilan'),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Chip(
                        label: Text(
                          isTheyOwe
                              ? '${item.person.name} berutang ke kamu'
                              : 'Kamu berutang ke ${item.person.name}',
                        ),
                      ),
                      Chip(
                        backgroundColor: statusColor.withValues(alpha: 0.15),
                        label: Text(
                          item.debt.status == 'settled'
                              ? 'Lunas'
                              : (item.isOverdue ? 'Jatuh Tempo' : 'Aktif'),
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Sisa Hutang',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  AmountText(
                    amount: item.remaining,
                    type: item.remaining == 0
                        ? 'income'
                        : (isTheyOwe ? 'income' : 'expense'),
                    style: tt.headlineMedium,
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: item.progress,
                      minHeight: 10,
                      color: statusColor,
                      backgroundColor: cs.surfaceContainerHighest,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Terbayar: ${CurrencyFormatter.format(item.paidTotal)}',
                        style: tt.bodySmall,
                      ),
                      Text(
                        'Pokok: ${CurrencyFormatter.format(item.debt.principal)}',
                        style: tt.bodySmall,
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  _InfoLine(
                    label: 'Tanggal dicatat',
                    value: AppDateUtils.formatDayDate(
                      DateTime.fromMillisecondsSinceEpoch(item.debt.createdAt)
                          .toLocal(),
                    ),
                  ),
                  if (item.debt.dueDate != null)
                    _InfoLine(
                      label: 'Jatuh tempo',
                      value: AppDateUtils.formatDayDate(
                        DateTime.fromMillisecondsSinceEpoch(item.debt.dueDate!)
                            .toLocal(),
                      ),
                    ),
                  if (item.walletName != null)
                    _InfoLine(label: 'Dompet terkait', value: item.walletName!),
                  if (item.debt.note.isNotEmpty)
                    _InfoLine(label: 'Catatan', value: item.debt.note),
                  if (item.remaining > 0) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => ref
                            .read(debtActionsProvider)
                            .shareBillingReminder(item),
                        icon: const Icon(Icons.share_rounded),
                        label: const Text('Bagikan Pengingat Penagihan'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text('Riwayat Pembayaran', style: tt.titleMedium),
          const SizedBox(height: 8),
          paymentsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Error: $e'),
            data: (payments) {
              if (payments.isEmpty) {
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      'Belum ada pembayaran / cicilan dicatat.',
                      style: tt.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                );
              }
              return Card(
                child: Column(
                  children: [
                    for (var i = 0; i < payments.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.check_circle_outline_rounded),
                        title: AmountText(
                          amount: payments[i].amount,
                          type: 'income',
                          style: tt.titleMedium,
                        ),
                        subtitle: Text(
                          '${AppDateUtils.formatShortDate(DateTime.fromMillisecondsSinceEpoch(payments[i].paidAt).toLocal())}${payments[i].note.isNotEmpty ? ' • ${payments[i].note}' : ''}',
                        ),
                        trailing: IconButton(
                          tooltip: 'Hapus pembayaran',
                          icon: const Icon(Icons.delete_outline_rounded),
                          onPressed: () => ref
                              .read(debtActionsProvider)
                              .deletePayment(payments[i].id, debtId),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
          Expanded(child: Text(value, style: tt.bodyMedium)),
        ],
      ),
    );
  }
}
