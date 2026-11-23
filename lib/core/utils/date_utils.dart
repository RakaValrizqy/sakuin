import 'package:intl/intl.dart';

/// Rentang tanggal periode [start, end] inklusif pada level hari lokal.
class DatePeriod {
  const DatePeriod({
    required this.start,
    required this.end,
    required this.label,
  });

  final DateTime start;
  final DateTime end;
  final String label;

  int get startDayKey => AppDateUtils.toDayKey(start);
  int get endDayKey => AppDateUtils.toDayKey(end);

  int get totalDays {
    final s = DateTime(start.year, start.month, start.day);
    final e = DateTime(end.year, end.month, end.day);
    return e.difference(s).inDays + 1;
  }

  int remainingDaysFrom(DateTime reference) {
    final ref = DateTime(reference.year, reference.month, reference.day);
    final e = DateTime(end.year, end.month, end.day);
    if (ref.isAfter(e)) return 0;
    final s = DateTime(start.year, start.month, start.day);
    final effectiveStart = ref.isBefore(s) ? s : ref;
    return e.difference(effectiveStart).inDays + 1;
  }

  @override
  bool operator ==(Object other) =>
      other is DatePeriod &&
      other.startDayKey == startDayKey &&
      other.endDayKey == endDayKey;

  @override
  int get hashCode => Object.hash(startDayKey, endDayKey);
}

enum ReportPeriodPreset {
  thisPeriod,
  lastPeriod,
  last7Days,
  last30Days,
  thisYear,
  custom,
}

class AppDateUtils {
  AppDateUtils._();

  static const List<String> _shortDays = [
    'Sen',
    'Sel',
    'Rab',
    'Kam',
    'Jum',
    'Sab',
    'Min',
  ];

