import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sakuin/core/services/notification_service.dart';
import 'package:sakuin/core/services/security_service.dart';
import 'package:sakuin/core/services/settings_service.dart';
import 'package:sakuin/core/utils/haptics.dart';
import 'package:sakuin/features/home/home_screen.dart';
import 'package:sakuin/features/recurring/recurring_service.dart';
import 'package:sakuin/features/report/report_screen.dart';
import 'package:sakuin/features/settings/more_screen.dart';
import 'package:sakuin/features/transaction/transaction_form_sheet.dart';
import 'package:sakuin/features/transaction/transaction_list_screen.dart';

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
    // Cold start <= 1 detik: jalankan inisialisasi notifikasi, FLAG_SECURE, dan recurring
    // secara lazy setelah frame pertama selesai dirender.
    WidgetsBinding.instance.addPostFrameCallback((_) => _runPostFirstFrame());
  }

  Future<void> _runPostFirstFrame() async {
    if (_postFrameInitialized) return;
    _postFrameInitialized = true;

    final settings = ref.read(settingsProvider);
    if (settings.secureScreen) {
      await ref.read(securityServiceProvider).setSecureScreenFlag(true);
    }
    await ref.read(notificationServiceProvider).init();
    await ref.read(recurringServiceProvider).processDueRules();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final haptics = ref.watch(settingsProvider.select((s) => s.hapticsEnabled));

    final screens = [
      HomeScreen(onSeeAllTransactions: () => setState(() => _tabIndex = 1)),
      const TransactionListScreen(),
      const ReportScreen(),
      const MoreScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: _tabIndex, children: screens),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: FloatingActionButton(
        tooltip: 'Tambah transaksi',
        onPressed: () {
          AppHaptics.light(haptics);
          showTransactionFormSheet(context);
        },
        shape: const CircleBorder(),
        child: const Icon(Icons.add_rounded, size: 30),
      ),
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        height: 70,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          children: [
            _NavItem(
              icon: Icons.home_outlined,
              selectedIcon: Icons.home_rounded,
              label: 'Beranda',
              selected: _tabIndex == 0,
              color: cs.primary,
              onTap: () => setState(() => _tabIndex = 0),
            ),
            _NavItem(
              icon: Icons.receipt_long_outlined,
              selectedIcon: Icons.receipt_long_rounded,
              label: 'Transaksi',
              selected: _tabIndex == 1,
              color: cs.primary,
              onTap: () => setState(() => _tabIndex = 1),
            ),
            const SizedBox(width: 56), // Ruang untuk FAB tengah
            _NavItem(
              icon: Icons.bar_chart_outlined,
              selectedIcon: Icons.bar_chart_rounded,
              label: 'Laporan',
              selected: _tabIndex == 2,
              color: cs.primary,
              onTap: () => setState(() => _tabIndex = 2),
            ),
            _NavItem(
              icon: Icons.grid_view_outlined,
              selectedIcon: Icons.grid_view_rounded,
              label: 'Lainnya',
              selected: _tabIndex == 3,
              color: cs.primary,
              onTap: () => setState(() => _tabIndex = 3),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = selected ? color : cs.onSurfaceVariant;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(
          height: 56,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(selected ? selectedIcon : icon, color: fg, size: 24),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
