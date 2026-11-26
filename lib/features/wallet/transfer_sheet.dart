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
import 'package:sakuin/features/transaction/transaction_providers.dart';
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
  int? _fromPocketId; // null = Saldo Bebas
  int? _toPocketId; // null = Saldo Bebas
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

    final isSameWallet = _fromWalletId == _toWalletId;
    if (isSameWallet) {
      if (_fromPocketId == _toPocketId) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Untuk transfer dalam saku yang sama, pilih pos budget asal & tujuan yang berbeda',
            ),
          ),
        );
        return;
      }
      setState(() => _saving = true);
      await ref
          .read(walletActionsProvider)
          .allocateOrMovePocket(
            walletId: _fromWalletId!,
            fromPocketId: _fromPocketId,
            toPocketId: _toPocketId,
            amount: amount,
            note: _noteCtrl.text.trim(),
          );
      AppHaptics.light(ref.read(settingsProvider).hapticsEnabled);
      if (mounted) Navigator.of(context).pop(true);
      return;
    }

    setState(() => _saving = true);
    final db = ref.read(appDatabaseProvider);
    await db.saveTransactionWithMemory(
      type: 'transfer',
      amount: amount,
      walletId: _fromWalletId!,
      toWalletId: _toWalletId!,
      pocketId: _fromPocketId,
      toPocketId: _toPocketId,
      fee: fee,
      note: _noteCtrl.text.trim(),
      occurredAt: _date,
      updateItemMemory: false,
    );
    ref.read(transactionRevisionProvider.notifier).state++;
    await ref.read(settingsProvider.notifier).setLastWalletId(_fromWalletId!);
    AppHaptics.light(ref.read(settingsProvider).hapticsEnabled);

    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final wallets =
        ref.watch(walletsWithBalancesProvider).valueOrNull ?? const [];
    final allPockets =
        ref.watch(allActivePocketsProvider).valueOrNull ?? const [];

    if (_fromWalletId == null && wallets.isNotEmpty) {
      _fromWalletId = wallets.first.wallet.id;
    }
    if (_toWalletId == null && wallets.isNotEmpty) {
      _toWalletId = wallets.length >= 2
          ? wallets
                .firstWhere(
                  (w) => w.wallet.id != _fromWalletId,
                  orElse: () => wallets.last,
                )
                .wallet
                .id
          : wallets.first.wallet.id;
    }

    final fromPockets = allPockets
        .where((p) => p.pocket.walletId == _fromWalletId)
        .toList();
    final toPockets = allPockets
        .where((p) => p.pocket.walletId == _toWalletId)
        .toList();

    if (_fromPocketId != null &&
        !fromPockets.any((p) => p.pocket.id == _fromPocketId)) {
      _fromPocketId = null;
    }
    if (_toPocketId != null &&
        !toPockets.any((p) => p.pocket.id == _toPocketId)) {
      _toPocketId = null;
    }

    final isSameWallet = _fromWalletId != null && _fromWalletId == _toWalletId;
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
                Text('Transfer Saku / Budget', style: tt.headlineSmall),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Bisa transfer antar saku, langsung ke pos budget tertentu, atau pindah antar budget di saku yang sama.',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            if (wallets.isEmpty) ...[
              Card(
                color: cs.errorContainer.withValues(alpha: 0.4),
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Buat dompet terlebih dahulu untuk transfer.'),
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
                onChanged: (v) => setState(() {
                  _fromWalletId = v;
                  _fromPocketId = null;
                }),
              ),
              if (fromPockets.isNotEmpty) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<int?>(
                  initialValue: _fromPocketId,
                  decoration: const InputDecoration(
                    labelText: 'Dari Pos Budget (opsional)',
                  ),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('Saldo Bebas'),
                    ),
                    for (final p in fromPockets)
                      DropdownMenuItem<int?>(
                        value: p.pocket.id,
                        child: Text(
                          '${p.pocket.name} (${CurrencyFormatter.format(p.balance)})',
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => _fromPocketId = v),
                ),
              ],
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
                onChanged: (v) => setState(() {
                  _toWalletId = v;
                  _toPocketId = null;
                }),
              ),
              if (toPockets.isNotEmpty) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<int?>(
                  initialValue: _toPocketId,
                  decoration: const InputDecoration(
                    labelText: 'Ke Pos Budget (opsional)',
                  ),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('Saldo Bebas'),
                    ),
                    for (final p in toPockets)
                      DropdownMenuItem<int?>(
                        value: p.pocket.id,
                        child: Text(
                          '${p.pocket.name} (${CurrencyFormatter.format(p.balance)})',
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => _toPocketId = v),
                ),
              ],
              const SizedBox(height: 14),
              TextField(
                controller: _amountCtrl,
                keyboardType: TextInputType.text,
                decoration: const InputDecoration(
                  labelText: 'Nominal transfer',
                  prefixText: 'Rp ',
                  hintText: 'Contoh: 200k atau 1,5jt',
                ),
              ),
              if (!isSameWallet) ...[
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
              ] else
                const SizedBox(height: 12),
              TextField(
                controller: _noteCtrl,
                decoration: const InputDecoration(
                  labelText: 'Catatan (opsional)',
                  hintText: 'Contoh: Pindah ke Tabungan',
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : () => _save(wallets),
                  icon: const Icon(Icons.swap_horiz_rounded),
                  label: Text(
                    isSameWallet ? 'Pindah Budget di Saku' : 'Simpan Transfer',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
