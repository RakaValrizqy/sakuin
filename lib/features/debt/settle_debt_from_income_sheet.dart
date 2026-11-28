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
import 'package:sakuin/core/utils/thousands_input_formatter.dart';
import 'package:sakuin/core/widgets/amount_text.dart';
import 'package:sakuin/features/debt/debt_form_sheet.dart';
import 'package:sakuin/features/debt/debt_providers.dart';
import 'package:sakuin/features/transaction/transaction_providers.dart';
import 'package:sakuin/features/wallet/wallet_providers.dart';

/// Hasil alokasi transfer masuk ke pelunasan piutang (hutang orang lain ke kita).
class SettleDebtAllocationResult {
  const SettleDebtAllocationResult({
    required this.settledCount,
    required this.totalAllocatedToDebts,
    required this.excessRecordedAsIncome,
    required this.walletId,
  });

  final int settledCount;
  final int totalAllocatedToDebts;
  final int excessRecordedAsIncome;
  final int walletId;
}

/// Buka bottom sheet untuk mengalokasikan dana/transfer masuk ke pelunasan
/// hutang orang lain (piutang / `they_owe`), bisa pilih 1 atau beberapa item sekaligus.
Future<SettleDebtAllocationResult?> showSettleDebtFromIncomeSheet(
  BuildContext context, {
  required int incomingAmount,
  required int initialWalletId,
  required DateTime occurredAt,
  String? senderHint,
  String? bankName,
  String? externalRef,
}) {
  return showModalBottomSheet<SettleDebtAllocationResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.9,
      child: SettleDebtFromIncomeSheet(
        incomingAmount: incomingAmount,
        initialWalletId: initialWalletId,
        occurredAt: occurredAt,
        senderHint: senderHint,
        bankName: bankName,
        externalRef: externalRef,
      ),
    ),
  );
}

/// Kalkulasi alokasi otomatis nominal transfer masuk ke beberapa item piutang terpilih.
Map<int, int> computeDebtAllocationMap({
  required int incomingAmount,
  required List<DebtWithSummary> selectedDebts,
  Map<int, int> manualOverrides = const {},
}) {
  final result = <int, int>{};
  var remainingPool = incomingAmount;

  for (final item in selectedDebts) {
    if (remainingPool <= 0) {
      result[item.debt.id] = 0;
      continue;
    }
    final override = manualOverrides[item.debt.id];
    final desired = override ?? item.remaining;
    final clamped = desired.clamp(0, item.remaining);
    final alloc = clamped > remainingPool ? remainingPool : clamped;
    result[item.debt.id] = alloc;
    remainingPool -= alloc;
  }
  return result;
}

class SettleDebtFromIncomeSheet extends ConsumerStatefulWidget {
  const SettleDebtFromIncomeSheet({
    super.key,
    required this.incomingAmount,
    required this.initialWalletId,
    required this.occurredAt,
    this.senderHint,
    this.bankName,
    this.externalRef,
  });

  final int incomingAmount;
  final int initialWalletId;
  final DateTime occurredAt;
  final String? senderHint;
  final String? bankName;
  final String? externalRef;

  @override
  ConsumerState<SettleDebtFromIncomeSheet> createState() =>
      _SettleDebtFromIncomeSheetState();
}

