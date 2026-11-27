import 'package:flutter_test/flutter_test.dart';
import 'package:sakuin/core/db/app_database.dart';
import 'package:sakuin/core/utils/date_utils.dart';
import 'package:sakuin/core/utils/notification_tx_parser.dart';
import 'package:sakuin/core/utils/spending_insights_calculator.dart';

void main() {
  group('NotificationTxParser', () {
    test('parses Indonesian bank & e-wallet push notifications accurately', () {
      final gopay = NotificationTxParser.parse(
        packageName: 'com.gojek.gopay',
        title: 'Pembayaran QRIS Berhasil',
        text:
            'Pembayaran Rp 28.000 di KOPI KENANGAN berhasil menggunakan GoPay.',
        timestamp: DateTime(2026, 11, 26, 14, 10),
      );
      expect(gopay, isNotNull);
      expect(gopay!.bankName, 'GoPay');
      expect(gopay.amount, 28000);
      expect(gopay.merchantName, 'KOPI KENANGAN');

      final bca = NotificationTxParser.parse(
        packageName: 'com.bca.mybca.omni.android',
        title: 'Transaksi QRIS Berhasil',
        text: 'Pembayaran ke WARUNG PADANG SEDERHANA sebesar IDR 35.000 berhasil.',
        timestamp: DateTime(2026, 11, 26, 12, 5),
      );
      expect(bca, isNotNull);
      expect(bca!.bankName, 'BCA');
      expect(bca.amount, 35000);
      expect(bca.merchantName, 'WARUNG PADANG SEDERHANA');
    });

    test('rejects OTPs, promos, failed tx, and incoming funds', () {
      expect(
        NotificationTxParser.parse(
          packageName: 'id.dana',
          title: 'Dana Masuk',
          text: 'Kamu menerima Rp 100.000 dari Budi',
          timestamp: DateTime(2026, 11, 26),
        ),
        isNull,
      );
      expect(
        NotificationTxParser.parse(
          packageName: 'com.shopee.id',
          title: 'Promo Spesial Cashback',
          text: 'Diskon hingga Rp 50.000 hari ini saja!',
          timestamp: DateTime(2026, 11, 26),
        ),
        isNull,
      );
      expect(
        NotificationTxParser.parse(
          packageName: 'id.bmri.livin',
          title: 'Kode OTP',
          text: 'Kode OTP transaksi Rp 20.000 adalah 123456',
          timestamp: DateTime(2026, 11, 26),
        ),
        isNull,
      );
    });
  });

  group('SpendingInsightsCalculator', () {
    test(
      'calculates stable daily Safe-to-Spend allowance and remaining today',
      () {
        final period = DatePeriod(
          start: DateTime(2026, 11, 1),
          end: DateTime(2026, 11, 30),
          label: 'November 2026',
        );
        // Tanggal 21 Nov -> 10 hari tersisa (21..30 inklusif)
        // Saldo awal hari = 1.000.000, hari ini sudah keluar 40.000 -> remainingPool = 960.000
        final res = SpendingInsightsCalculator.calculateSafeToSpend(
          now: DateTime(2026, 11, 21, 13, 0),
          period: period,
          remainingPool: 960000,
          spentToday: 40000,
          sourceLabel: 'Pos Uang Harian',
        );

        expect(res.daysRemaining, 10);
        expect(res.dailyAllowance, 100000);
        expect(res.remainingToday, 60000);
        expect(res.isOverDailyLimit, isFalse);
      },
    );

    test('computes no-spend days, busiest weekday, rising/falling category, and projection', () {
      final period = DatePeriod(
        start: DateTime(2026, 11, 1),
        end: DateTime(2026, 11, 10),
        label: '1–10 Nov 2026',
      );
      // Hari ini tgl 5 Nov (elapsed = 5 hari: 1..5)
      // Belanja di tgl 1 (Minggu: 50rb) dan tgl 3 (Selasa: 150rb) -> 3 No-Spend Days!
      final trend = [
        DailyTrendPoint(
          dayKey: AppDateUtils.toDayKey(DateTime(2026, 11, 1)),
          income: 0,
          expense: 50000,
        ),
        DailyTrendPoint(
          dayKey: AppDateUtils.toDayKey(DateTime(2026, 11, 3)),
          income: 0,
          expense: 150000,
        ),
      ];

      final insights = SpendingInsightsCalculator.computePeriodInsights(
        now: DateTime(2026, 11, 5, 18, 0),
        period: period,
        trend: trend,
        currentTransactions: const [],
        currentExpenseCategories: const [
          CategoryAggregate(
            categoryId: 1,
            categoryName: 'Makanan & Minuman',
            icon: 'restaurant',
            color: 0xFF000000,
            total: 150000,
            count: 3,
          ),
          CategoryAggregate(
            categoryId: 2,
            categoryName: 'Transportasi',
            icon: 'car',
            color: 0xFF000000,
            total: 50000,
            count: 1,
          ),
        ],
        previousExpenseCategories: const [
          CategoryAggregate(
            categoryId: 1,
            categoryName: 'Makanan & Minuman',
            icon: 'restaurant',
            color: 0xFF000000,
            total: 100000,
            count: 2,
          ),
          CategoryAggregate(
            categoryId: 2,
            categoryName: 'Transportasi',
            icon: 'car',
            color: 0xFF000000,
            total: 120000,
            count: 3,
          ),
        ],
      );

      expect(insights.elapsedDays, 5);
      expect(insights.noSpendDays, 3);
      expect(insights.busiestWeekdayName, 'Selasa');
      expect(insights.busiestWeekdayAverage, 150000);
      expect(insights.projectedExpense, 400000); // 200rb / 5 * 10
      expect(insights.topRisingCategory?.categoryName, 'Makanan & Minuman');
      expect(insights.topRisingCategory?.deltaAmount, 50000);
      expect(insights.topFallingCategory?.categoryName, 'Transportasi');
      expect(insights.topFallingCategory?.deltaAmount, -70000);
    });

    test('assigns heatmap levels cleanly', () {
      expect(SpendingInsightsCalculator.heatmapLevel(0, 100000), 0);
      expect(SpendingInsightsCalculator.heatmapLevel(50000, 100000), 1);
      expect(SpendingInsightsCalculator.heatmapLevel(100000, 100000), 2);
      expect(SpendingInsightsCalculator.heatmapLevel(200000, 100000), 3);
    });

    test('groups pockets with same name across different wallets', () {
      const pockets = [
        PocketWithBalance(
          pocket: WalletPocket(
            id: 1,
            walletId: 10,
            name: 'Uang Harian',
            icon: 'restaurant',
            color: 0xFF00AA00,
            sortOrder: 0,
            isArchived: false,
          ),
          balance: 231200,
        ),
        PocketWithBalance(
          pocket: WalletPocket(
            id: 2,
            walletId: 20,
            name: 'uang harian',
            icon: 'restaurant',
            color: 0xFF00AA00,
            sortOrder: 0,
            isArchived: false,
          ),
          balance: 50000,
        ),
        PocketWithBalance(
          pocket: WalletPocket(
            id: 3,
            walletId: 30,
            name: 'Uang Harian',
            icon: 'restaurant',
            color: 0xFF00AA00,
            sortOrder: 0,
            isArchived: false,
          ),
          balance: 100000,
        ),
        PocketWithBalance(
          pocket: WalletPocket(
            id: 4,
            walletId: 10,
            name: 'Life Style',
            icon: 'shopping_bag',
            color: 0xFFAA00AA,
            sortOrder: 1,
            isArchived: false,
          ),
          balance: 200000,
        ),
        PocketWithBalance(
          pocket: WalletPocket(
            id: 5,
            walletId: 20,
            name: 'Lifestyle',
            icon: 'shopping_bag',
            color: 0xFFAA00AA,
            sortOrder: 1,
            isArchived: false,
          ),
          balance: 4500,
        ),
      ];

      final grouped = SpendingInsightsCalculator.groupPocketsByName(pockets);
      expect(grouped.length, 2);
      expect(grouped[0].displayName, 'Uang Harian');
      expect(grouped[0].totalBalance, 381200);
      expect(grouped[0].walletCount, 3);
      expect(grouped[0].pocketIds, {1, 2, 3});
      expect(grouped[1].displayName, 'Life Style');
      expect(grouped[1].totalBalance, 204500);
      expect(grouped[1].walletCount, 2);
    });
  });
}
