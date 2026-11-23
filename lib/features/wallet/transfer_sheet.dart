import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sakuin/core/constants/app_colors.dart';
import 'package:sakuin/core/db/app_database.dart';
import 'package:sakuin/core/db/db_provider.dart';
import 'package:sakuin/core/services/settings_service.dart';
import 'package:sakuin/core/utils/amount_parser.dart';
import 'package:sakuin/core/utils/currency_formatter.dart';
import 'package:sakuin/core/utils/date_utils.dart';
import 'package:sakuin/core/utils/haptics.dart';
import 'package:sakuin/core/widgets/category_icon.dart';
import 'package:sakuin/features/wallet/wallet_providers.dart';

Future<bool?> showTransferSheet(
  BuildContext context, {
  int? initialFromWalletId,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => TransferSheet(initialFromWalletId: initialFromWalletId),
  );
}

class TransferSheet extends ConsumerStatefulWidget {
  const TransferSheet({super.key, this.initialFromWalletId});

  final int? initialFromWalletId;

  @override
  ConsumerState<TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends ConsumerState<TransferSheet> {
  final _amountCtrl = TextEditingController();
  final _feeCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  int? _fromWalletId;
  int? _toWalletId;
  DateTime _date = DateTime.now();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _fromWalletId = widget.initialFromWalletId;
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _feeCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save(List<WalletWithBalance> wallets) async {
    final amount = AmountParser.parse(_amountCtrl.text) ?? 0;
    final fee = _feeCtrl.text.trim().isEmpty
        ? 0
        : (AmountParser.parse(_feeCtrl.text) ?? 0);

    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Masukkan nominal transfer lebih dari 0')),
      );
      return;
    }
    if (_fromWalletId == null || _toWalletId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih dompet asal dan tujuan')),
      );
      return;
    }
    if (_fromWalletId == _toWalletId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dompet asal dan tujuan tidak boleh sama'),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    final db = ref.read(appDatabaseProvider);
    await db.saveTransactionWithMemory(
      type: 'transfer',
      amount: amount,
      walletId: _fromWalletId!,
      toWalletId: _toWalletId!,
      fee: fee,
      note: _noteCtrl.text.trim(),
      occurredAt: _date,
      updateItemMemory: false,
    );
    await ref.read(settingsProvider.notifier).setLastWalletId(_fromWalletId!);
    AppHaptics.light(ref.read(settingsProvider).hapticsEnabled);

    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final wallets =
        ref.watch(walletsWithBalancesProvider).valueOrNull ?? const [];
    if (_fromWalletId == null && wallets.isNotEmpty) {
      _fromWalletId = wallets.first.wallet.id;
    }
    if (_toWalletId == null && wallets.length >= 2) {
      _toWalletId = wallets
          .firstWhere(
            (w) => w.wallet.id != _fromWalletId,
            orElse: () => wallets.last,
          )
          .wallet
          .id;
    }

    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  Icons.swap_horiz_rounded,
                  color: AppColors.transfer(context),
                ),
                const SizedBox(width: 8),
                Text('Transfer Antar Saku', style: tt.headlineSmall),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Transfer tidak dihitung sebagai pemasukan/pengeluaran, kecuali biaya admin (masuk kategori Biaya Admin).',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),

            if (wallets.length < 2) ...[
              Card(
                color: cs.errorContainer.withValues(alpha: 0.4),
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Minimal butuh 2 dompet aktif untuk melakukan transfer.',
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ] else ...[
              Text('Dari Dompet', style: tt.labelMedium),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                initialValue: _fromWalletId,
                items: [
                  for (final wb in wallets)
                    DropdownMenuItem(
                      value: wb.wallet.id,
                      child: Row(
                        children: [
                          CategoryIconBadge(
                            iconKey: wb.wallet.icon,
                            colorValue: wb.wallet.color,
                            size: 28,
                            iconSize: 16,
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: Text(wb.wallet.name)),
                          Text(
                            CurrencyFormatter.format(wb.balance),
                            style: tt.bodySmall,
                          ),
                        ],
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _fromWalletId = v),
              ),
              const SizedBox(height: 12),

              Text('Ke Dompet', style: tt.labelMedium),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                initialValue: _toWalletId,
                items: [
                  for (final wb in wallets)
                    DropdownMenuItem(
                      value: wb.wallet.id,
                      child: Row(
                        children: [
                          CategoryIconBadge(
                            iconKey: wb.wallet.icon,
                            colorValue: wb.wallet.color,
                            size: 28,
                            iconSize: 16,
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: Text(wb.wallet.name)),
                          Text(
                            CurrencyFormatter.format(wb.balance),
                            style: tt.bodySmall,
                          ),
                        ],
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _toWalletId = v),
              ),
              const SizedBox(height: 14),

              TextField(
                controller: _amountCtrl,
                keyboardType: TextInputType.text,
                decoration: const InputDecoration(
                  labelText: 'Nominal transfer',
                  prefixText: 'Rp ',
                  hintText: 'Contoh: 500k atau 1,5jt',
                ),
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _feeCtrl,
                keyboardType: TextInputType.text,
                decoration: const InputDecoration(
                  labelText: 'Biaya admin (opsional)',
                  prefixText: 'Rp ',
                  hintText: 'Contoh: 2500 atau 6,5k',
                ),
              ),
              const SizedBox(height: 12),

              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_today_rounded),
                title: const Text('Tanggal'),
                trailing: Text(
                  AppDateUtils.formatDayDate(_date),
                  style: tt.titleSmall,
                ),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) {
                    setState(() {
                      _date = DateTime(
                        picked.year,
                        picked.month,
                        picked.day,
                        _date.hour,
                        _date.minute,
                      );
                    });
                  }
                },
              ),

              TextField(
                controller: _noteCtrl,
                decoration: const InputDecoration(
                  labelText: 'Catatan (opsional)',
                  hintText: 'Contoh: Top up e-wallet',
                ),
              ),
              const SizedBox(height: 18),

              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : () => _save(wallets),
                  icon: const Icon(Icons.swap_horiz_rounded),
                  label: const Text('Simpan Transfer'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