  static const List<String> _shortMonths = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'Mei',
    'Jun',
    'Jul',
    'Agu',
    'Sep',
    'Okt',
    'Nov',
    'Des',
  ];

  static const List<String> _fullMonths = [
    'Januari',
    'Februari',
    'Maret',
    'April',
    'Mei',
    'Juni',
    'Juli',
    'Agustus',
    'September',
    'Oktober',
    'November',
    'Desember',
  ];

  /// Konversi DateTime lokal ke integer `yyyymmdd` untuk indexing SQL cepat.
  static int toDayKey(DateTime date) =>
      date.year * 10000 + date.month * 100 + date.day;

  static DateTime fromDayKey(int dayKey) {
    final year = dayKey ~/ 10000;
    final month = (dayKey % 10000) ~/ 100;
    final day = dayKey % 100;
    return DateTime(year, month, day);
  }

  /// Format: `Sen, 23 Nov 2026`
  static String formatDayDate(DateTime date) {
    final dayName = _shortDays[date.weekday - 1];
    final monthName = _shortMonths[date.month - 1];
    return '$dayName, ${date.day} $monthName ${date.year}';
  }

  /// Format: `23 Nov 2026`
  static String formatShortDate(DateTime date) {
    final monthName = _shortMonths[date.month - 1];
    return '${date.day} $monthName ${date.year}';
  }

  /// Format: `23 Nov`
  static String formatDayMonth(DateTime date) {
    final monthName = _shortMonths[date.month - 1];
    return '${date.day} $monthName';
  }

  /// Format: `November 2026`
  static String formatMonthYear(DateTime date) =>
      '${_fullMonths[date.month - 1]} ${date.year}';

  /// Format jam: `19:30`
  static String formatTime(DateTime date) => DateFormat('HH:mm').format(date);

  /// Label header grup transaksi: `Hari ini`, `Kemarin`, atau `Sen, 23 Nov 2026`
  static String formatRelativeHeader(int dayKey, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final todayKey = toDayKey(today);
    if (dayKey == todayKey) return 'Hari ini • ${formatDayDate(today)}';
    final yesterday = today.subtract(const Duration(days: 1));
    if (dayKey == toDayKey(yesterday)) {
      return 'Kemarin • ${formatDayDate(yesterday)}';
    }
    return formatDayDate(fromDayKey(dayKey));
  }

  /// Hitung periode bulanan berdasarkan `periodStartDay` (1..28), mis. tgl 25 gajian.
  ///
  /// Contoh: `periodStartDay = 25`, `reference = 10 Nov 2026`
  /// -> start = `25 Okt 2026`, end = `24 Nov 2026`.
  /// Contoh: `periodStartDay = 25`, `reference = 26 Nov 2026`
  /// -> start = `25 Nov 2026`, end = `24 Des 2026`.
  /// Contoh: `periodStartDay = 1`, `reference = 15 Nov 2026`
  /// -> start = `1 Nov 2026`, end = `30 Nov 2026`.
  static DatePeriod periodForDate(DateTime reference, int periodStartDay) {
    final safeStartDay = periodStartDay.clamp(1, 28);
    final ref = DateTime(reference.year, reference.month, reference.day);

    if (safeStartDay == 1) {
      final start = DateTime(ref.year, ref.month, 1);
      final end = DateTime(ref.year, ref.month + 1, 0);
      return DatePeriod(start: start, end: end, label: formatMonthYear(start));
    }

    late final DateTime start;
    late final DateTime end;
    if (ref.day >= safeStartDay) {
      start = DateTime(ref.year, ref.month, safeStartDay);
      end = DateTime(ref.year, ref.month + 1, safeStartDay - 1);
    } else {
      start = DateTime(ref.year, ref.month - 1, safeStartDay);
      end = DateTime(ref.year, ref.month, safeStartDay - 1);
    }

    return DatePeriod(
      start: start,
      end: end,
      label: '${formatDayMonth(start)} – ${formatDayMonth(end)}',
    );
  }

  /// Periode sebelumnya dengan panjang yang setara (untuk perbandingan naik/turun %).
  static DatePeriod previousPeriod(
    DatePeriod current,
    int periodStartDay, {
    bool isMonthlyCycle = true,
  }) {
    if (isMonthlyCycle) {
      final prevRef = current.start.subtract(const Duration(days: 1));
      return periodForDate(prevRef, periodStartDay);
    }
    final days = current.totalDays;
    final prevEnd = current.start.subtract(const Duration(days: 1));
    final prevStart = prevEnd.subtract(Duration(days: days - 1));
    return DatePeriod(
      start: prevStart,
      end: prevEnd,
      label: '${formatDayMonth(prevStart)} – ${formatDayMonth(prevEnd)}',
    );
  }

  static DatePeriod periodForPreset(
    ReportPeriodPreset preset,
    int periodStartDay, {
    DateTime? now,
    DateTime? customStart,
    DateTime? customEnd,
  }) {
    final ref = now ?? DateTime.now();
    final today = DateTime(ref.year, ref.month, ref.day);
    switch (preset) {
      case ReportPeriodPreset.thisPeriod:
        return periodForDate(today, periodStartDay);
      case ReportPeriodPreset.lastPeriod:
        final current = periodForDate(today, periodStartDay);
        return previousPeriod(current, periodStartDay, isMonthlyCycle: true);
      case ReportPeriodPreset.last7Days:
        final start = today.subtract(const Duration(days: 6));
        return DatePeriod(start: start, end: today, label: '7 Hari Terakhir');
      case ReportPeriodPreset.last30Days:
        final start = today.subtract(const Duration(days: 29));
        return DatePeriod(start: start, end: today, label: '30 Hari Terakhir');
      case ReportPeriodPreset.thisYear:
        return DatePeriod(
          start: DateTime(today.year, 1, 1),
          end: DateTime(today.year, 12, 31),
          label: 'Tahun ${today.year}',
        );
      case ReportPeriodPreset.custom:
        final s = customStart ?? today.subtract(const Duration(days: 29));
        final e = customEnd ?? today;
        final orderedStart = s.isAfter(e) ? e : s;
        final orderedEnd = s.isAfter(e) ? s : e;
        return DatePeriod(
          start: orderedStart,
          end: orderedEnd,
          label:
              '${formatShortDate(orderedStart)} – ${formatShortDate(orderedEnd)}',
        );
    }
  }
}
