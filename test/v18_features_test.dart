import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakuin/core/db/app_database.dart';
import 'package:sakuin/core/services/auto_backup_service.dart';
import 'package:sakuin/core/services/backup_service.dart';
import 'package:sakuin/core/utils/notification_tx_parser.dart';
import 'package:sakuin/core/utils/quick_input_parser.dart';

void main() {
  group('QuickInputParser (Catat Cepat 1 Baris)', () {
    const wallets = [
      WalletWithBalance(
        wallet: Wallet(
          id: 1,
          name: 'Mandiri',
          type: 'bank',
          icon: 'bank',
          color: 0xFF1E3A8A,
          initialBalance: 0,
          includeInTotal: true,
          isArchived: false,
          sortOrder: 0,
        ),
        balance: 500000,
      ),
      WalletWithBalance(
        wallet: Wallet(
          id: 2,
          name: 'GoPay',
          type: 'ewallet',
          icon: 'ewallet',
          color: 0xFF00AA55,
          initialBalance: 0,
          includeInTotal: true,
          isArchived: false,
          sortOrder: 1,
        ),
        balance: 200000,
      ),
    ];

    const pockets = [
      PocketWithBalance(
        pocket: WalletPocket(
          id: 10,
          walletId: 2,
          name: 'Uang Harian',
          icon: 'food',
          color: 0xFFEA580C,
          sortOrder: 0,
          isArchived: false,
        ),
        balance: 150000,
      ),
      PocketWithBalance(
        pocket: WalletPocket(
          id: 11,
          walletId: 2,
          name: 'Date',
          icon: 'gift',
          color: 0xFFDB2777,
          sortOrder: 1,
          isArchived: false,
        ),
        balance: 100000,
      ),
    ];

    test('parses item, amount, wallet, and pocket alias offline', () {
      final res = QuickInputParser.parse(
        rawInput: 'kopi susu 18rb gopay harian',
        wallets: wallets,
        pockets: pockets,
      );
      expect(res.type, 'expense');
      expect(res.amount, 18000);
      expect(res.itemName, 'Kopi susu');
      expect(res.walletId, 2);
      expect(res.pocketId, 10);
      expect(res.canQuickSave, isTrue);
    });

    test('parses @merchant syntax and income keywords', () {
      final exp = QuickInputParser.parse(
        rawInput: 'makan siang 25k @"Warteg Bahari" mandiri',
        wallets: wallets,
        pockets: pockets,
      );
      expect(exp.type, 'expense');
      expect(exp.amount, 25000);
      expect(exp.itemName, 'Makan siang');
      expect(exp.merchantName, 'Warteg Bahari');
      expect(exp.walletId, 1);

      final inc = QuickInputParser.parse(
        rawInput: 'gaji 5,5jt mandiri',
        wallets: wallets,
        pockets: pockets,
      );
      expect(inc.type, 'income');
      expect(inc.amount, 5500000);
      expect(inc.walletId, 1);
    });

    test('auto-fills full tuple from MerchantMemory & ItemMemory', () {
      const merchantMem = [
        MerchantMemoryData(
          id: 1,
          merchantNormalized: 'kopi kenangan',
          displayMerchant: 'Kopi Kenangan',
          type: 'expense',
          lastItemName: 'Kopi Susu Mantan',
          lastAmount: 22000,
          lastCategoryId: 7,
          lastWalletId: 2,
          lastPocketId: 10,
          lastNote: 'Less sugar',
          useCount: 4,
          lastUsedAt: 1000,
        ),
      ];

      final res = QuickInputParser.parse(
        rawInput: 'kopi kenangan',
        wallets: wallets,
        pockets: pockets,
        merchantMemories: merchantMem,
      );
      expect(res.merchantName, 'Kopi Kenangan');
      expect(res.itemName, 'Kopi Susu Mantan');
      expect(res.amount, 22000);
      expect(res.categoryId, 7);
      expect(res.walletId, 2);
      expect(res.pocketId, 10);
    });
  });

  group('MerchantMemory, Pocket Group Query & Backup v4', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() => db.close());

    test(
      'saves paired item+merchant memory and restores cleanly in Backup v4',
      () async {
        final walletId = await db
            .into(db.wallets)
            .insert(
              WalletsCompanion.insert(
                name: 'GoPay',
                type: 'ewallet',
                icon: 'ewallet',
                color: 0xFF00AA55,
              ),
            );
        final pocketId = await db
            .into(db.walletPockets)
            .insert(
              WalletPocketsCompanion.insert(
                walletId: walletId,
                name: 'Uang Harian',
                icon: 'food',
                color: 0xFFEA580C,
              ),
            );
        final foodCatId = await db.findCategoryIdByName(
          'Makanan & Minuman',
          'expense',
        );

        await db.saveTransactionWithMemory(
          type: 'expense',
          amount: 24000,
          walletId: walletId,
          pocketId: pocketId,
          categoryId: foodCatId,
          itemName: 'Es Kopi Susu',
          merchantName: 'Kopi Kenangan',
          occurredAt: DateTime(2026, 11, 27, 10, 0),
        );

        final items = await db.searchItemMemory('kopi');
        expect(items.length, 1);
        expect(items.first.lastMerchantName, 'Kopi Kenangan');

        final matchedMerch = await db.findMerchantMemoryForName(
          'KOPI KENANGAN GRAND INDONESIA',
          type: 'expense',
        );
        expect(matchedMerch, isNotNull);
        expect(matchedMerch!.lastItemName, 'Es Kopi Susu');
        expect(matchedMerch.lastAmount, 24000);
        expect(matchedMerch.lastPocketId, pocketId);

        final pocketTxs = await db.fetchTransactionsForPocketIds({pocketId});
        expect(pocketTxs.length, 1);
        expect(pocketTxs.first.transaction.merchantName, 'Kopi Kenangan');

        // Target update
        await db.updatePocketTargetAmount(pocketId, 1000000);
        final pockets = await db.getPocketsForWallet(walletId);
        expect(pockets.first.pocket.targetAmount, 1000000);

        // Backup & Restore v4
        final jsonStr = await BackupService(db).buildJsonBackup();
        final preview = BackupService(db).parseBackupJson(jsonStr);
        final db2 = AppDatabase(NativeDatabase.memory());
        addTearDown(db2.close);
        await BackupService(db2).restoreBackup(preview, replaceExisting: true);
        final restoredMerch = await db2.findMerchantMemoryForName(
          'kopi kenangan',
        );
        expect(restoredMerch, isNotNull);
        expect(restoredMerch!.lastItemName, 'Es Kopi Susu');
      },
    );
  });

  group('NotificationTxParser (Income Capture) & AutoBackupService', () {
    test(
      'captures incoming transfer notifications when captureIncome is true',
      () {
        final ts = DateTime(2026, 11, 27, 13, 30);
        final ignored = NotificationTxParser.parse(
          packageName: 'id.bmri.livin',
          title: 'Dana Masuk',
          text: 'Transfer masuk sebesar Rp 500.000 dari Budi Santoso berhasil',
          timestamp: ts,
          captureIncome: false,
        );
        expect(ignored, isNull);

        final captured = NotificationTxParser.parse(
          packageName: 'id.bmri.livin',
          title: 'Dana Masuk',
          text: 'Transfer masuk sebesar Rp 500.000 dari Budi Santoso berhasil',
          timestamp: ts,
          captureIncome: true,
        );
        expect(captured, isNotNull);
        expect(captured!.txType, 'income');
        expect(captured.amount, 500000);
        expect(captured.merchantName, 'Budi Santoso');
      },
    );

    test('computes auto-backup schedule and 14-day reminder accurately', () {
      final now = DateTime(2026, 11, 27, 14, 0);
      expect(
        AutoBackupService.isBackupDue(
          lastBackupMillis: null,
          intervalDays: 7,
          now: now,
        ),
        isTrue,
      );
      expect(
        AutoBackupService.isBackupDue(
          lastBackupMillis: now
              .subtract(const Duration(days: 2))
              .millisecondsSinceEpoch,
          intervalDays: 7,
          now: now,
        ),
        isFalse,
      );
      expect(
        AutoBackupService.isBackupDue(
          lastBackupMillis: now
              .subtract(const Duration(days: 7, hours: 1))
              .millisecondsSinceEpoch,
          intervalDays: 7,
          now: now,
        ),
        isTrue,
      );
      expect(
        AutoBackupService.isBackupOverdue(
          lastBackupMillis: now
              .subtract(const Duration(days: 15))
              .millisecondsSinceEpoch,
          autoBackupEnabled: false,
          now: now,
        ),
        isTrue,
      );
      expect(
        AutoBackupService.isBackupOverdue(
          lastBackupMillis: now
              .subtract(const Duration(days: 15))
              .millisecondsSinceEpoch,
          autoBackupEnabled: true,
          now: now,
        ),
        isFalse,
      );
    });
  });
}
