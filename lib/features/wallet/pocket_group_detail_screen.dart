import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sakuin/core/constants/app_colors.dart';
import 'package:sakuin/core/db/app_database.dart';
import 'package:sakuin/core/db/db_provider.dart';
import 'package:sakuin/core/services/settings_service.dart';
import 'package:sakuin/core/utils/amount_parser.dart';
import 'package:sakuin/core/utils/currency_formatter.dart';
import 'package:sakuin/core/utils/date_utils.dart';
import 'package:sakuin/core/utils/spending_insights_calculator.dart';
import 'package:sakuin/core/utils/thousands_input_formatter.dart';
import 'package:sakuin/core/widgets/amount_text.dart';
import 'package:sakuin/core/widgets/category_icon.dart';
import 'package:sakuin/core/widgets/nominal_shortcut_bar.dart';
import 'package:sakuin/features/transaction/transaction_form_sheet.dart';
import 'package:sakuin/features/transaction/transaction_providers.dart';
import 'package:sakuin/features/transaction/widgets/transaction_tile.dart';
import 'package:sakuin/features/wallet/wallet_detail_screen.dart';
import 'package:sakuin/features/wallet/wallet_providers.dart';

class PocketGroupDetailScreen extends ConsumerStatefulWidget {
  const PocketGroupDetailScreen({
    super.key,
    required this.normalizedKey,
    required this.initialTitle,
    required this.initialIcon,
    required this.initialColor,
  });

  final String normalizedKey;
  final String initialTitle;
  final String initialIcon;
  final int initialColor;

  @override
  ConsumerState<PocketGroupDetailScreen> createState() =>
      _PocketGroupDetailScreenState();
}

