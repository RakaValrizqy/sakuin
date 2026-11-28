import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sakuin/core/constants/app_colors.dart';
import 'package:sakuin/core/constants/app_icons.dart';
import 'package:sakuin/core/db/app_database.dart';
import 'package:sakuin/core/db/db_provider.dart';
import 'package:sakuin/core/services/settings_service.dart';
import 'package:sakuin/core/utils/currency_formatter.dart';
import 'package:sakuin/core/utils/date_utils.dart';
import 'package:sakuin/core/utils/haptics.dart';
import 'package:sakuin/core/widgets/amount_text.dart';
import 'package:sakuin/features/transaction/transaction_form_sheet.dart';
import 'package:sakuin/features/transaction/transaction_providers.dart';
import 'package:sakuin/features/wallet/wallet_providers.dart';

/// Buka sheet pelacakan mutasi Saldo Bebas (Audit Selisih Saku) agar pengguna
/// bisa langsung tahu transaksi/alokasi mana yang membuat Saldo Bebas minus atau tidak nol,
/// lalu memperbaikinya dalam 1 ketukan.
Future<bool?> showUnallocatedAuditSheet(
  BuildContext context, {
  required int walletId,
  required String walletName,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.92,
      child: UnallocatedAuditSheet(walletId: walletId, walletName: walletName),
    ),
  );
}

class UnallocatedAuditSheet extends ConsumerStatefulWidget {
  const UnallocatedAuditSheet({
    super.key,
    required this.walletId,
    required this.walletName,
  });

  final int walletId;
  final String walletName;

  @override
  ConsumerState<UnallocatedAuditSheet> createState() =>
      _UnallocatedAuditSheetState();
}

