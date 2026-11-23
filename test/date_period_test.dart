import 'package:flutter_test/flutter_test.dart';
import 'package:sakuin/core/utils/crypto_utils.dart';
import 'package:sakuin/core/utils/date_utils.dart';
import 'package:sakuin/features/recurring/recurring_service.dart';

void main() {
  group('AppDateUtils & Custom Report Periods', () {
    test('converts DateTime to dayKey and back', () {
      final date = DateTime(2026, 11, 23);
      final key = AppDateUtils.toDayKey(date);
      expect(key, 20261123);
      expect(AppDateUtils.fromDayKey(key), DateTime(2026, 11, 23));
    });

    test('calculates standard calendar month when periodStartDay is 1', () {
      final period = AppDateUtils.periodForDate(DateTime(2026, 11, 15), 1);
      expect(period.startDayKey, 20261101);
      expect(period.endDayKey, 20261130);
      expect(period.totalDays, 30);
    });

    test('calculates payday period (startDay = 25) before start day', () {
      final period = AppDateUtils.periodForDate(DateTime(2026, 11, 10), 25);
      expect(period.startDayKey, 20261025);
      expect(period.endDayKey, 20261124);
    });

    test('calculates payday period (startDay = 25) on and after start day', () {
      final onStart = AppDateUtils.periodForDate(DateTime(2026, 11, 25), 25);
      expect(onStart.startDayKey, 20261125);
      expect(onStart.endDayKey, 20261224);

      // Year rollover December -> January
      final decRollover = AppDateUtils.periodForDate(
        DateTime(2026, 12, 26),
        25,
      );
      expect(decRollover.startDayKey, 20261225);
      expect(decRollover.endDayKey, 20270124);
    });

    test('calculates previous period accurately for payday cycle', () {
      final current = AppDateUtils.periodForDate(DateTime(2026, 11, 26), 25);
      final prev = AppDateUtils.previousPeriod(current, 25);
      expect(prev.startDayKey, 20261025);
      expect(prev.endDayKey, 20261124);
    });

    test('formats Indonesian short day date', () {
      expect(
        AppDateUtils.formatDayDate(DateTime(2026, 11, 23)),
        'Sen, 23 Nov 2026',
      );
    });
  });

  group('RecurringService.computeNextDue', () {
    test('computes daily, weekly, and monthly next due dates', () {
      expect(
        RecurringService.computeNextDue(
          currentDueDayKey: 20261123,
          frequency: 'daily',
        ),
        20261124,
      );
      expect(
        RecurringService.computeNextDue(
          currentDueDayKey: 20261123,
          frequency: 'weekly',
        ),
        20261130,
      );
      expect(
        RecurringService.computeNextDue(
          currentDueDayKey: 20261125,
          frequency: 'monthly',
          dayOfMonth: 25,
        ),
        20261225,
      );
    });
  });

  group('CryptoUtils PIN hashing', () {
    test('hashes and verifies PIN with unique salt', () {
      final salt1 = CryptoUtils.generateSalt();
      final salt2 = CryptoUtils.generateSalt();
      expect(salt1, isNot(equals(salt2)));

      final hash = CryptoUtils.hashPin('123456', salt1);
      expect(CryptoUtils.verifyPin('123456', salt1, hash), isTrue);
      expect(CryptoUtils.verifyPin('654321', salt1, hash), isFalse);
      expect(CryptoUtils.verifyPin('123456', salt2, hash), isFalse);
    });
  });
}
