import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sakuin/core/constants/app_colors.dart';
import 'package:sakuin/core/db/app_database.dart';
import 'package:sakuin/core/db/db_provider.dart';
import 'package:sakuin/core/utils/amount_parser.dart';
import 'package:sakuin/core/utils/currency_formatter.dart';
import 'package:sakuin/core/utils/date_utils.dart';
import 'package:sakuin/core/widgets/amount_text.dart';
import 'package:sakuin/core/widgets/category_icon.dart';
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

  @override
  Widget build(BuildContext context) {
    final wallets =
        ref.watch(allWalletsWithBalancesProvider).valueOrNull ?? const [];
    final wb = wallets.where((e) => e.wallet.id == widget.walletId).firstOrNull;
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    if (wb == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Detail Dompet')),
        body: const Center(child: Text('Dompet tidak ditemukan')),
      );
    }

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
          padding: const EdgeInsets.all(16),
          children: [
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
                        Column(
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
              ? 'Transfer dari ${detail.wallet.name}'
              : 'Transfer ke ${detail.toWallet?.name ?? "-"}')
        : (tx.itemName ?? detail.category?.name ?? 'Transaksi');

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
      subtitle: Text(AppDateUtils.formatDayDate(date)),
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
