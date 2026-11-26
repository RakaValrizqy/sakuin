import 'package:flutter_test/flutter_test.dart';
import 'package:sakuin/core/services/qris_sync_service.dart';
import 'package:sakuin/core/utils/date_utils.dart';

void main() {
  group('QrisSyncService cutoff date filtering', () {
    test('ignores transactions on and before selected cutoff date', () {
      final cutoff = AppDateUtils.toDayKey(DateTime(2026, 11, 25));

      // 24 Nov 2026 -> diabaikan
      expect(
        QrisSyncService.shouldIgnoreTransactionDate(
          DateTime(2026, 11, 24, 23, 59),
          cutoff,
        ),
        isTrue,
      );

      // 25 Nov 2026 (pagi sampai akhir hari) -> diabaikan
      expect(
        QrisSyncService.shouldIgnoreTransactionDate(
          DateTime(2026, 11, 25, 0, 0),
          cutoff,
        ),
        isTrue,
      );
      expect(
        QrisSyncService.shouldIgnoreTransactionDate(
          DateTime(2026, 11, 25, 23, 59, 59),
          cutoff,
        ),
        isTrue,
      );

      // 26 Nov 2026 -> diproses
      expect(
        QrisSyncService.shouldIgnoreTransactionDate(
          DateTime(2026, 11, 26, 0, 1),
          cutoff,
        ),
        isFalse,
      );

      // Tanpa batas -> semua diproses
      expect(
        QrisSyncService.shouldIgnoreTransactionDate(
          DateTime(2026, 11, 25, 12, 0),
          null,
        ),
        isFalse,
      );
    });

    test(
      'computes efficient IMAP SINCE date using later of lookback and cutoff',
      () {
        final now = DateTime(2026, 11, 26, 14, 0);
        final cutoff25Nov = AppDateUtils.toDayKey(DateTime(2026, 11, 25));

        // lookback 14 hari (12 Nov) vs cutoff 25 Nov -> ambil 25 Nov
        expect(
          QrisSyncService.computeImapSinceDate(
            now: now,
            lookbackDays: 14,
            ignoreOnOrBeforeDayKey: cutoff25Nov,
          ),
          DateTime(2026, 11, 25),
        );

        // lookback 7 hari (19 Nov) vs cutoff lama 1 Nov -> ambil 19 Nov
        expect(
          QrisSyncService.computeImapSinceDate(
            now: now,
            lookbackDays: 7,
            ignoreOnOrBeforeDayKey: AppDateUtils.toDayKey(
              DateTime(2026, 11, 1),
            ),
          ),
          DateTime(2026, 11, 19),
        );

        // tanpa cutoff -> pakai lookback
        expect(
          QrisSyncService.computeImapSinceDate(
            now: now,
            lookbackDays: 14,
            ignoreOnOrBeforeDayKey: null,
          ),
          DateTime(2026, 11, 12),
        );
      },
    );
  });
}
