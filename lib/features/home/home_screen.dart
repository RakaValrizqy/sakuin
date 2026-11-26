import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sakuin/core/constants/app_colors.dart';
import 'package:sakuin/core/db/app_database.dart';
import 'package:sakuin/core/db/db_provider.dart';
import 'package:sakuin/core/services/qris_sync_service.dart';
import 'package:sakuin/core/services/settings_service.dart';
import 'package:sakuin/core/utils/currency_formatter.dart';
import 'package:sakuin/core/utils/date_utils.dart';
import 'package:sakuin/core/utils/haptics.dart';
import 'package:sakuin/core/widgets/amount_text.dart';
import 'package:sakuin/features/debt/debt_list_screen.dart';
import 'package:sakuin/features/debt/debt_providers.dart';
import 'package:sakuin/features/qris/qris_inbox_screen.dart';
import 'package:sakuin/features/recurring/recurring_service.dart';
import 'package:sakuin/features/transaction/transaction_form_sheet.dart';
import 'package:sakuin/features/transaction/transaction_providers.dart';
import 'package:sakuin/features/transaction/widgets/transaction_tile.dart';
import 'package:sakuin/features/wallet/wallet_list_screen.dart';
import 'package:sakuin/features/wallet/wallet_providers.dart';

final currentPeriodSummaryProvider = StreamProvider<PeriodSummary>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final startDay = ref.watch(settingsProvider.select((s) => s.periodStartDay));
  final period = AppDateUtils.periodForDate(DateTime.now(), startDay);
  return db.watchPeriodSummary(period.startDayKey, period.endDayKey);
});

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key, required this.onSeeAllTransactions});

  final VoidCallback onSeeAllTransactions;

  Future<void> _onQuickItemTap(
    BuildContext context,
    WidgetRef ref,
    ItemMemoryData item,
  ) async {
    final settings = ref.read(settingsProvider);
    AppHaptics.selection(settings.hapticsEnabled);

    if (settings.quickSaveMode) {
      final actions = ref.read(transactionActionsProvider);
      final saved = await actions.quickSaveItem(item);
      if (saved != null && context.mounted) {
        AppHaptics.medium(settings.hapticsEnabled);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                'Tersimpan: ${item.displayName} (${CurrencyFormatter.format(item.lastAmount)})',
              ),
              action: SnackBarAction(
                label: 'Urungkan',
                onPressed: () => actions.deleteTransaction(saved),
              ),
            ),
          );
      }
    } else {
      await showTransactionFormSheet(context, prefillItem: item);
    }
  }

  Future<void> _deleteWithUndo(
    BuildContext context,
    WidgetRef ref,
    Transaction tx,
  ) async {
    final actions = ref.read(transactionActionsProvider);
    AppHaptics.medium(ref.read(settingsProvider).hapticsEnabled);
    await actions.deleteTransaction(tx);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Transaksi dihapus'),
          action: SnackBarAction(
            label: 'Urungkan',
            onPressed: () => actions.undoDelete([tx]),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totalBalance = ref.watch(totalBalanceProvider);
    final wallets =
        ref.watch(walletsWithBalancesProvider).valueOrNull ?? const [];
    final summary =
        ref.watch(currentPeriodSummaryProvider).valueOrNull ??
        const PeriodSummary(income: 0, expense: 0);
    final quickItems = ref.watch(quickItemsProvider).valueOrNull ?? const [];
    final recentTxs =
        ref.watch(recentTransactionsProvider).valueOrNull ?? const [];
    final debtTotals = ref.watch(debtTotalsProvider);
    final pendingRecurring = ref.watch(pendingRecurringRulesProvider);
    final pendingQris =
        ref.watch(pendingQrisDraftsProvider).valueOrNull ?? const [];

    final hideBalances = ref.watch(
      settingsProvider.select((s) => s.hideBalances),
    );
    final startDay = ref.watch(
      settingsProvider.select((s) => s.periodStartDay),
    );
    final quickSaveMode = ref.watch(
      settingsProvider.select((s) => s.quickSaveMode),
    );
    final period = AppDateUtils.periodForDate(DateTime.now(), startDay);

    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Sakuin'),
            Text(
              period.label,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: hideBalances ? 'Tampilkan saldo' : 'Sembunyikan saldo',
            icon: Icon(
              hideBalances
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
            ),
            onPressed: () => ref
                .read(settingsProvider.notifier)
                .setHideBalances(!hideBalances),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 108),
        children: [
          // 1. Kartu Total Saldo & Ringkasan Periode (animasi hitung naik murah)
          _BalanceSummaryCard(
            totalBalance: totalBalance,
            income: summary.income,
            expense: summary.expense,
            hideBalances: hideBalances,
            periodLabel: period.label,
          ),
          const SizedBox(height: 14),

          // 1b. Antrean Email QRIS dari Gmail Menunggu Review
          if (pendingQris.isNotEmpty) ...[
            Card(
              color: cs.primaryContainer.withValues(alpha: 0.45),
              child: ListTile(
                leading: Icon(Icons.qr_code_2_rounded, color: cs.primary),
                title: Text(
                  '${pendingQris.length} transaksi QRIS menunggu review',
                  style: tt.titleSmall,
                ),
                subtitle: Text(
                  'Ketuk untuk konfirmasi cepat atau pecah jadi beberapa item',
                  style: tt.bodySmall,
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const QrisInboxScreen()),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // 2. Pengingat Transaksi Berulang Menunggu Konfirmasi
          if (pendingRecurring.isNotEmpty) ...[
            for (final rule in pendingRecurring.take(2))
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  color: cs.secondaryContainer.withValues(alpha: 0.45),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.event_repeat_rounded),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Jatuh tempo: ${rule.title}',
                                style: tt.titleSmall,
                              ),
                              Text(
                                CurrencyFormatter.format(rule.amount),
                                style: tt.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () => ref
                              .read(recurringServiceProvider)
                              .skipRuleOccurrence(rule),
                          child: const Text('Lewati'),
                        ),
                        FilledButton.tonal(
                          onPressed: () => ref
                              .read(recurringServiceProvider)
                              .confirmRuleNow(rule),
                          child: const Text('Catat'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],

          // 3. Kartu Akses Cepat: Saku & Hutang
          Row(
            children: [
              Expanded(
                child: Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const WalletListScreen(),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.account_balance_wallet_rounded,
                                size: 20,
                                color: cs.primary,
                              ),
                              const SizedBox(width: 8),
                              Text('Saku', style: tt.titleSmall),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${wallets.length} dompet aktif',
                            style: tt.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            wallets.isEmpty
                                ? 'Ketuk untuk tambah'
                                : wallets
                                      .take(2)
                                      .map((w) => w.wallet.name)
                                      .join(', '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tt.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const DebtListScreen()),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.handshake_rounded,
                                size: 20,
                                color: cs.primary,
                              ),
                              const SizedBox(width: 8),
                              Text('Hutang', style: tt.titleSmall),
                            ],
                          ),
                          const SizedBox(height: 8),
                          AmountText(
                            amount: debtTotals.net,
                            type: debtTotals.net > 0
                                ? 'income'
                                : (debtTotals.net < 0 ? 'expense' : null),
                            signed: debtTotals.net != 0,
                            compact: true,
                            style: tt.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            debtTotals.iOweTotal == 0 &&
                                    debtTotals.theyOweTotal == 0
                                ? 'Tidak ada catatan aktif'
                                : 'Saldo bersih teman',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tt.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // 4. Item Cepat (Anti Input Berulang)
          if (quickItems.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Item Cepat', style: tt.titleMedium),
                Text(
                  quickSaveMode
                      ? 'Ketuk = langsung simpan'
                      : 'Ketuk = isi form',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 48,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: quickItems.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, idx) {
                  final item = quickItems[idx];
                  final chipColor = item.type == 'expense'
                      ? AppColors.expense(context)
                      : AppColors.income(context);
                  return GestureDetector(
                    onLongPress: () async {
                      await ref
                          .read(appDatabaseProvider)
                          .togglePinItemMemory(item.id, !item.isPinned);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              item.isPinned
                                  ? 'Pin dilepas dari "${item.displayName}"'
                                  : '"${item.displayName}" disematkan',
                            ),
                          ),
                        );
                      }
                    },
                    child: ActionChip(
                      avatar: Icon(
                        item.isPinned
                            ? Icons.push_pin_rounded
                            : Icons.bolt_rounded,
                        size: 16,
                        color: chipColor,
                      ),
                      label: Text(
                        '${item.displayName} • ${CurrencyFormatter.formatCompact(item.lastAmount)}',
                      ),
                      onPressed: () => _onQuickItemTap(context, ref, item),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 18),
          ],

          // 5. Transaksi Terbaru
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Transaksi Terbaru', style: tt.titleMedium),
              TextButton(
                onPressed: onSeeAllTransactions,
                child: const Text('Lihat semua'),
              ),
            ],
          ),
          if (recentTxs.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(
                      Icons.receipt_long_outlined,
                      size: 40,
                      color: cs.onSurfaceVariant,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Belum ada transaksi — ketuk + untuk mulai',
                      style: tt.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var i = 0; i < recentTxs.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    TransactionTile(
                      detail: recentTxs[i],
                      onTap: () => showTransactionFormSheet(
                        context,
                        existing: recentTxs[i],
                      ),
                      onDelete: () => _deleteWithUndo(
                        context,
                        ref,
                        recentTxs[i].transaction,
                      ),
                      onDuplicate: () => showTransactionFormSheet(
                        context,
                        duplicateFrom: recentTxs[i],
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _BalanceSummaryCard extends StatelessWidget {
  const _BalanceSummaryCard({
    required this.totalBalance,
    required this.income,
    required this.expense,
    required this.hideBalances,
    required this.periodLabel,
  });

  final int totalBalance;
  final int income;
  final int expense;
  final bool hideBalances;
  final String periodLabel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF133A37), const Color(0xFF0E2528)]
              : [const Color(0xFF0F766E), const Color(0xFF115E59)],
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Total Saldo',
            style: tt.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.82),
            ),
          ),
          const SizedBox(height: 6),
          if (hideBalances)
            Text(
              CurrencyFormatter.masked,
              style: tt.headlineMedium?.copyWith(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            )
          else
            TweenAnimationBuilder<double>(
              tween: Tween<double>(end: totalBalance.toDouble()),
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              builder: (_, value, _) => FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  CurrencyFormatter.format(value.round()),
                  style: tt.headlineMedium?.copyWith(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppColors.incomeDark,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Pemasukan',
                            style: tt.bodySmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        hideBalances
                            ? CurrencyFormatter.masked
                            : CurrencyFormatter.format(income),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.titleMedium?.copyWith(
                          color: AppColors.incomeDark,
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 1,
                  height: 36,
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  color: cs.onPrimary.withValues(alpha: 0.2),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppColors.expenseDark,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Pengeluaran',
                            style: tt.bodySmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        hideBalances
                            ? CurrencyFormatter.masked
                            : CurrencyFormatter.format(expense),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.titleMedium?.copyWith(
                          color: AppColors.expenseDark,
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