class _UnallocatedAuditSheetState extends ConsumerState<UnallocatedAuditSheet> {
  String _filter = 'all'; // 'all' | 'unassigned_tx' | 'allocation'
  List<UnallocatedAuditEvent> _events = const [];
  bool _loading = true;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await ref
        .read(appDatabaseProvider)
        .getWalletUnallocatedAuditEvents(widget.walletId);
    if (!mounted) return;
    setState(() {
      _events = list;
      _loading = false;
    });
  }

  Future<void> _moveTxToPocket(
    UnallocatedAuditEvent event,
    List<PocketWithBalance> pockets,
  ) async {
    final detail = event.transactionDetail;
    if (detail == null || pockets.isEmpty) return;

    final picked = await showModalBottomSheet<PocketWithBalance>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Pindahkan ke Pos Budget',
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                '${event.title} (${CurrencyFormatter.format(event.delta.abs())}) akan dipindahkan dari Saldo Bebas ke pos yang kamu pilih:',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              for (final p in pockets)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: Color(p.pocket.color)
                        .withValues(alpha: 0.16),
                    child: Icon(
                      AppIcons.fromKey(p.pocket.icon),
                      color: Color(p.pocket.color),
                      size: 18,
                    ),
                  ),
                  title: Text(p.pocket.name),
                  subtitle: Text(
                    'Saldo saat ini: ${CurrencyFormatter.format(p.balance)}',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.pop(ctx, p),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;

    await ref
        .read(appDatabaseProvider)
        .assignTransactionPocket(
          transactionId: detail.transaction.id,
          pocketId: picked.pocket.id,
          isIncomingTransferTarget: event.isIncomingTransferToUnallocated,
        );
    ref.read(transactionRevisionProvider.notifier).state++;
    AppHaptics.medium(ref.read(settingsProvider).hapticsEnabled);
    _changed = true;
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '"${event.title}" dipindahkan ke pos ${picked.pocket.name}',
          ),
        ),
      );
    }
  }

  Future<void> _closeDeficitFromPocket(
    int deficitAmount,
    List<PocketWithBalance> pockets,
  ) async {
    if (deficitAmount <= 0 || pockets.isEmpty) return;
    final picked = await showModalBottomSheet<PocketWithBalance>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tutup Selisih ${CurrencyFormatter.format(deficitAmount)}',
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                'Pilih pos yang ingin dikurangi ${CurrencyFormatter.format(deficitAmount)} agar Saldo Bebas kembali Rp 0 (saldo total dompet tetap sama):',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              for (final p in pockets)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: Color(p.pocket.color)
                        .withValues(alpha: 0.16),
                    child: Icon(
                      AppIcons.fromKey(p.pocket.icon),
                      color: Color(p.pocket.color),
                      size: 18,
                    ),
                  ),
                  title: Text(p.pocket.name),
                  subtitle: Text(
                    '${CurrencyFormatter.format(p.balance)} → ${CurrencyFormatter.format(p.balance - deficitAmount)}',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.pop(ctx, p),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;

    await ref
        .read(walletActionsProvider)
        .allocateOrMovePocket(
          walletId: widget.walletId,
          fromPocketId: picked.pocket.id,
          toPocketId: null,
          amount: deficitAmount,
          note: 'Penyesuaian selisih Saldo Bebas',
        );
    AppHaptics.medium(ref.read(settingsProvider).hapticsEnabled);
    _changed = true;
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Selisih ${CurrencyFormatter.format(deficitAmount)} ditutup dari ${picked.pocket.name}',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final wallets =
        ref.watch(allWalletsWithBalancesProvider).valueOrNull ?? const [];
    final wb = wallets.where((w) => w.wallet.id == widget.walletId).firstOrNull;
    final pockets =
        ref.watch(walletPocketsProvider(widget.walletId)).valueOrNull ??
        const [];
    final totalAllocated = pockets.fold<int>(0, (s, p) => s + p.balance);
    final walletBalance = wb?.balance ?? 0;
    final unallocated = walletBalance - totalAllocated;

    final filtered = _events.where((e) {
      if (_filter == 'unassigned_tx') {
        return e.transactionDetail != null;
      }
      if (_filter == 'allocation') {
        return e.kind == 'allocation' || e.kind == 'initial';
      }
      return true;
    }).toList();

    // Cari kandidat paling dicurigai jika Saldo Bebas minus (mis. nominal transaksi persis sama dengan selisih)
    final exactSuspects = unallocated < 0
        ? _events
              .where(
                (e) =>
                    e.transactionDetail != null &&
                    e.delta < 0 &&
                    e.delta == unallocated,
              )
              .toList()
        : const <UnallocatedAuditEvent>[];

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
                  onPressed: () => Navigator.of(context).pop(_changed),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Lacak Saldo Bebas', style: tt.titleLarge),
                      Text(
                        'Audit selisih alokasi ${widget.walletName}',
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

          // Kartu Diagnosis Singkat
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color:
                    (unallocated < 0
                            ? AppColors.expense(context)
                            : AppColors.income(context))
                        .withValues(alpha: 0.11),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color:
                      (unallocated < 0
                              ? AppColors.expense(context)
                              : AppColors.income(context))
                          .withValues(alpha: 0.35),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Saldo Saku: ${CurrencyFormatter.format(walletBalance)}',
                        style: tt.labelMedium,
                      ),
                      Text(
                        'Total Pos: ${CurrencyFormatter.format(totalAllocated)}',
                        style: tt.labelMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Saldo Bebas Sekarang',
                        style: tt.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      AmountText(
                        amount: unallocated,
                        type: unallocated < 0
                            ? 'expense'
                            : (unallocated > 0 ? 'income' : null),
                        style: tt.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    unallocated < 0
                        ? (exactSuspects.isNotEmpty
                              ? 'Ditemukan ${exactSuspects.length} transaksi tanpa Pos Budget yang nominalnya persis ${CurrencyFormatter.format(unallocated.abs())}! Ketuk "Pindah ke Pos" untuk memperbaikinya.'
                              : 'Biasanya terjadi karena ada pengeluaran/transfer keluar dari ${widget.walletName} yang lupa dipilih Pos Budget-nya, atau alokasi pos melebihi saldo. Cek daftar di bawah atau tutup selisih dari pos.')
                        : (unallocated == 0
                              ? 'Mantap! Seluruh saldo ${widget.walletName} sudah pas 100% terbagi ke pos budget.'
                              : 'Ada ${CurrencyFormatter.format(unallocated)} dana masuk/sisa di Saldo Bebas yang belum dialokasikan ke pos.'),
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),

          // Filter Chips
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ChoiceChip(
                    label: Text('Semua (${_events.length})'),
                    selected: _filter == 'all',
                    onSelected: (_) => setState(() => _filter = 'all'),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text(
                      'Transaksi Tanpa Pos (${_events.where((e) => e.transactionDetail != null).length})',
                    ),
                    selected: _filter == 'unassigned_tx',
                    onSelected: (_) =>
                        setState(() => _filter = 'unassigned_tx'),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Alokasi & Modal'),
                    selected: _filter == 'allocation',
                    onSelected: (_) => setState(() => _filter = 'allocation'),
                  ),
                ],
              ),
            ),
          ),

          // Daftar Riwayat Mutasi Saldo Bebas
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                ? Center(
                    child: Text(
                      'Tidak ada mutasi Saldo Bebas untuk filter ini.',
                      style: tt.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, idx) {
                      final e = filtered[idx];
                      final isExactSuspect =
                          unallocated < 0 &&
                          e.transactionDetail != null &&
                          e.delta == unallocated;
                      final isNegativeUnassigned =
                          unallocated < 0 &&
                          e.transactionDetail != null &&
                          e.delta < 0;
                      final dt = e.timestamp > 0
                          ? DateTime.fromMillisecondsSinceEpoch(e.timestamp)
                                .toLocal()
                          : null;

                      return Card(
                        color: isExactSuspect
                            ? AppColors.expense(context).withValues(alpha: 0.12)
                            : null,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    e.transactionDetail != null
                                        ? Icons.receipt_long_outlined
                                        : (e.kind == 'allocation'
                                              ? Icons.swap_horiz_rounded
                                              : (e.kind == 'initial'
                                                    ? Icons.flag_outlined
                                                    : Icons
                                                          .handshake_outlined)),
                                    size: 20,
                                    color: e.delta < 0
                                        ? AppColors.expense(context)
                                        : AppColors.income(context),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Flexible(
                                              child: Text(
                                                e.title,
                                                style: tt.titleSmall?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (isExactSuspect) ...[
                                              const SizedBox(width: 6),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: AppColors.expense(
                                                    context,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  'Cocok selisih!',
                                                  style: tt.labelSmall
                                                      ?.copyWith(
                                                        color: Colors.white,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          e.subtitle,
                                          style: tt.bodySmall?.copyWith(
                                            color: cs.onSurfaceVariant,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${dt != null ? '${AppDateUtils.formatShortDate(dt)} ${AppDateUtils.formatTime(dt)} • ' : ''}Saldo Bebas jadi ${CurrencyFormatter.format(e.runningBalanceAfter)}',
                                          style: tt.labelSmall?.copyWith(
                                            color: e.runningBalanceAfter < 0
                                                ? AppColors.expense(context)
                                                : cs.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${e.delta >= 0 ? '+' : '-'}${CurrencyFormatter.format(e.delta.abs())}',
                                    style: tt.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: e.delta < 0
                                          ? AppColors.expense(context)
                                          : AppColors.income(context),
                                    ),
                                  ),
                                ],
                              ),
                              if (e.transactionDetail != null) ...[
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    TextButton.icon(
                                      onPressed: () async {
                                        final ok =
                                            await showTransactionFormSheet(
                                              context,
                                              existing: e.transactionDetail,
                                            );
                                        if (ok == true) {
                                          _changed = true;
                                          await _load();
                                        }
                                      },
                                      icon: const Icon(
                                        Icons.edit_outlined,
                                        size: 16,
                                      ),
                                      label: const Text('Edit'),
                                    ),
                                    if (pockets.isNotEmpty) ...[
                                      const SizedBox(width: 6),
                                      FilledButton.tonalIcon(
                                        onPressed: () =>
                                            _moveTxToPocket(e, pockets),
                                        icon: const Icon(
                                          Icons.drive_file_move_outlined,
                                          size: 16,
                                        ),
                                        label: Text(
                                          isNegativeUnassigned
                                              ? 'Pindah ke Pos'
                                              : 'Pilih Pos',
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),

          if (unallocated < 0 && pockets.isNotEmpty)
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
                    onPressed: () =>
                        _closeDeficitFromPocket(unallocated.abs(), pockets),
                    icon: const Icon(Icons.auto_fix_high_rounded),
                    label: Text(
                      'Tutup Selisih ${CurrencyFormatter.format(unallocated.abs())} dari Pos...',
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
