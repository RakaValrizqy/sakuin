import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sakuin/core/db/db_provider.dart';
import 'package:sakuin/core/services/backup_service.dart';
import 'package:sakuin/core/services/settings_service.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AutoBackupConfig {
  const AutoBackupConfig({
    this.enabled = false,
    this.intervalDays = 7,
    this.lastAutoBackupMillis,
  });

  final bool enabled;
  final int intervalDays; // 1 | 3 | 7
  final int? lastAutoBackupMillis;

  AutoBackupConfig copyWith({
    bool? enabled,
    int? intervalDays,
    int? lastAutoBackupMillis,
  }) {
    return AutoBackupConfig(
      enabled: enabled ?? this.enabled,
      intervalDays: intervalDays ?? this.intervalDays,
      lastAutoBackupMillis: lastAutoBackupMillis ?? this.lastAutoBackupMillis,
    );
  }
}

class LocalBackupSnapshot {
  const LocalBackupSnapshot({
    required this.file,
    required this.fileName,
    required this.modifiedAt,
    required this.sizeBytes,
  });

  final File file;
  final String fileName;
  final DateTime modifiedAt;
  final int sizeBytes;
}

class AutoBackupService {
  AutoBackupService(this._ref);

  static const _kEnabled = 'sakuin_auto_backup_enabled';
  static const _kIntervalDays = 'sakuin_auto_backup_interval_days';
  static const _kLastAutoMillis = 'sakuin_auto_backup_last_millis';
  static const _kReminderDismissedDay = 'sakuin_backup_reminder_dismissed_day';
  static const int maxRetainedSnapshots = 5;

  final Ref _ref;

  Future<AutoBackupConfig> loadConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return AutoBackupConfig(
        enabled: prefs.getBool(_kEnabled) ?? false,
        intervalDays: prefs.getInt(_kIntervalDays) ?? 7,
        lastAutoBackupMillis: prefs.getInt(_kLastAutoMillis),
      );
    } catch (_) {
      return const AutoBackupConfig();
    }
  }

  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabled, enabled);
  }

  Future<void> setIntervalDays(int days) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kIntervalDays, days);
  }

  Future<Directory> getSnapshotDirectory() async {
    final baseDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${baseDir.path}/SakuinBackup');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Simpan snapshot cadangan JSON lokal otomatis & jaga maksimal [maxRetainedSnapshots] file terbaru.
  Future<File> runAutoBackupNow() async {
    final backupSvc = _ref.read(backupServiceProvider);
    final jsonText = await backupSvc.buildJsonBackup();
    final dir = await getSnapshotDirectory();

    final now = DateTime.now();
    final stamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    final file = File('${dir.path}/sakuin_auto_$stamp.json');
    await file.writeAsString(jsonText);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kLastAutoMillis, now.millisecondsSinceEpoch);
    await _ref.read(settingsProvider.notifier).recordLastBackupNow();

    await _pruneOldSnapshots(dir);
    return file;
  }

  Future<void> _pruneOldSnapshots(Directory dir) async {
    try {
      final files = await dir
          .list()
          .where((e) => e is File && e.path.endsWith('.json'))
          .cast<File>()
          .toList();
      if (files.length <= maxRetainedSnapshots) return;
      final stats = <File, DateTime>{};
      for (final f in files) {
        stats[f] = (await f.stat()).modified;
      }
      files.sort((a, b) => stats[b]!.compareTo(stats[a]!));
      for (final old in files.skip(maxRetainedSnapshots)) {
        try {
          await old.delete();
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// Dipanggil saat app dibuka (post-first-frame): jalankan auto-backup jika sudah jatuh jadwal.
  Future<bool> runIfDue({DateTime? now}) async {
    try {
      final cfg = await loadConfig();
      if (!cfg.enabled) return false;

      final current = now ?? DateTime.now();
      if (!isBackupDue(
        lastBackupMillis: cfg.lastAutoBackupMillis,
        intervalDays: cfg.intervalDays,
        now: current,
      )) {
        return false;
      }

      final db = _ref.read(appDatabaseProvider);
      final wallets = await db.select(db.wallets).get();
      if (wallets.isEmpty) return false;

      await runAutoBackupNow();
      return true;
    } catch (_) {
      return false;
    }
  }

  static bool isBackupDue({
    required int? lastBackupMillis,
    required int intervalDays,
    required DateTime now,
  }) {
    if (lastBackupMillis == null) return true;
    final last = DateTime.fromMillisecondsSinceEpoch(lastBackupMillis);
    return now.difference(last).inHours >= intervalDays * 24;
  }

  /// Cek apakah banner pengingat halus di Beranda perlu muncul (> 14 hari belum backup).
  static bool isBackupOverdue({
    required int? lastBackupMillis,
    required bool autoBackupEnabled,
    required DateTime now,
    int thresholdDays = 14,
  }) {
    if (autoBackupEnabled) return false;
    if (lastBackupMillis == null) return true;
    final last = DateTime.fromMillisecondsSinceEpoch(lastBackupMillis);
    return now.difference(last).inDays >= thresholdDays;
  }

  Future<bool> isReminderDismissedToday() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      final todayKey = now.year * 10000 + now.month * 100 + now.day;
      return prefs.getInt(_kReminderDismissedDay) == todayKey;
    } catch (_) {
      return false;
    }
  }

  Future<void> dismissReminderToday() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      final todayKey = now.year * 10000 + now.month * 100 + now.day;
      await prefs.setInt(_kReminderDismissedDay, todayKey);
    } catch (_) {}
  }

  Future<List<LocalBackupSnapshot>> listLocalSnapshots() async {
    try {
      final dir = await getSnapshotDirectory();
      final items = <LocalBackupSnapshot>[];
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith('.json')) {
          final stat = await entity.stat();
          final name = entity.uri.pathSegments.isNotEmpty
              ? entity.uri.pathSegments.last
              : entity.path;
          items.add(
            LocalBackupSnapshot(
              file: entity,
              fileName: name,
              modifiedAt: stat.modified,
              sizeBytes: stat.size,
            ),
          );
        }
      }
      items.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
      return items;
    } catch (_) {
      return const [];
    }
  }

  Future<void> shareSnapshot(LocalBackupSnapshot snapshot) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(snapshot.file.path, mimeType: 'application/json')],
        subject: 'Cadangan Otomatis Sakuin',
        text: 'File cadangan lokal otomatis Sakuin (${snapshot.fileName}).',
      ),
    );
  }
}

final autoBackupServiceProvider = Provider<AutoBackupService>(
  (ref) => AutoBackupService(ref),
);

final autoBackupConfigProvider = FutureProvider<AutoBackupConfig>((ref) {
  return ref.watch(autoBackupServiceProvider).loadConfig();
});

final localBackupSnapshotsProvider = FutureProvider<List<LocalBackupSnapshot>>((
  ref,
) {
  return ref.watch(autoBackupServiceProvider).listLocalSnapshots();
});
