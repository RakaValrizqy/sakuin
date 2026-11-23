import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sakuin/core/db/app_database.dart';
import 'package:sakuin/core/utils/amount_parser.dart';
import 'package:sakuin/core/utils/currency_formatter.dart';
import 'package:sakuin/core/widgets/amount_text.dart';
import 'package:sakuin/core/widgets/category_icon.dart';
import 'package:sakuin/core/widgets/empty_state.dart';
import 'package:sakuin/features/wallet/transfer_sheet.dart';
import 'package:sakuin/features/wallet/wallet_detail_screen.dart';
import 'package:sakuin/features/wallet/wallet_form_sheet.dart';
import 'package:sakuin/features/wallet/wallet_providers.dart';

class WalletListScreen extends ConsumerStatefulWidget {
  const WalletListScreen({super.key});

  @override
  ConsumerState<WalletListScreen> createState() => _WalletListScreenState();
}

class _WalletListScreenState extends ConsumerState<WalletListScreen> {
  bool _showArchived = false;

  Future<void> _showBalanceCorrectionDialog(WalletWithBalance wb) async {
    final ctrl = TextEditingController(
      text: CurrencyFormatter.format(wb.balance, withSymbol: false),
    );
    final confirmed = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Koreksi Saldo ${wb.wallet.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Saldo tercatat: ${CurrencyFormatter.format(wb.balance)}',
              style: Theme.of(ctx).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Saldo nyata sekarang',
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
              final val = AmountParser.parse(ctrl.text);
              if (val != null) Navigator.pop(ctx, val);
            },
            child: const Text('Sesuaikan'),
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saldo berhasil dikoreksi')),
        );
      }
    }
  }

  Future<void> _deleteOrArchive(WalletWithBalance wb) async {
    final deleted = await ref
        .read(walletActionsProvider)
        .deleteOrArchiveWallet(wb.wallet.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          deleted
              ? 'Dompet "${wb.wallet.name}" dihapus'
              : 'Dompet "${wb.wallet.name}" diarsipkan karena sudah memiliki riwayat',
        ),
        action: deleted
            ? null
            : SnackBarAction(
                label: 'Urungkan',
                onPressed: () => ref
                    .read(walletActionsProvider)
                    .setArchived(wb.wallet.id, false),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allWalletsAsync = ref.watch(allWalletsWithBalancesProvider);
    final totalBalance = ref.watch(totalBalanceProvider);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Saku & Dompet'),
        actions: [
          IconButton(
            tooltip: 'Transfer antar dompet',
            icon: const Icon(Icons.swap_horiz_rounded),
            onPressed: () => showTransferSheet(context),
          ),
          IconButton(
            tooltip: _showArchived ? 'Sembunyikan arsip' : 'Tampilkan arsip',
            icon: Icon(
              _showArchived ? Icons.archive_rounded : Icons.archive_outlined,
            ),
            onPressed: () => setState(() => _showArchived = !_showArchived),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showWalletFormSheet(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Dompet Baru'),
      ),
      body: allWalletsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Gagal memuat dompet: $e')),
        data: (allWallets) {
          final active = allWallets.where((w) => !w.wallet.isArchived).toList();
          final archived = allWallets
              .where((w) => w.wallet.isArchived)
              .toList();

          if (active.isEmpty && archived.isEmpty) {
            return EmptyState(
              icon: Icons.account_balance_wallet_outlined,
              title: 'Belum ada saku atau dompet',
              subtitle: 'Buat dompet pertamamu (Tunai, Bank, atau E-Wallet) untuk mulai mencatat keuangan.',
              actionLabel: 'Tambah Dompet',
              onAction: () => showWalletFormSheet(context),
            );
          }

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Card(
                    color: cs.primaryContainer.withValues(alpha: 0.45),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Total Saldo Aktif',
                                  style: tt.bodyMedium?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                AmountText(
                                  amount: totalBalance,
                                  style: tt.headlineMedium,
                                ),
                              ],
                            ),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: active.length >= 2
                                ? () => showTransferSheet(context)
                                : null,
                            icon: const Icon(Icons.swap_horiz_rounded),
                            label: const Text('Transfer'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (active.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Text(
                      'Tarik ikon garis di kanan untuk mengatur urutan dompet',
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                ),
              SliverReorderableList(
                itemCount: active.length,
                onReorderItem: (oldIndex, newIndex) async {
                  final ids = active.map((e) => e.wallet.id).toList();
                  final moved = ids.removeAt(oldIndex);
                  ids.insert(newIndex, moved);
                  await ref.read(walletActionsProvider).reorder(ids);
                },
                itemBuilder: (ctx, index) {
                  final wb = active[index];
                  return Padding(
                    key: ValueKey('wallet_${wb.wallet.id}'),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: Card(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                WalletDetailScreen(walletId: wb.wallet.id),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              CategoryIconBadge(
                                iconKey: wb.wallet.icon,
                                colorValue: wb.wallet.color,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            wb.wallet.name,
                                            style: tt.titleMedium,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (!wb.wallet.includeInTotal) ...[
                                          const SizedBox(width: 6),
                                          Icon(
                                            Icons.visibility_off_outlined,
                                            size: 16,
                                            color: cs.onSurfaceVariant,
                                          ),
                                        ],
                                      ],
                                    ),
                                    Text(
                                      walletTypeLabel(wb.wallet.type),
                                      style: tt.bodySmall?.copyWith(
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              AmountText(
                                amount: wb.balance,
                                style: tt.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              PopupMenuButton<String>(
                                onSelected: (action) {
                                  switch (action) {
                                    case 'edit':
                                      showWalletFormSheet(
                                        context,
                                        existing: wb.wallet,
                                      );
                                    case 'transfer':
                                      showTransferSheet(
                                        context,
                                        initialFromWalletId: wb.wallet.id,
                                      );
                                    case 'adjust':
                                      _showBalanceCorrectionDialog(wb);
                                    case 'delete':
                                      _deleteOrArchive(wb);
                                  }
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'edit',
                                    child: Text('Edit dompet'),
                                  ),
                                  PopupMenuItem(
                                    value: 'transfer',
                                    child: Text('Transfer dari sini'),
                                  ),
                                  PopupMenuItem(
                                    value: 'adjust',
                                    child: Text('Koreksi saldo'),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Arsipkan / Hapus'),
                                  ),
                                ],
                              ),
                              ReorderableDragStartListener(
                                index: index,
                                child: Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: Icon(
                                    Icons.drag_handle_rounded,
                                    color: cs.onSurfaceVariant,
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
              if (_showArchived && archived.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text('Dompet Diarsipkan', style: tt.titleMedium),
                  ),
                ),
                SliverList.builder(
                  itemCount: archived.length,
                  itemBuilder: (_, idx) {
                    final wb = archived[idx];
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Card(
                        child: ListTile(
                          leading: CategoryIconBadge(
                            iconKey: wb.wallet.icon,
                            colorValue: wb.wallet.color,
                          ),
                          title: Text(wb.wallet.name),
                          subtitle: AmountText(amount: wb.balance),
                          trailing: TextButton(
                            onPressed: () => ref
                                .read(walletActionsProvider)
                                .setArchived(wb.wallet.id, false),
                            child: const Text('Aktifkan'),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 96)),
            ],
          );
        },
      ),
    );
  }
}
