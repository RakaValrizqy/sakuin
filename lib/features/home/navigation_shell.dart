import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sakuin/core/services/notification_service.dart';
import 'package:sakuin/core/services/qris_sync_service.dart';
import 'package:sakuin/core/services/security_service.dart';
import 'package:sakuin/core/services/settings_service.dart';
import 'package:sakuin/core/services/update_service.dart';
import 'package:sakuin/core/utils/haptics.dart';
import 'package:sakuin/features/home/home_screen.dart';
import 'package:sakuin/features/recurring/recurring_service.dart';
import 'package:sakuin/features/report/report_screen.dart';
import 'package:sakuin/features/settings/more_screen.dart';
import 'package:sakuin/features/settings/update_sheet.dart';
import 'package:sakuin/features/transaction/transaction_form_sheet.dart';
import 'package:sakuin/features/wallet/wallet_list_screen.dart';

class NavigationShell extends ConsumerStatefulWidget {
  const NavigationShell({super.key});

  @override
  ConsumerState<NavigationShell> createState() => _NavigationShellState();
}

class _NavigationShellState extends ConsumerState<NavigationShell> {
  int _tabIndex = 0;
  bool _postFrameInitialized = false;

  @override
  void initState() {
    super.initState();
    // Cold start <= 1 detik: jalankan inisialisasi notifikasi, FLAG_SECURE, recurring,
    // QRIS Gmail sync, dan cek update secara lazy setelah frame pertama selesai dirender.
    WidgetsBinding.instance.addPostFrameCallback((_) => _runPostFirstFrame());
  }

  Future<void> _runPostFirstFrame() async {
    if (_postFrameInitialized) return;
    _postFrameInitialized = true;

    final settings = await ref.read(settingsProvider.notifier).ensureLoaded();
    if (settings.secureScreen) {
      await ref.read(securityServiceProvider).setSecureScreenFlag(true);
    }
    await ref.read(notificationServiceProvider).init();
    await ref.read(recurringServiceProvider).processDueRules();

    final updater = ref.read(updateServiceProvider);
    await updater.cleanupOldApks();

    final qrisSvc = ref.read(qrisSyncServiceProvider);
    final qrisCfg = await qrisSvc.loadConfig();
    if (qrisCfg.isConfigured && qrisCfg.autoSyncOnOpen) {
      qrisSvc.syncNow();
    }

    if (settings.autoCheckUpdate) {
      final result = await updater.checkForUpdate();
      final update = result.availableUpdate;
      if (mounted &&
          update != null &&
          update.tagName != settings.skippedUpdateTag) {
        await showUpdateAvailableSheet(
          context,
          currentVersion: result.currentVersion,
          update: update,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final haptics = ref.watch(settingsProvider.select((s) => s.hapticsEnabled));
    final pendingQrisCount =
        ref.watch(pendingQrisDraftsProvider).valueOrNull?.length ?? 0;

    final screens = const [
      HomeScreen(),
      WalletListScreen(),
      ReportScreen(),
      MoreScreen(),
    ];

    // Tampilkan FAB "+ Catat" di Beranda saja agar tidak menimpa
    // FAB milik tab Dompet ("+ Dompet Baru").
    final showAddTransactionFab = _tabIndex == 0;

    return Scaffold(
      body: IndexedStack(index: _tabIndex, children: screens),
      floatingActionButton: showAddTransactionFab
          ? FloatingActionButton.extended(
              tooltip: 'Tambah transaksi',
              onPressed: () {
                AppHaptics.light(haptics);
                showTransactionFormSheet(context);
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text('Catat'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (idx) {
          AppHaptics.selection(haptics);
          setState(() => _tabIndex = idx);
        },
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Beranda',
          ),
          const NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet_rounded),
            label: 'Dompet',
          ),
          const NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart_rounded),
            label: 'Laporan',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: pendingQrisCount > 0,
              label: Text('$pendingQrisCount'),
              child: const Icon(Icons.grid_view_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: pendingQrisCount > 0,
              label: Text('$pendingQrisCount'),
              child: const Icon(Icons.grid_view_rounded),
            ),
            label: 'Lainnya',
          ),
        ],
      ),
    );
  }
}
