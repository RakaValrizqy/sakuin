import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sakuin/core/utils/currency_formatter.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  NotificationService();

  static const int _dailyReminderId = 1001;
  static const int _weeklyBackupId = 1002;
  static const int _debtBaseId = 2000;
  static const int _budgetBaseId = 3000;
  static const int _recurringBaseId = 4000;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    _configureLocalTimezone();

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const settings = InitializationSettings(android: androidSettings);
    try {
      await _plugin.initialize(settings);
      _initialized = true;
    } catch (_) {
      // Aman diabaikan pada lingkungan unit test.
    }
  }

  void _configureLocalTimezone() {
    // Deteksi offset lokal perangkat agar tidak memerlukan plugin timezone tambahan.
    final offset = DateTime.now().timeZoneOffset;
    final hours = offset.inHours;
    String zoneName;
    if (hours == 7) {
      zoneName = 'Asia/Jakarta';
    } else if (hours == 8) {
      zoneName = 'Asia/Makassar';
    } else if (hours == 9) {
      zoneName = 'Asia/Jayapura';
    } else {
      zoneName = 'UTC';
    }
    try {
      tz.setLocalLocation(tz.getLocation(zoneName));
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }
  }

  Future<void> requestPermissionIfNeeded() async {
    await init();
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    } catch (_) {}
  }

  Future<void> scheduleDailyReminder({
    required bool enabled,
    required int hour,
    required int minute,
  }) async {
    await init();
    if (!enabled) {
      await _plugin.cancel(_dailyReminderId);
      return;
    }

    await requestPermissionIfNeeded();

    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'sakuin_daily_reminder',
        'Pengingat Harian',
        channelDescription: 'Pengingat harian untuk mencatat transaksi',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
    );

    try {
      await _plugin.zonedSchedule(
        _dailyReminderId,
        'Sudah catat pengeluaran hari ini?',
        'Catat transaksi harianmu di Sakuin cuma butuh beberapa detik.',
        scheduled,
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (_) {}
  }

  Future<void> scheduleWeeklyBackupReminder(bool enabled) async {
    await init();
    if (!enabled) {
      await _plugin.cancel(_weeklyBackupId);
      return;
    }
    await requestPermissionIfNeeded();
    final now = tz.TZDateTime.now(tz.local);
    final nextSunday = now.add(Duration(days: (7 - now.weekday) % 7 + 1));
    final scheduled = tz.TZDateTime(
      tz.local,
      nextSunday.year,
      nextSunday.month,
      nextSunday.day,
      19,
      0,
    );

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'sakuin_backup_reminder',
        'Pengingat Backup',
        channelDescription: 'Pengingat mingguan untuk mencadangkan data Sakuin',
        importance: Importance.low,
        priority: Priority.low,
      ),
    );

    try {
      await _plugin.zonedSchedule(
        _weeklyBackupId,
        'Waktunya backup data Sakuin',
        'Simpan cadangan keuanganmu ke Google Drive atau penyimpanan perangkat.',
        scheduled,
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
    } catch (_) {}
  }

  Future<void> scheduleDebtReminder({
    required int debtId,
    required String personName,
    required String direction,
    required int remaining,
    required DateTime? dueDate,
  }) async {
    await init();
    final notifId = _debtBaseId + (debtId % 900);
    if (dueDate == null || remaining <= 0) {
      await _plugin.cancel(notifId);
      return;
    }

    // Jadwalkan H-1 pukul 09:00 lokal, atau hari H jika H-1 sudah lewat.
    final now = tz.TZDateTime.now(tz.local);
    var target = tz.TZDateTime(
      tz.local,
      dueDate.year,
      dueDate.month,
      dueDate.day,
      9,
      0,
    ).subtract(const Duration(days: 1));
    if (!target.isAfter(now)) {
      target = tz.TZDateTime(
        tz.local,
        dueDate.year,
        dueDate.month,
        dueDate.day,
        9,
        0,
      );
    }
    if (!target.isAfter(now)) return;

    final amountStr = CurrencyFormatter.format(remaining);
    final body = direction == 'i_owe'
        ? 'Hutangmu ke $personName sebesar $amountStr segera jatuh tempo.'
        : 'Piutang dari $personName sebesar $amountStr segera jatuh tempo.';

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'sakuin_debt_reminder',
        'Pengingat Hutang-Piutang',
        channelDescription: 'Pengingat jatuh tempo hutang dan piutang',
        importance: Importance.high,
        priority: Priority.high,
      ),
    );

    try {
      await _plugin.zonedSchedule(
        notifId,
        'Pengingat Jatuh Tempo',
        body,
        target,
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (_) {}
  }

  Future<void> cancelDebtReminder(int debtId) async {
    await init();
    try {
      await _plugin.cancel(_debtBaseId + (debtId % 900));
    } catch (_) {}
  }

  Future<void> showBudgetAlert({
    required int budgetId,
    required String label,
    required int percent,
    required int spent,
    required int limit,
  }) async {
    await init();
    final isOver = percent >= 100;
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'sakuin_budget_alert',
        'Peringatan Anggaran',
        channelDescription:
            'Notifikasi saat pengeluaran mencapai 80% atau 100% anggaran',
        importance: Importance.high,
        priority: Priority.high,
      ),
    );
    try {
      await _plugin.show(
        _budgetBaseId + (budgetId % 900),
        isOver
            ? 'Anggaran $label terlampaui ($percent%)'
            : 'Anggaran $label hampir habis ($percent%)',
        'Terpakai ${CurrencyFormatter.format(spent)} dari ${CurrencyFormatter.format(limit)}.',
        details,
      );
    } catch (_) {}
  }

  Future<void> showRecurringNotification({
    required int ruleId,
    required String title,
    required int amount,
    required bool autoCreated,
  }) async {
    await init();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'sakuin_recurring',
        'Transaksi Berulang',
        channelDescription: 'Notifikasi transaksi berulang yang jatuh tempo',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
    );
    try {
      await _plugin.show(
        _recurringBaseId + (ruleId % 900),
        autoCreated
            ? 'Transaksi berulang dicatat: $title'
            : 'Konfirmasi transaksi berulang: $title',
        autoCreated
            ? 'Nominal ${CurrencyFormatter.format(amount)} telah otomatis ditambahkan.'
            : 'Nominal ${CurrencyFormatter.format(amount)} jatuh tempo hari ini. Buka Sakuin untuk konfirmasi.',
        details,
      );
    } catch (_) {}
  }
}

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService();
});
