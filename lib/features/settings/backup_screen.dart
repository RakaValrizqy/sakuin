import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sakuin/core/services/auto_backup_service.dart';
import 'package:sakuin/core/services/backup_service.dart';
import 'package:sakuin/core/services/notification_service.dart';
import 'package:sakuin/core/services/settings_service.dart';
import 'package:sakuin/core/utils/date_utils.dart';
import 'package:sakuin/features/budget/budget_providers.dart';
import 'package:sakuin/features/transaction/transaction_providers.dart';

class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _busy = false;

  Future<void> _exportSaf() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final path = await ref.read(backupServiceProvider).exportViaSaf();
      if (path != null) {
        await ref.read(settingsProvider.notifier).recordLastBackupNow();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cadangan berhasil disimpan')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Gagal menyimpan cadangan: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportShare() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(backupServiceProvider).exportViaShareSheet();
      await ref.read(settingsProvider.notifier).recordLastBackupNow();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal membagikan cadangan: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickAndRestore() async {
    if (_busy) return;
    setState(() => _busy = true);
    BackupPreview? preview;
    try {
      preview = await ref.read(backupServiceProvider).pickAndPreviewBackup();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('File tidak valid: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }

    if (preview == null || !mounted) return;

    final mode = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pratinjau File Cadangan'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (preview!.exportedAt != null)
              Text(
                'Dibuat: ${AppDateUtils.formatDayDate(preview.exportedAt!)} ${AppDateUtils.formatTime(preview.exportedAt!)}',
              ),
            Text('Versi skema: v${preview.schemaVersion}'),
            const Divider(height: 20),
            Text('• Dompet: ${preview.walletCount}'),
            Text('• Kategori: ${preview.categoryCount}'),
            Text('• Transaksi: ${preview.transactionCount}'),
            Text('• Hutang-Piutang: ${preview.debtCount}'),
            Text('• Anggaran: ${preview.budgetCount}'),
            Text('• Transaksi berulang: ${preview.recurringCount}'),
            const SizedBox(height: 12),
            const Text(
              'Pilih cara pemulihan data:',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, 'merge'),
            child: const Text('Gabungkan'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'replace'),
            child: const Text('Timpa Semua'),
          ),
        ],
      ),
    );

    if (mode == null || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(backupServiceProvider)
          .restoreBackup(preview, replaceExisting: mode == 'replace');
      ref.read(transactionRevisionProvider.notifier).state++;
      ref.read(budgetsRevisionProvider.notifier).state++;
      await ref.read(settingsProvider.notifier).setOnboardingCompleted(true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              mode == 'replace'
                  ? 'Data berhasil dipulihkan (ditimpa)'
                  : 'Data berhasil digabungkan',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal memulihkan data: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreFromSnapshot(LocalBackupSnapshot snap) async {
    if (_busy) return;
    setState(() => _busy = true);
    BackupPreview? preview;
    try {
      final content = await snap.file.readAsString();
      preview = ref.read(backupServiceProvider).parseBackupJson(content);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Snapshot rusak: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (preview == null || !mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pulihkan Snapshot Lokal?'),
        content: Text(
          'Memulihkan ${snap.fileName} (${preview!.transactionCount} transaksi, ${preview.walletCount} dompet). Seluruh data saat ini akan diganti dengan snapshot ini.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Pulihkan'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(backupServiceProvider)
          .restoreBackup(preview, replaceExisting: true);
      ref.read(transactionRevisionProvider.notifier).state++;
      ref.read(budgetsRevisionProvider.notifier).state++;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Snapshot lokal berhasil dipulihkan')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runAutoBackupNow() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(autoBackupServiceProvider).runAutoBackupNow();
      ref.invalidate(autoBackupConfigProvider);
      ref.invalidate(localBackupSnapshotsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Snapshot backup lokal tersimpan')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal backup lokal: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final autoCfg =
        ref.watch(autoBackupConfigProvider).valueOrNull ??
        const AutoBackupConfig();
    final snapshots =
        ref.watch(localBackupSnapshotsProvider).valueOrNull ?? const [];
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    final lastBackupText = settings.lastBackupMillis == null
        ? 'Belum pernah backup'
        : AppDateUtils.formatDayDate(
            DateTime.fromMillisecondsSinceEpoch(settings.lastBackupMillis!)
                .toLocal(),
          );

    return Scaffold(
      appBar: AppBar(title: const Text('Backup & Restore')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: cs.primaryContainer.withValues(alpha: 0.35),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.cloud_done_outlined, color: cs.primary, size: 32),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('100% Privat & Offline', style: tt.titleMedium),
                        const SizedBox(height: 4),
                        Text(
                          'Simpan cadangan ke Google Drive atau folder HP lewat pemilih file sistem (Storage Access Framework) tanpa perlu login akun.',
                          style: tt.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.history_rounded),
                  title: const Text('Terakhir backup'),
                  subtitle: Text(lastBackupText),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.save_alt_rounded),
                  title: const Text('Simpan File Cadangan (.json)'),
                  subtitle: const Text(
                    'Pilih lokasi simpan (termasuk Google Drive di dialog Android)',
                  ),
                  trailing: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.chevron_right_rounded),
                  onTap: _exportSaf,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.share_rounded),
                  title: const Text('Bagikan / Kirim Cadangan'),
                  subtitle: const Text(
                    'Kirim file cadangan ke Google Drive, Telegram, atau penyimpanan lain',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _exportShare,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: ListTile(
              leading: const Icon(Icons.restore_rounded),
              title: const Text('Pulihkan Data (Restore)'),
              subtitle: const Text(
                'Pilih file .json dari perangkat atau Google Drive, pratinjau, lalu timpa atau gabung',
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: _pickAndRestore,
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.autorenew_rounded),
                  title: const Text('Backup otomatis lokal berkala'),
                  subtitle: const Text(
                    'Simpan hingga 5 snapshot JSON terbaru di HP secara otomatis saat aplikasi dibuka',
                  ),
                  value: autoCfg.enabled,
                  onChanged: (v) async {
                    await ref.read(autoBackupServiceProvider).setEnabled(v);
                    if (v) {
                      await _runAutoBackupNow();
                    } else {
                      ref.invalidate(autoBackupConfigProvider);
                    }
                  },
                ),
                if (autoCfg.enabled) ...[
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Frekuensi', style: tt.labelMedium),
                        const SizedBox(height: 8),
                        SegmentedButton<int>(
                          segments: const [
                            ButtonSegment(value: 1, label: Text('Harian')),
                            ButtonSegment(value: 3, label: Text('3 Hari')),
                            ButtonSegment(value: 7, label: Text('Mingguan')),
                          ],
                          selected: {autoCfg.intervalDays},
                          onSelectionChanged: (sel) async {
                            await ref
                                .read(autoBackupServiceProvider)
                                .setIntervalDays(sel.first);
                            ref.invalidate(autoBackupConfigProvider);
                          },
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _busy ? null : _runAutoBackupNow,
                            icon: const Icon(Icons.backup_outlined, size: 18),
                            label: const Text('Buat Snapshot Lokal Sekarang'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (snapshots.isNotEmpty) ...[
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Snapshot Lokal Tersimpan (${snapshots.length}/${AutoBackupService.maxRetainedSnapshots})',
                        style: tt.labelMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                  for (final snap in snapshots)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.description_outlined, size: 20),
                      title: Text(
                        '${AppDateUtils.formatDayDate(snap.modifiedAt)} • ${AppDateUtils.formatTime(snap.modifiedAt)}',
                        style: tt.bodyMedium,
                      ),
                      subtitle: Text(
                        '${(snap.sizeBytes / 1024).toStringAsFixed(1)} KB • ${snap.fileName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.labelSmall,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Bagikan ke Drive / WhatsApp',
                            icon: const Icon(Icons.share_outlined, size: 18),
                            onPressed: () => ref
                                .read(autoBackupServiceProvider)
                                .shareSnapshot(snap),
                          ),
                          IconButton(
                            tooltip: 'Pulihkan snapshot ini',
                            icon: const Icon(Icons.restore_rounded, size: 18),
                            onPressed: () => _restoreFromSnapshot(snap),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: SwitchListTile(
              secondary: const Icon(Icons.notifications_active_outlined),
              title: const Text('Pengingat backup mingguan'),
              subtitle: const Text(
                'Ingatkan setiap minggu untuk mencadangkan data',
              ),
              value: settings.backupReminderEnabled,
              onChanged: (v) async {
                await ref
                    .read(settingsProvider.notifier)
                    .setBackupReminderEnabled(v);
                await ref
                    .read(notificationServiceProvider)
                    .scheduleWeeklyBackupReminder(v);
              },
            ),
          ),
        ],
      ),
    );
  }
}
