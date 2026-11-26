import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sakuin/core/services/notification_service.dart';
import 'package:sakuin/core/services/security_service.dart';
import 'package:sakuin/core/services/settings_service.dart';
import 'package:sakuin/core/services/update_service.dart';
import 'package:sakuin/features/settings/pin_lock_screen.dart';
import 'package:sakuin/features/settings/update_sheet.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  String _themeLabel(ThemeMode m) => switch (m) {
    ThemeMode.light => 'Terang',
    ThemeMode.dark => 'Gelap',
    ThemeMode.system => 'Ikuti sistem',
  };

  String _autoLockLabel(int sec) => switch (sec) {
    0 => 'Langsung saat keluar',
    60 => 'Setelah 1 menit',
    300 => 'Setelah 5 menit',
    _ => 'Langsung saat keluar',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _SectionTitle('Periode & Input Cepat'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.calendar_month_rounded),
                  title: const Text('Tanggal mulai periode'),
                  subtitle: Text(
                    'Tanggal ${settings.periodStartDay} tiap bulan (mis. tgl gajian)',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    final picked = await showDialog<int>(
                      context: context,
                      builder: (ctx) => SimpleDialog(
                        title: const Text('Pilih Tanggal Mulai (1–28)'),
                        children: [
                          SizedBox(
                            width: double.maxFinite,
                            height: 320,
                            child: GridView.builder(
                              padding: const EdgeInsets.all(12),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 7,
                                    mainAxisSpacing: 8,
                                    crossAxisSpacing: 8,
                                  ),
                              itemCount: 28,
                              itemBuilder: (_, idx) {
                                final day = idx + 1;
                                final selected = day == settings.periodStartDay;
                                return InkWell(
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: () => Navigator.pop(ctx, day),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: selected
                                          ? cs.primary
                                          : cs.surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      '$day',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: selected
                                            ? cs.onPrimary
                                            : cs.onSurface,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    );
                    if (picked != null) {
                      await notifier.setPeriodStartDay(picked);
                    }
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.flash_on_rounded),
                  title: const Text('Mode Simpan Langsung (Item Cepat)'),
                  subtitle: const Text(
                    'Ketuk chip Item Cepat di Beranda langsung menyimpan + tombol Urungkan',
                  ),
                  value: settings.quickSaveMode,
                  onChanged: notifier.setQuickSaveMode,
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),
          _SectionTitle('Tampilan & Interaksi'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.palette_outlined),
                  title: const Text('Tema aplikasi'),
                  subtitle: Text(_themeLabel(settings.themeMode)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    final picked = await showDialog<ThemeMode>(
                      context: context,
                      builder: (ctx) => SimpleDialog(
                        title: const Text('Pilih Tema'),
                        children: [
                          for (final mode in ThemeMode.values)
                            SimpleDialogOption(
                              onPressed: () => Navigator.pop(ctx, mode),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                ),
                                child: Text(
                                  _themeLabel(mode),
                                  style: tt.bodyLarge,
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                    if (picked != null) await notifier.setThemeMode(picked);
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.vibration_rounded),
                  title: const Text('Getaran sentuh (Haptic)'),
                  subtitle: const Text(
                    'Getaran halus saat tekan keypad, simpan, dan hapus',
                  ),
                  value: settings.hapticsEnabled,
                  onChanged: notifier.setHapticsEnabled,
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),
          _SectionTitle('Pengingat Harian'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.notifications_outlined),
                  title: const Text('Ingatkan catat transaksi'),
                  subtitle: const Text('Sudah catat pengeluaran hari ini?'),
                  value: settings.reminderEnabled,
                  onChanged: (v) async {
                    await notifier.setReminder(enabled: v);
                    await ref
                        .read(notificationServiceProvider)
                        .scheduleDailyReminder(
                          enabled: v,
                          hour: settings.reminderHour,
                          minute: settings.reminderMinute,
                        );
                  },
                ),
                if (settings.reminderEnabled) ...[
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.access_time_rounded),
                    title: const Text('Jam pengingat'),
                    trailing: Text(
                      '${settings.reminderHour.toString().padLeft(2, '0')}:${settings.reminderMinute.toString().padLeft(2, '0')}',
                      style: tt.titleMedium,
                    ),
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay(
                          hour: settings.reminderHour,
                          minute: settings.reminderMinute,
                        ),
                      );
                      if (picked != null) {
                        await notifier.setReminder(
                          enabled: true,
                          hour: picked.hour,
                          minute: picked.minute,
                        );
                        await ref
                            .read(notificationServiceProvider)
                            .scheduleDailyReminder(
                              enabled: true,
                              hour: picked.hour,
                              minute: picked.minute,
                            );
                      }
                    },
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 16),
          _SectionTitle('Keamanan & Privasi'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.lock_outline_rounded),
                  title: const Text('Kunci PIN (4–6 digit)'),
                  subtitle: const Text(
                    'Lindungi aplikasi dengan PIN terenkripsi lokal',
                  ),
                  value: settings.pinEnabled,
                  onChanged: (enable) async {
                    if (enable) {
                      await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (_) =>
                              const PinLockScreen(mode: PinScreenMode.setup),
                        ),
                      );
                    } else {
                      await ref.read(securityServiceProvider).clearPin();
                      await notifier.setPinEnabled(false);
                      await notifier.setBiometricEnabled(false);
                    }
                  },
                ),
                if (settings.pinEnabled) ...[
                  const Divider(height: 1),
                  SwitchListTile(
                    secondary: const Icon(Icons.fingerprint_rounded),
                    title: const Text('Buka dengan Sidik Jari / Biometrik'),
                    value: settings.biometricEnabled,
                    onChanged: (v) async {
                      if (v) {
                        final can = await ref
                            .read(securityServiceProvider)
                            .canCheckBiometrics();
                        if (!can && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Biometrik tidak tersedia di perangkat ini',
                              ),
                            ),
                          );
                          return;
                        }
                      }
                      await notifier.setBiometricEnabled(v);
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.timer_outlined),
                    title: const Text('Kunci otomatis di background'),
                    subtitle: Text(_autoLockLabel(settings.autoLockSeconds)),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () async {
                      final picked = await showDialog<int>(
                        context: context,
                        builder: (ctx) => SimpleDialog(
                          title: const Text('Waktu Kunci Otomatis'),
                          children: [
                            for (final sec in const [0, 60, 300])
                              SimpleDialogOption(
                                onPressed: () => Navigator.pop(ctx, sec),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 6,
                                  ),
                                  child: Text(
                                    _autoLockLabel(sec),
                                    style: tt.bodyLarge,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                      if (picked != null) {
                        await notifier.setAutoLockSeconds(picked);
                      }
                    },
                  ),
                ],
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.visibility_off_outlined),
                  title: const Text('Sembunyikan saldo'),
                  subtitle: const Text('Tampilkan angka sebagai Rp ••••••'),
                  value: settings.hideBalances,
                  onChanged: notifier.setHideBalances,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.screenshot_monitor_outlined),
                  title: const Text('Blokir screenshot & blur recent apps'),
                  subtitle: const Text(
                    'Aktifkan perlindungan layar FLAG_SECURE',
                  ),
                  value: settings.secureScreen,
                  onChanged: (v) async {
                    await notifier.setSecureScreen(v);
                    await ref
                        .read(securityServiceProvider)
                        .setSecureScreenFlag(v);
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),
          const _SectionTitle('Pembaruan Aplikasi'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.system_update_rounded),
                  title: const Text('Cek pembaruan otomatis'),
                  subtitle: const Text(
                    'Periksa rilis terbaru dari GitHub saat Sakuin dibuka (data keuangan tetap 100% lokal)',
                  ),
                  value: settings.autoCheckUpdate,
                  onChanged: notifier.setAutoCheckUpdate,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.refresh_rounded),
                  title: const Text('Cek Pembaruan Sekarang'),
                  subtitle: const Text(
                    'Unduh & pasang versi terbaru langsung dari aplikasi',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Memeriksa pembaruan dari GitHub...'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                    final result = await ref
                        .read(updateServiceProvider)
                        .checkForUpdate();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    if (result.errorMessage != null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(result.errorMessage!)),
                      );
                      return;
                    }
                    if (result.availableUpdate != null) {
                      await showUpdateAvailableSheet(
                        context,
                        currentVersion: result.currentVersion,
                        update: result.availableUpdate!,
                        allowSkip: false,
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Sakuin v${result.currentVersion} sudah versi terbaru',
                          ),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
          Center(
            child: Text(
              'Sakuin • Offline-first • Tanpa server & tanpa iklan',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall
            ?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}