class _PocketGroupDetailScreenState
    extends ConsumerState<PocketGroupDetailScreen> {
  Future<void> _editGroupTarget(
    List<PocketWithBalance> groupPockets,
    int currentTarget,
  ) async {
    if (groupPockets.isEmpty) return;
    final ctrl = TextEditingController(
      text: currentTarget > 0
          ? CurrencyFormatter.format(currentTarget, withSymbol: false)
          : '',
    );
    final haptics = ref.read(settingsProvider).hapticsEnabled;

    final result = await showDialog<int?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Target Pos ${widget.initialTitle}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Atur target saldo gabungan untuk pos ini (kosongkan atau isi 0 untuk menghapus target).',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [ThousandsSeparatorInputFormatter()],
              decoration: const InputDecoration(
                labelText: 'Target saldo',
                prefixText: 'Rp ',
                hintText: 'Contoh: 5.000.000',
              ),
            ),
            const SizedBox(height: 8),
            NominalShortcutBar(controller: ctrl, hapticsEnabled: haptics),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, -1),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              final parsed = AmountParser.parse(ctrl.text) ?? 0;
              Navigator.pop(ctx, parsed > 0 ? parsed : 0);
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    ctrl.dispose();

    if (result == null || result == -1) return;
    final db = ref.read(appDatabaseProvider);
    // Simpan target gabungan pada pos pertama & bersihkan target duplikat di pos lain pada grup ini
    // agar angka target gabungan selalu tepat sesuai input pengguna.
    final primaryId = groupPockets.first.pocket.id;
    for (final p in groupPockets) {
      await db.updatePocketTargetAmount(
        p.pocket.id,
        p.pocket.id == primaryId ? (result > 0 ? result : null) : null,
      );
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result > 0
                ? 'Target diatur ke ${CurrencyFormatter.format(result)}'
                : 'Target dihapus',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final allPockets =
        ref.watch(allActivePocketsProvider).valueOrNull ?? const [];
    final wallets =
        ref.watch(walletsWithBalancesProvider).valueOrNull ?? const [];
    final startDay = ref.watch(
      settingsProvider.select((s) => s.periodStartDay),
    );
    final revision = ref.watch(transactionRevisionProvider);

    final walletById = {for (final w in wallets) w.wallet.id: w};
    final groupPockets = allPockets
        .where(
          (p) =>
              SpendingInsightsCalculator.normalizePocketGroupKey(
                p.pocket.name,
              ) ==
              widget.normalizedKey,
        )
        .toList();

    final pocketIds = groupPockets.map((p) => p.pocket.id).toSet();
    final totalBalance = groupPockets.fold<int>(0, (s, p) => s + p.balance);
    final totalTarget = groupPockets.fold<int>(
      0,
      (s, p) => s + (p.pocket.targetAmount ?? 0),
    );
    final title = groupPockets.isNotEmpty
        ? groupPockets.first.pocket.name.trim()
        : widget.initialTitle;
    final iconKey = groupPockets.isNotEmpty
        ? groupPockets.first.pocket.icon
        : widget.initialIcon;
    final colorValue = groupPockets.isNotEmpty
        ? groupPockets.first.pocket.color
        : widget.initialColor;

    final period = AppDateUtils.periodForDate(DateTime.now(), startDay);
    final db = ref.read(appDatabaseProvider);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Pos $title'),
        actions: [
          IconButton(
            tooltip: 'Atur target pos',
            icon: const Icon(Icons.flag_outlined),
            onPressed: groupPockets.isEmpty
                ? null
                : () => _editGroupTarget(groupPockets, totalTarget),
          ),
        ],
      ),
      body: FutureBuilder<List<TransactionDetail>>(
        key: ValueKey('pocket_group_${widget.normalizedKey}_$revision'),
        future: db.fetchTransactionsForPocketIds(pocketIds, limit: 150),
        builder: (context, snapshot) {
          final txs = snapshot.data ?? const [];

          var periodExpense = 0;
          var periodIncome = 0;
          for (final d in txs) {
            final tx = d.transaction;
            if (tx.dayKey < period.startDayKey ||
                tx.dayKey > period.endDayKey) {
              continue;
            }
            if (tx.type == 'expense' &&
                tx.pocketId != null &&
                pocketIds.contains(tx.pocketId)) {
              periodExpense += tx.amount;
            } else if (tx.type == 'income' &&
                tx.pocketId != null &&
                pocketIds.contains(tx.pocketId)) {
              periodIncome += tx.amount;
            } else if (tx.type == 'transfer') {
              if (tx.pocketId != null && pocketIds.contains(tx.pocketId)) {
                periodExpense += tx.fee;
              }
            }
          }

          final progress = totalTarget > 0
              ? (totalBalance / totalTarget).clamp(0.0, 1.0)
              : null;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: [
              // 1. Kartu Ringkasan Saldo Gabungan & Target
              Card(
                color: Color(colorValue).withValues(alpha: 0.14),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CategoryIconBadge(
                            iconKey: iconKey,
                            colorValue: colorValue,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  groupPockets.length > 1
                                      ? '$title (${groupPockets.length} saku)'
                                      : title,
                                  style: tt.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  'Total saldo gabungan saat ini',
                                  style: tt.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      AmountText(
                        amount: totalBalance,
                        style: tt.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (progress != null) ...[
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Target: ${CurrencyFormatter.format(totalTarget)}',
                              style: tt.labelMedium,
                            ),
                            Text(
                              '${(progress * 100).round()}%',
                              style: tt.labelMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: Color(colorValue),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 8,
                            color: Color(colorValue),
                            backgroundColor: cs.surfaceContainerHighest,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          totalBalance >= totalTarget
                              ? 'Target tercapai!'
                              : 'Kurang ${CurrencyFormatter.format(totalTarget - totalBalance)} lagi',
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ] else ...[
                        const SizedBox(height: 8),
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: () =>
                              _editGroupTarget(groupPockets, totalTarget),
                          icon: const Icon(Icons.flag_outlined, size: 16),
                          label: const Text('Atur target saldo (opsional)'),
                        ),
                      ],
                      const Divider(height: 22),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Terpakai (${period.label})',
                                  style: tt.labelSmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                AmountText(
                                  amount: periodExpense,
                                  type: 'expense',
                                  style: tt.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.expense(context),
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
                                  'Pemasukan Langsung',
                                  style: tt.labelSmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                AmountText(
                                  amount: periodIncome,
                                  type: 'income',
                                  style: tt.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.income(context),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 2. Rincian per Saku
              Text('Rincian per Saku', style: tt.titleMedium),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: [
                    for (var i = 0; i < groupPockets.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      Builder(
                        builder: (ctx) {
                          final p = groupPockets[i];
                          final wb = walletById[p.pocket.walletId];
                          return ListTile(
                            leading: CategoryIconBadge(
                              iconKey: wb?.wallet.icon ?? 'wallet',
                              colorValue: wb?.wallet.color ?? colorValue,
                              size: 38,
                              iconSize: 18,
                            ),
                            title: Text(wb?.wallet.name ?? 'Saku'),
                            subtitle: Text(
                              'Ketuk untuk kelola pos di saku ini',
                              style: tt.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                AmountText(
                                  amount: p.balance,
                                  style: tt.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(Icons.chevron_right_rounded),
                              ],
                            ),
                            onTap: wb == null
                                ? null
                                : () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => WalletDetailScreen(
                                        walletId: wb.wallet.id,
                                      ),
                                    ),
                                  ),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // 3. Riwayat Transaksi Pos Ini
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Riwayat Transaksi Pos', style: tt.titleMedium),
                  Text(
                    '${txs.length} transaksi',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (snapshot.connectionState == ConnectionState.waiting &&
                  txs.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (txs.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Center(
                      child: Text(
                        'Belum ada transaksi yang memakai pos $title.',
                        style: tt.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                )
              else
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (var i = 0; i < txs.length; i++) ...[
                        if (i > 0) const Divider(height: 1),
                        TransactionTile(
                          detail: txs[i],
                          enableSwipe: false,
                          onTap: () => showTransactionFormSheet(
                            context,
                            existing: txs[i],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
