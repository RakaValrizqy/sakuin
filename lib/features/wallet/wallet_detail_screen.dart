import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sakuin/core/constants/app_colors.dart';
import 'package:sakuin/core/constants/app_icons.dart';
import 'package:sakuin/core/db/app_database.dart';
import 'package:sakuin/core/db/db_provider.dart';
import 'package:sakuin/core/utils/amount_parser.dart';
import 'package:sakuin/core/utils/currency_formatter.dart';
import 'package:sakuin/core/utils/date_utils.dart';
import 'package:sakuin/core/utils/thousands_input_formatter.dart';
import 'package:sakuin/core/widgets/amount_text.dart';
import 'package:sakuin/core/widgets/category_icon.dart';
import 'package:sakuin/features/wallet/pocket_sheets.dart';
import 'package:sakuin/features/wallet/transfer_sheet.dart';
import 'package:sakuin/features/wallet/wallet_form_sheet.dart';
import 'package:sakuin/features/wallet/wallet_providers.dart';

class WalletDetailScreen extends ConsumerStatefulWidget {
  const WalletDetailScreen({super.key, required this.walletId});

  final int walletId;

  @override
  ConsumerState<WalletDetailScreen> createState() => _WalletDetailScreenState();
}

class _WalletDetailScreenState extends ConsumerState<WalletDetailScreen> {
  List<TransactionDetail> _transactions = [];
  List<DailyTrendPoint> _trend = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final db = ref.read(appDatabaseProvider);
    final now = DateTime.now();
    final start = now.subtract(const Duration(days: 13));
    final txs = await db.fetchTransactionsPage(
      limit: 50,
      walletId: widget.walletId,
    );
    final trend = await db.getDailyTrend(
      startDayKey: AppDateUtils.toDayKey(start),
      endDayKey: AppDateUtils.toDayKey(now),
      walletId: widget.walletId,
    );
    if (!mounted) return;
    setState(() {
      _transactions = txs;
      _trend = trend;
      _loading = false;
    });
  }

  Future<void> _adjustBalance(WalletWithBalance wb) async {
    final ctrl = TextEditingController(
      text: CurrencyFormatter.format(wb.balance, withSymbol: false),
    );
    final confirmed = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Koreksi Saldo ${wb.wallet.name}'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [ThousandsSeparatorInputFormatter()],
          decoration: const InputDecoration(
            labelText: 'Saldo nyata sekarang',
            prefixText: 'Rp ',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              final val = AmountParser.parse(ctrl.text);
              if (val != null) Navigator.pop(ctx, val);
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    ctrl.dispose();

    if (confirmed != null) {
      await ref
          .read(walletActionsProvider)
          .adjustBalance(
            walletId: wb.wallet.id,
            currentBalance: wb.balance,
            actualBalance: confirmed,
          );
      await _loadData();
    }
  }

  Future<void> _deletePocket(PocketWithBalance pb) async {
    final deleted = await ref
        .read(walletActionsProvider)
        .deleteOrArchivePocket(widget.walletId, pb.pocket.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          deleted
              ? 'Pos "${pb.pocket.name}" dihapus (sisa saldo dikembalikan ke Saldo Bebas)'
              : 'Pos "${pb.pocket.name}" diarsipkan (sisa saldo dikembalikan ke Saldo Bebas)',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wallets =
        ref.watch(allWalletsWithBalancesProvider).valueOrNull ?? const [];
    final wb = wallets.where((e) => e.wallet.id == widget.walletId).firstOrNull;
    final pockets =
        ref.watch(walletPocketsProvider(widget.walletId)).valueOrNull ??
        const [];
    final recentAllocations =
        ref
            .watch(walletRecentAllocationsProvider(widget.walletId))
            .valueOrNull ??
        const [];
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    if (wb == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Detail Dompet')),
        body: const Center(child: Text('Dompet tidak ditemukan')),
      );
    }

    var totalAllocated = 0;
    for (final p in pockets) {
      totalAllocated += p.balance;
    }
    final unallocated = wb.balance - totalAllocated;
    final pocketNameById = {
      for (final p in pockets) p.pocket.id: p.pocket.name,
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(wb.wallet.name),
        actions: [
          IconButton(
            tooltip: 'Edit dompet',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => showWalletFormSheet(context, existing: wb.wallet),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            // Kartu Saldo Utama Saku
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CategoryIconBadge(
                          iconKey: wb.wallet.icon,
                          colorValue: wb.wallet.color,
                          size: 48,
                          iconSize: 24,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                walletTypeLabel(wb.wallet.type),
                                style: tt.bodyMedium?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                              AmountText(
                                amount: wb.balance,
                                style: tt.headlineMedium,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final ok = await showTransferSheet(
                                context,
                                initialFromWalletId: wb.wallet.id,
                              );
                              if (ok == true) _loadData();
                            },
                            icon: const Icon(Icons.swap_horiz_rounded),
                            label: const Text('Transfer'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _adjustBalance(wb),
                            icon: const Icon(Icons.tune_rounded),
                            label: const Text('Koreksi Saldo'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),

            // Bagian Pembagian Budget (Pos di dalam Saku)
            Row(
              children: [
                Expanded(
                  child: Text('Pembagian Budget Saku', style: tt.titleMedium),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => showPocketFormSheet(
                    context,
                    walletId: wb.wallet.id,
                    unallocatedBalance: unallocated,
                  ),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Pos'),
                ),
              ],
            ),
            if (pockets.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => showBulkAllocateSheet(
                        context,
                        walletId: wb.wallet.id,
                        walletName: wb.wallet.name,
                        totalWalletBalance: wb.balance,
                        pockets: pockets,
                      ),
                      icon: const Icon(Icons.tune_rounded, size: 18),
                      label: const Text('Atur Semua Alokasi'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => showPocketAllocateSheet(
                      context,
                      walletId: wb.wallet.id,
                      walletName: wb.wallet.name,
                      unallocatedBalance: unallocated,
                      pockets: pockets,
                    ),
                    icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                    label: const Text('Pindah'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Bar proporsi visual jika ada pos
                    if (pockets.isNotEmpty && wb.balance > 0) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: SizedBox(
                          height: 10,
                          child: Row(
                            children: [
                              for (final p in pockets)
                                if (p.balance > 0)
                                  Expanded(
                                    flex: p.balance,
                                    child: Container(
                                      color: Color(p.pocket.color),
                                    ),
                                  ),
                              if (unallocated > 0)
                                Expanded(
                                  flex: unallocated,
                                  child: Container(
                                    color: cs.surfaceContainerHighest,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Baris Saldo Bebas (Belum Dialokasikan)
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest.withValues(
                              alpha: 0.7,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.account_balance_wallet_outlined,
                            color: cs.onSurfaceVariant,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Saldo Bebas', style: tt.titleSmall),
                              Text(
                                unallocated < 0
                                    ? 'Alokasi melebihi saldo saku'
                                    : 'Belum dialokasikan ke pos budget',
                                style: tt.bodySmall?.copyWith(
                                  color: unallocated < 0
                                      ? AppColors.expense(context)
                                      : cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        AmountText(
                          amount: unallocated,
                          type: unallocated < 0 ? 'expense' : null,
                          style: tt.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),

                    if (pockets.isEmpty) ...[
                      const Divider(height: 22),
                      Text(
                        'Bagi saldo ${wb.wallet.name} jadi beberapa pos budget tanpa bikin saku baru. Ketuk pintasan cepat:',
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final preset in pocketPresets.take(4))
                            ActionChip(
                              avatar: Icon(
                                AppIcons.fromKey(preset.icon),
                                size: 16,
                                color: Color(preset.color),
                              ),
                              label: Text('+ ${preset.name}'),
                              onPressed: () => showPocketFormSheet(
                                context,
                                walletId: wb.wallet.id,
                                unallocatedBalance: unallocated,
                                initialPreset: preset,
                              ),
                            ),
                        ],
                      ),
                    ] else ...[
                      const Divider(height: 22),
                      for (var i = 0; i < pockets.length; i++) ...[
                        if (i > 0) const Divider(height: 16),
                        _PocketRow(
                          item: pockets[i],
                          walletTotalBalance: wb.balance,
                          onAllocate: () => showPocketAllocateSheet(
                            context,
                            walletId: wb.wallet.id,
                            walletName: wb.wallet.name,
                            unallocatedBalance: unallocated,
                            pockets: pockets,
                            initialFromPocketId: unallocated > 0
                                ? null
                                : pockets[i].pocket.id,
                            initialToPocketId: unallocated > 0
                                ? pockets[i].pocket.id
                                : null,
                          ),
                          onEdit: () => showPocketFormSheet(
                            context,
                            walletId: wb.wallet.id,
                            unallocatedBalance: unallocated,
                            existing: pockets[i],
                          ),
                          onDelete: () => _deletePocket(pockets[i]),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),

            if (recentAllocations.isNotEmpty) ...[
              const SizedBox(height: 14),
              ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 4),
                title: Text(
                  'Riwayat Alokasi Budget (${recentAllocations.length})',
                  style: tt.titleSmall,
                ),
                children: [
                  Card(
                    child: Column(
                      children: [
                        for (
                          var i = 0;
                          i < recentAllocations.take(8).length;
                          i++
                        ) ...[
                          if (i > 0) const Divider(height: 1),
                          Builder(
                            builder: (_) {
                              final alloc = recentAllocations[i];
                              final fromName = alloc.fromPocketId == null
                                  ? 'Saldo Bebas'
                                  : (pocketNameById[alloc.fromPocketId] ??
                                        'Pos');
                              final toName = alloc.toPocketId == null
                                  ? 'Saldo Bebas'
                                  : (pocketNameById[alloc.toPocketId] ?? 'Pos');
                              final dt = DateTime.fromMillisecondsSinceEpoch(
                                alloc.createdAt,
                              ).toLocal();
                              return ListTile(
                                dense: true,
                                leading: const Icon(
                                  Icons.swap_horiz_rounded,
                                  size: 20,
                                ),
                                title: Text('$fromName → $toName'),
                                subtitle: Text(
                                  '${AppDateUtils.formatShortDate(dt)}${alloc.note.isNotEmpty ? ' • ${alloc.note}' : ''}',
                                ),
                                trailing: AmountText(
                                  amount: alloc.amount,
                                  type: 'transfer',
                                  style: tt.titleSmall,
                                ),
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),

            // Mini chart 14 hari terakhir
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Aktivitas 14 Hari Terakhir', style: tt.titleMedium),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 110,
                      child: RepaintBoundary(
                        child: CustomPaint(
                          size: Size.infinite,
                          painter: _WalletMiniBarPainter(
                            points: _trend,
                            incomeColor: AppColors.income(context),
                            expenseColor: AppColors.expense(context),
                            gridColor: cs.outlineVariant.withValues(alpha: 0.4),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            Text('Riwayat Transaksi', style: tt.titleMedium),
            const SizedBox(height: 8),

            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_transactions.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      'Belum ada transaksi di dompet ini',
                      style: tt.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              )
            else
              Card(
                child: Column(
                  children: [
                    for (var i = 0; i < _transactions.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      _WalletTxRow(
                        detail: _transactions[i],
                        currentWalletId: widget.walletId,
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PocketRow extends StatelessWidget {
  const _PocketRow({
    required this.item,
    required this.walletTotalBalance,
    required this.onAllocate,
    required this.onEdit,
    required this.onDelete,
  });

  final PocketWithBalance item;
  final int walletTotalBalance;
  final VoidCallback onAllocate;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final progress = item.targetProgress;
    final sharePct = walletTotalBalance > 0 && item.balance > 0
        ? ((item.balance / walletTotalBalance) * 100).round()
        : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CategoryIconBadge(
              iconKey: item.pocket.icon,
              colorValue: item.pocket.color,
              size: 40,
              iconSize: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          item.pocket.name,
                          style: tt.titleMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (sharePct > 0) ...[
                        const SizedBox(width: 6),
                        Text(
                          '$sharePct%',
                          style: tt.labelSmall?.copyWith(
                            color: Color(item.pocket.color),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (item.pocket.targetAmount != null &&
                      item.pocket.targetAmount! > 0)
                    Text(
                      'Target ${CurrencyFormatter.format(item.pocket.targetAmount!)}',
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                ],
              ),
            ),
            AmountText(
              amount: item.balance,
              type: item.balance < 0 ? 'expense' : null,
              style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        if (progress != null) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              color: Color(item.pocket.color),
              backgroundColor: cs.surfaceContainerHighest,
            ),
          ),
        ],
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton.icon(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: onAllocate,
              icon: const Icon(Icons.swap_horiz_rounded, size: 16),
              label: const Text('Pindah'),
            ),
            TextButton.icon(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Atur'),
            ),
            IconButton(
              tooltip: 'Hapus / Arsipkan pos',
              visualDensity: VisualDensity.compact,
              icon: Icon(
                Icons.delete_outline_rounded,
                size: 18,
                color: cs.onSurfaceVariant,
              ),
              onPressed: onDelete,
            ),
          ],
        ),
      ],
    );
  }
}

class _WalletTxRow extends StatelessWidget {
  const _WalletTxRow({required this.detail, required this.currentWalletId});

  final TransactionDetail detail;
  final int currentWalletId;

  @override
  Widget build(BuildContext context) {
    final tx = detail.transaction;
    final date = DateTime.fromMillisecondsSinceEpoch(tx.occurredAt).toLocal();
    final isTransferIn =
        tx.type == 'transfer' && tx.toWalletId == currentWalletId;
    final title = tx.type == 'transfer'
        ? (isTransferIn
              ? 'Transfer dari ${detail.wallet.name}${detail.toPocketName != null ? ' → ${detail.toPocketName}' : ''}'
              : 'Transfer ke ${detail.toWallet?.name ?? "-"}${detail.toPocketName != null ? ' (${detail.toPocketName})' : ''}')
        : (tx.itemName ?? detail.category?.name ?? 'Transaksi');

    final pocketTag = tx.type != 'transfer' && detail.pocketName != null
        ? ' • Pos ${detail.pocketName}'
        : '';

    return ListTile(
      leading: CategoryIconBadge(
        iconKey: tx.type == 'transfer'
            ? 'admin_fee'
            : (detail.category?.icon ?? 'other'),
        colorValue: tx.type == 'transfer'
            ? AppColors.transfer(context).toARGB32()
            : (detail.category?.color ?? 0xFF64748B),
        size: 40,
        iconSize: 20,
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${AppDateUtils.formatDayDate(date)}$pocketTag'),
      trailing: AmountText(
        amount: tx.amount,
        type: tx.type == 'transfer'
            ? (isTransferIn ? 'income' : 'transfer')
            : tx.type,
        signed: true,
      ),
    );
  }
}

class _WalletMiniBarPainter extends CustomPainter {
  _WalletMiniBarPainter({
    required this.points,
    required this.incomeColor,
    required this.expenseColor,
    required this.gridColor,
  });

  final List<DailyTrendPoint> points;
  final Color incomeColor;
  final Color expenseColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    final basePaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height - 4),
      Offset(size.width, size.height - 4),
      basePaint,
    );

    if (points.isEmpty) return;

    var maxVal = 1;
    for (final p in points) {
      if (p.income > maxVal) maxVal = p.income;
      if (p.expense > maxVal) maxVal = p.expense;
    }

    final slotWidth = size.width / points.length;
    final barWidth = (slotWidth * 0.34).clamp(4.0, 14.0);
    final usableHeight = size.height - 12;

    final incPaint = Paint()..color = incomeColor;
    final expPaint = Paint()..color = expenseColor;

    for (var i = 0; i < points.length; i++) {
      final pt = points[i];
      final cx = i * slotWidth + slotWidth / 2;
      if (pt.income > 0) {
        final h = (pt.income / maxVal) * usableHeight;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(cx - barWidth - 1, size.height - 4 - h, barWidth, h),
            const Radius.circular(3),
          ),
          incPaint,
        );
      }
      if (pt.expense > 0) {
        final h = (pt.expense / maxVal) * usableHeight;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(cx + 1, size.height - 4 - h, barWidth, h),
            const Radius.circular(3),
          ),
          expPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _WalletMiniBarPainter oldDelegate) =>
      oldDelegate.points != points;
}