class _SettleDebtFromIncomeSheetState
    extends ConsumerState<SettleDebtFromIncomeSheet> {
  late int _walletId;
  int? _pocketId;
  final Set<int> _selectedDebtIds = {};
  final Map<int, int> _manualAmounts = {};
  bool _recordExcessAsIncome = true;
  bool _saving = false;
  bool _autoPreselected = false;

  @override
  void initState() {
    super.initState();
    _walletId = widget.initialWalletId;
  }

  bool _isLikelyMatch(DebtWithSummary item) {
    if (item.remaining == widget.incomingAmount) return true;
    final hint = (widget.senderHint ?? '').trim().toLowerCase();
    if (hint.length >= 3) {
      final pName = item.person.name.trim().toLowerCase();
      if (pName.length >= 3 && (hint.contains(pName) || pName.contains(hint))) {
        return true;
      }
    }
    return false;
  }

  Future<void> _editAllocatedAmount(
    DebtWithSummary item,
    int currentAlloc,
    int maxAllowed,
  ) async {
    final ctrl = TextEditingController(
      text: CurrencyFormatter.format(currentAlloc, withSymbol: false),
    );
    final entered = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Nominal untuk ${item.person.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sisa hutang: ${CurrencyFormatter.format(item.remaining)}\nMaks. dari transfer ini: ${CurrencyFormatter.format(maxAllowed)}',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [ThousandsSeparatorInputFormatter()],
              decoration: const InputDecoration(
                labelText: 'Nominal pelunasan',
                prefixText: 'Rp ',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              final val = AmountParser.parse(ctrl.text) ?? 0;
              Navigator.pop(ctx, val);
            },
            child: const Text('Terapkan'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (entered != null && mounted) {
      setState(() {
        if (entered <= 0) {
          _selectedDebtIds.remove(item.debt.id);
          _manualAmounts.remove(item.debt.id);
        } else {
          _selectedDebtIds.add(item.debt.id);
          _manualAmounts[item.debt.id] = entered.clamp(1, item.remaining);
        }
      });
    }
  }

  Future<void> _save(
    List<DebtWithSummary> selectedDebts,
    Map<int, int> allocationMap,
  ) async {
    if (_saving) return;
    final totalAllocated = allocationMap.values.fold<int>(0, (s, v) => s + v);
    if (totalAllocated <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pilih minimal satu item piutang yang ingin dilunasi'),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final debtActions = ref.read(debtActionsProvider);
      final noteParts = <String>[
        if (widget.bankName != null && widget.bankName!.isNotEmpty)
          'Transfer masuk ${widget.bankName}'
        else
          'Transfer masuk',
        if (widget.senderHint != null &&
            widget.senderHint!.trim().isNotEmpty &&
            !widget.senderHint!.toLowerCase().startsWith('dana masuk '))
          widget.senderHint!.trim(),
      ];
      final payNote = noteParts.join(' • ');

      var settledCount = 0;
      for (final item in selectedDebts) {
        final amt = allocationMap[item.debt.id] ?? 0;
        if (amt <= 0) continue;
        await debtActions.addPayment(
          debtSummary: item,
          amount: amt,
          paidAt: widget.occurredAt,
          walletId: _walletId,
          note: payNote,
        );
        settledCount++;
      }

      // Jika pengguna memilih Pos Budget tujuan, masukkan dana pelunasan dari Saldo Bebas ke pos tsb
      if (_pocketId != null) {
        await ref
            .read(walletActionsProvider)
            .allocateOrMovePocket(
              walletId: _walletId,
              fromPocketId: null,
              toPocketId: _pocketId,
              amount: totalAllocated,
              note: 'Pelunasan piutang ($payNote)',
            );
      }

      // Jika nominal transfer lebih besar dari total piutang yang dilunasi,
      // opsional catat kelebihannya sebagai pemasukan biasa agar saldo dompet cocok 100%.
      final excess = widget.incomingAmount - totalAllocated;
      var excessRecorded = 0;
      if (excess > 0 && _recordExcessAsIncome) {
        final db = ref.read(appDatabaseProvider);
        final incCat =
            await db.findCategoryIdByName('Lainnya', 'income') ??
            await db.findCategoryIdByName('Bonus', 'income');
        await ref
            .read(transactionActionsProvider)
            .saveTransaction(
              type: 'income',
              amount: excess,
              walletId: _walletId,
              pocketId: _pocketId,
              categoryId: incCat,
              itemName: widget.senderHint?.trim().isNotEmpty == true
                  ? 'Sisa transfer ${widget.senderHint}'
                  : 'Sisa transfer pelunasan',
              merchantName: widget.senderHint,
              note: payNote,
              occurredAt: widget.occurredAt,
            );
        excessRecorded = excess;
      }

      ref.read(transactionRevisionProvider.notifier).state++;
      AppHaptics.medium(ref.read(settingsProvider).hapticsEnabled);

      if (mounted) {
        Navigator.of(context).pop(
          SettleDebtAllocationResult(
            settledCount: settledCount,
            totalAllocatedToDebts: totalAllocated,
            excessRecordedAsIncome: excessRecorded,
            walletId: _walletId,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final allDebts = ref.watch(allDebtsProvider).valueOrNull ?? const [];
    final wallets =
        ref.watch(walletsWithBalancesProvider).valueOrNull ?? const [];
    final allPockets =
        ref.watch(allActivePocketsProvider).valueOrNull ?? const [];

    if (wallets.isNotEmpty && !wallets.any((w) => w.wallet.id == _walletId)) {
      _walletId = wallets.first.wallet.id;
    }
    final walletPockets = allPockets
        .where((p) => p.pocket.walletId == _walletId)
        .toList();
    if (_pocketId != null &&
        !walletPockets.any((p) => p.pocket.id == _pocketId)) {
      _pocketId = null;
    }

    // Ambil semua piutang aktif ("they_owe" — orang lain berhutang ke saya)
    final openReceivables =
        allDebts
            .where(
              (d) =>
                  d.debt.status == 'open' &&
                  d.debt.direction == 'they_owe' &&
                  d.remaining > 0,
            )
            .toList()
          ..sort((a, b) {
            final ma = _isLikelyMatch(a) ? 0 : 1;
            final mb = _isLikelyMatch(b) ? 0 : 1;
            if (ma != mb) return ma.compareTo(mb);
            final exactA = a.remaining == widget.incomingAmount ? 0 : 1;
            final exactB = b.remaining == widget.incomingAmount ? 0 : 1;
            if (exactA != exactB) return exactA.compareTo(exactB);
            return b.debt.createdAt.compareTo(a.debt.createdAt);
          });

    // Auto-centang 1 item jika persis cocok nominal & belum ada yang dipilih
    if (!_autoPreselected && openReceivables.isNotEmpty) {
      _autoPreselected = true;
      final exact = openReceivables
          .where((d) => d.remaining == widget.incomingAmount)
          .firstOrNull;
      if (exact != null) {
        _selectedDebtIds.add(exact.debt.id);
      }
    }

    final selectedDebts = openReceivables
        .where((d) => _selectedDebtIds.contains(d.debt.id))
        .toList();
    final allocationMap = computeDebtAllocationMap(
      incomingAmount: widget.incomingAmount,
      selectedDebts: selectedDebts,
      manualOverrides: _manualAmounts,
    );
    final totalAllocated = allocationMap.values.fold<int>(0, (s, v) => s + v);
    final remainingExcess = (widget.incomingAmount - totalAllocated).clamp(
      0,
      widget.incomingAmount,
    );

    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Tutup',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Masuk ke Hutang Orang Lain', style: tt.titleLarge),
                      Text(
                        widget.senderHint != null &&
                                widget.senderHint!.trim().isNotEmpty
                            ? '${widget.senderHint} • ${AppDateUtils.formatShortDate(widget.occurredAt)}'
                            : 'Pilih item piutang yang dilunasi',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Ringkasan Transfer Masuk vs Alokasi Piutang
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.income(context).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.income(context).withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Dana Transfer Masuk', style: tt.labelSmall),
                      AmountText(
                        amount: widget.incomingAmount,
                        type: 'income',
                        signed: true,
                        style: tt.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        remainingExcess == 0
                            ? 'Alokasi Piutang'
                            : 'Sisa Transfer',
                        style: tt.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        remainingExcess == 0
                            ? 'Pas ${CurrencyFormatter.format(totalAllocated)}!'
                            : CurrencyFormatter.format(remainingExcess),
                        style: tt.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: remainingExcess == 0
                              ? AppColors.income(context)
                              : cs.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Pilihan Dompet & Pos Budget (opsional)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: wallets.isNotEmpty ? _walletId : null,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Masuk ke Dompet',
                      isDense: true,
                    ),
                    items: [
                      for (final wb in wallets)
                        DropdownMenuItem(
                          value: wb.wallet.id,
                          child: Text(
                            wb.wallet.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (v) => setState(() {
                      if (v != null) {
                        _walletId = v;
                        _pocketId = null;
                      }
                    }),
                  ),
                ),
                if (walletPockets.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<int?>(
                      initialValue: _pocketId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Kembalikan ke Pos',
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Text('Saldo Bebas'),
                        ),
                        for (final p in walletPockets)
                          DropdownMenuItem<int?>(
                            value: p.pocket.id,
                            child: Text(
                              p.pocket.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) => setState(() => _pocketId = v),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Daftar Piutang Aktif (Orang Lain Berhutang ke Saya)
          Expanded(
            child: openReceivables.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.handshake_outlined,
                            size: 44,
                            color: cs.onSurfaceVariant,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Belum ada catatan piutang aktif',
                            style: tt.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Buat catatan piutang dulu jika teman berhutang kepadamu, lalu lunasi dari transfer ini.',
                            textAlign: TextAlign.center,
                            style: tt.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 14),
                          FilledButton.tonalIcon(
                            onPressed: () => showDebtFormSheet(
                              context,
                              initialDirection: 'they_owe',
                            ),
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Buat Catatan Piutang'),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                    children: [
                      Text(
                        'Pilih item piutang yang dilunasi (${openReceivables.length} aktif):',
                        style: tt.labelMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (final item in openReceivables)
                        Builder(
                          builder: (ctx) {
                            final selected = _selectedDebtIds.contains(
                              item.debt.id,
                            );
                            final allocated = allocationMap[item.debt.id] ?? 0;
                            final isMatch = _isLikelyMatch(item);
                            final willSettle =
                                selected && allocated >= item.remaining;

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Card(
                                color: selected
                                    ? cs.primaryContainer.withValues(
                                        alpha: 0.35,
                                      )
                                    : null,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(18),
                                  onTap: () {
                                    AppHaptics.selection(
                                      ref.read(settingsProvider).hapticsEnabled,
                                    );
                                    setState(() {
                                      if (selected) {
                                        _selectedDebtIds.remove(item.debt.id);
                                        _manualAmounts.remove(item.debt.id);
                                      } else {
                                        _selectedDebtIds.add(item.debt.id);
                                      }
                                    });
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Row(
                                      children: [
                                        Checkbox(
                                          value: selected,
                                          onChanged: (v) {
                                            setState(() {
                                              if (v == true) {
                                                _selectedDebtIds.add(
                                                  item.debt.id,
                                                );
                                              } else {
                                                _selectedDebtIds.remove(
                                                  item.debt.id,
                                                );
                                                _manualAmounts.remove(
                                                  item.debt.id,
                                                );
                                              }
                                            });
                                          },
                                        ),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Flexible(
                                                    child: Text(
                                                      item.person.name,
                                                      style: tt.titleSmall
                                                          ?.copyWith(
                                                            fontWeight:
                                                                FontWeight.w700,
                                                          ),
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  if (isMatch) ...[
                                                    const SizedBox(width: 6),
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 6,
                                                            vertical: 2,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color:
                                                            AppColors.income(
                                                              context,
                                                            ).withValues(
                                                              alpha: 0.18,
                                                            ),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              6,
                                                            ),
                                                      ),
                                                      child: Text(
                                                        'Cocok',
                                                        style: tt.labelSmall
                                                            ?.copyWith(
                                                              color:
                                                                  AppColors.income(
                                                                    context,
                                                                  ),
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
                                                            ),
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                              if (item.debt.note.isNotEmpty)
                                                Text(
                                                  item.debt.note,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: tt.bodySmall?.copyWith(
                                                    color: cs.onSurfaceVariant,
                                                  ),
                                                ),
                                              const SizedBox(height: 2),
                                              Text(
                                                'Sisa: ${CurrencyFormatter.format(item.remaining)}',
                                                style: tt.labelSmall?.copyWith(
                                                  color: cs.onSurfaceVariant,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (selected)
                                          InkWell(
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            onTap: () {
                                              final otherAlloc =
                                                  totalAllocated - allocated;
                                              final maxAllowed =
                                                  (widget.incomingAmount -
                                                          otherAlloc)
                                                      .clamp(0, item.remaining);
                                              _editAllocatedAmount(
                                                item,
                                                allocated,
                                                maxAllowed,
                                              );
                                            },
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 6,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: cs.surface,
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                border: Border.all(
                                                  color: cs.outlineVariant,
                                                ),
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.end,
                                                children: [
                                                  Text(
                                                    CurrencyFormatter.format(
                                                      allocated,
                                                    ),
                                                    style: tt.labelLarge
                                                        ?.copyWith(
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          color:
                                                              AppColors.income(
                                                                context,
                                                              ),
                                                        ),
                                                  ),
                                                  Text(
                                                    willSettle
                                                        ? 'Lunas • ubah'
                                                        : 'Cicil • ubah',
                                                    style: tt.labelSmall
                                                        ?.copyWith(
                                                          fontSize: 10,
                                                          color: cs
                                                              .onSurfaceVariant,
                                                        ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      if (remainingExcess > 0 && totalAllocated > 0) ...[
                        const SizedBox(height: 6),
                        Card(
                          child: CheckboxListTile(
                            controlAffinity: ListTileControlAffinity.leading,
                            title: Text(
                              'Catat sisa ${CurrencyFormatter.format(remainingExcess)} sebagai Pemasukan',
                            ),
                            subtitle: const Text(
                              'Agar total saldo dompet cocok 100% dengan nominal transfer masuk',
                            ),
                            value: _recordExcessAsIncome,
                            onChanged: (v) => setState(
                              () => _recordExcessAsIncome = v ?? true,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
          ),

          // Sticky Save Button
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              decoration: BoxDecoration(
                color: cs.surface,
                border: Border(top: BorderSide(color: cs.outlineVariant)),
              ),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving || totalAllocated <= 0
                      ? null
                      : () => _save(selectedDebts, allocationMap),
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_rounded),
                  label: Text(
                    totalAllocated > 0
                        ? 'Simpan Pelunasan • ${CurrencyFormatter.format(totalAllocated)}'
                        : 'Pilih Piutang untuk Dilunasi',
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
