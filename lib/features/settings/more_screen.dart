import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sakuin/core/services/qris_sync_service.dart';
import 'package:sakuin/core/services/update_service.dart';
import 'package:sakuin/features/budget/budget_screen.dart';
import 'package:sakuin/features/category/category_list_screen.dart';
import 'package:sakuin/features/debt/debt_list_screen.dart';
import 'package:sakuin/features/qris/qris_inbox_screen.dart';
import 'package:sakuin/features/receipt/receipt_scanner_screen.dart';
import 'package:sakuin/features/recurring/recurring_screen.dart';
import 'package:sakuin/features/settings/backup_screen.dart';
import 'package:sakuin/features/settings/settings_screen.dart';
import 'package:sakuin/features/transaction/transaction_list_screen.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingQrisCount =
        ref.watch(pendingQrisDraftsProvider).valueOrNull?.length ?? 0;
    final appVersion = ref.watch(appVersionInfoProvider).valueOrNull;
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    void push(Widget screen) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Lainnya')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.receipt_long_rounded),
                  title: const Text('Transaksi'),
                  subtitle: const Text(
                    'Riwayat lengkap, cari, filter, & pecah item',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => push(const TransactionListScreen()),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.handshake_rounded),
                  title: const Text('Hutang & Piutang'),
                  subtitle: const Text(
                    'Pinjaman, cicilan, & saldo bersih per teman',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => push(const DebtListScreen()),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.document_scanner_rounded),
                  title: const Text('Scan Struk & Split Bill'),
                  subtitle: const Text(
                    'Foto / share struk, bagi item per orang, & catat piutang',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => push(const ReceiptScannerScreen()),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.qr_code_2_rounded),
                  title: const Text('Auto QRIS (Gmail)'),
                  subtitle: const Text(
                    'Tarik pengeluaran QRIS dari email Gmail & pecah item',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (pendingQrisCount > 0)
                        Badge.count(count: pendingQrisCount),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right_rounded),
                    ],
                  ),
                  onTap: () => push(const QrisInboxScreen()),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.pie_chart_outline_rounded),
                  title: const Text('Anggaran'),
                  subtitle: const Text('Batas belanja bulanan & peringatan'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => push(const BudgetScreen()),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.category_outlined),
                  title: const Text('Kategori'),
                  subtitle: const Text('Ubah atau tambah kategori kustom'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => push(const CategoryListScreen()),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.event_repeat_rounded),
                  title: const Text('Transaksi Berulang'),
                  subtitle: const Text('Gaji, langganan, cicilan otomatis'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => push(const RecurringScreen()),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.backup_outlined),
                  title: const Text('Backup & Restore'),
                  subtitle: const Text(
                    'Simpan ke Google Drive / pulihkan data',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => push(const BackupScreen()),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.settings_outlined),
                  title: const Text('Pengaturan'),
                  subtitle: const Text(
                    'Tanggal periode, tema, PIN & biometrik, pembaruan',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => push(const SettingsScreen()),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: Text(
              appVersion != null
                  ? 'Sakuin v${appVersion.versionName} (Build ${appVersion.versionCode})'
                  : 'Sakuin',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
