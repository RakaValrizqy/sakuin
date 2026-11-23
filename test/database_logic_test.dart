import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakuin/core/constants/default_categories.dart';
import 'package:sakuin/core/db/app_database.dart';
import 'package:sakuin/core/services/backup_service.dart';
import 'package:sakuin/core/utils/date_utils.dart';
import 'package:sakuin/features/report/export_service.dart';
import 'package:sakuin/features/report/report_providers.dart';

void main() {
  late AppDatabase db;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> createWallet(String name, int initialBalance) {
    return db
        .into(db.wallets)
        .insert(
          WalletsCompanion.insert(
            name: name,
            type: 'cash',
            icon: 'cash',
            color: 0xFF15803D,
            initialBalance: Value(initialBalance),
          ),
        );
  }

  group('Perhitungan Saldo Dompet & Transfer', () {
    test(
      'menghitung saldo awal + pemasukan - pengeluaran ± transfer - fee',
      () async {
        final cashId = await createWallet('Tunai', 500000);
        final bankId = await createWallet('BCA', 1000000);
        final foodCatId = await db.findCategoryIdByName(
          'Makanan & Minuman',
          'expense',
        );
        final salaryCatId = await db.findCategoryIdByName('Gaji', 'income');

        final now = DateTime(2026, 11, 23, 10, 0);

        // Pemasukan gaji Rp 3.000.000 ke BCA
        await db.saveTransactionWithMemory(
          type: 'income',
          amount: 3000000,
          walletId: bankId,
          categoryId: salaryCatId,
          itemName: 'Gaji November',
          occurredAt: now,
        );

        // Pengeluaran makan Rp 35.000 dari Tunai
        await db.saveTransactionWithMemory(
          type: 'expense',
          amount: 35000,
          walletId: cashId,
          categoryId: foodCatId,
          itemName: 'Ayam goreng',
          occurredAt: now,
        );

        // Transfer Rp 200.000 dari BCA ke Tunai + biaya admin Rp 2.500
        await db.saveTransactionWithMemory(
          type: 'transfer',
          amount: 200000,
          walletId: bankId,
          toWalletId: cashId,
          fee: 2500,
          occurredAt: now,
        );

        final cash = await db.getWalletWithBalance(cashId);
        final bank = await db.getWalletWithBalance(bankId);

        // Tunai: 500.000 - 35.000 + 200.000 = 665.000
        expect(cash?.balance, 665000);
        // BCA: 1.000.000 + 3.000.000 - 200.000 - 2.500 = 3.797.500
        expect(bank?.balance, 3797500);

        // Laporan periode: transfer BUKAN income/expense, tapi fee 2.500 masuk expense (Biaya Admin)
        final dayKey = AppDateUtils.toDayKey(now);
        final summary = await db.getPeriodSummary(dayKey, dayKey);
        expect(summary.income, 3000000);
        expect(summary.expense, 35000 + 2500);

        final breakdown = await db.getCategoryBreakdown(
          startDayKey: dayKey,
          endDayKey: dayKey,
          type: 'expense',
        );
        final adminRow = breakdown.firstWhere(
          (c) => c.categoryName == DefaultSeeds.adminFeeCategoryName,
        );
        expect(adminRow.total, 2500);
      },
    );
  });

  group('Logika Hutang-Piutang, Cicilan, & Efek Dompet', () {
    test(
      'cicilan parsial, otomatis lunas, efek dompet, tanpa masuk laporan',
      () async {
        final cashId = await createWallet('Tunai', 1000000);
        final budi = await db.findOrCreatePerson('Budi');
        final now = DateTime(2026, 11, 23, 12, 0);

        // Saya meminjamkan Rp 300.000 ke Budi (catat ke dompet -> Tunai berkurang 300k)
        final debtId = await db
            .into(db.debts)
            .insert(
              DebtsCompanion.insert(
                personId: budi.id,
                direction: 'they_owe',
                principal: 300000,
                createdAt: now.toUtc().millisecondsSinceEpoch,
                walletId: Value(cashId),
              ),
            );

        var wallet = await db.getWalletWithBalance(cashId);
        expect(wallet?.balance, 700000);

        // Budi cicil Rp 100.000 ke dompet Tunai -> saldo jadi 800k, status masih 'open'
        await db.addDebtPayment(
          debtId: debtId,
          amount: 100000,
          paidAt: now,
          walletId: cashId,
        );
        wallet = await db.getWalletWithBalance(cashId);
        expect(wallet?.balance, 800000);

        var debtList = await db.watchDebtsWithSummary().first;
        expect(debtList.first.debt.status, 'open');
        expect(debtList.first.remaining, 200000);

        // Budi melunasi sisa Rp 200.000 -> saldo kembali 1.000.000, status otomatis 'settled'
        await db.addDebtPayment(
          debtId: debtId,
          amount: 200000,
          paidAt: now,
          walletId: cashId,
        );
        wallet = await db.getWalletWithBalance(cashId);
        expect(wallet?.balance, 1000000);

        debtList = await db.watchDebtsWithSummary().first;
        expect(debtList.first.debt.status, 'settled');
        expect(debtList.first.remaining, 0);

        // Hutang-piutang BUKAN pemasukan/pengeluaran di laporan
        final dayKey = AppDateUtils.toDayKey(now);
        final summary = await db.getPeriodSummary(dayKey, dayKey);
        expect(summary.income, 0);
        expect(summary.expense, 0);
      },
    );

    test(
      'arah i_owe menambah dompet saat meminjam dan mengurangi saat membayar',
      () async {
        final cashId = await createWallet('Tunai', 100000);
        final andi = await db.findOrCreatePerson('Andi');
        final now = DateTime(2026, 11, 23);

        final debtId = await db
            .into(db.debts)
            .insert(
              DebtsCompanion.insert(
                personId: andi.id,
                direction: 'i_owe',
                principal: 250000,
                createdAt: now.toUtc().millisecondsSinceEpoch,
                walletId: Value(cashId),
              ),
            );
        expect((await db.getWalletWithBalance(cashId))?.balance, 350000);

        await db.addDebtPayment(
          debtId: debtId,
          amount: 100000,
          paidAt: now,
          walletId: cashId,
        );
        expect((await db.getWalletWithBalance(cashId))?.balance, 250000);
      },
    );
  });

  group('Item Memory (Auto-learn & Ranking)', () {
    test('normalisasi nama, akumulasi useCount, update nominal & prioritas pin', () async {
      final cashId = await createWallet('Tunai', 500000);
      final foodCatId = await db.findCategoryIdByName(
        'Makanan & Minuman',
        'expense',
      );
      final now = DateTime(2026, 11, 23);

      await db.saveTransactionWithMemory(
        type: 'expense',
        amount: 22000,
        walletId: cashId,
        categoryId: foodCatId,
        itemName: '  Ayam Goreng Merk A  ',
        note: 'Pedas',
        occurredAt: now,
      );

      // Simpan lagi dengan casing berbeda & nominal terbaru -> upsert ke baris yang sama
      await db.saveTransactionWithMemory(
        type: 'expense',
        amount: 25000,
        walletId: cashId,
        categoryId: foodCatId,
        itemName: 'ayam goreng merk a',
        note: 'Sedang',
        occurredAt: now.add(const Duration(hours: 2)),
      );

      await db.saveTransactionWithMemory(
        type: 'expense',
        amount: 18000,
        walletId: cashId,
        categoryId: foodCatId,
        itemName: 'Kopi Susu',
        occurredAt: now.add(const Duration(hours: 3)),
      );

      final matches = await db.searchItemMemory('ayam', type: 'expense');
      expect(matches.length, 1);
      expect(matches.first.useCount, 2);
      expect(matches.first.lastAmount, 25000);
      expect(matches.first.lastNote, 'Sedang');

      // Pin "Kopi Susu" -> muncul pertama di Item Cepat mengalahkan useCount=2
      final kopi = (await db.searchItemMemory('kopi')).first;
      await db.togglePinItemMemory(kopi.id, true);

      final quick = await db.watchQuickItems().first;
      expect(quick.first.displayName, 'Kopi Susu');
      expect(quick[1].useCount, 2);
    });
  });

  group('Backup & Restore JSON', () {
    test(
      'ekspor JSON, pratinjau, dan pulihkan kembali dengan akurat',
      () async {
        final backupService = BackupService(db);
        final cashId = await createWallet('Tunai', 200000);
        final foodCatId = await db.findCategoryIdByName(
          'Makanan & Minuman',
          'expense',
        );
        await db.saveTransactionWithMemory(
          type: 'expense',
          amount: 15000,
          walletId: cashId,
          categoryId: foodCatId,
          itemName: 'Bakso',
          occurredAt: DateTime(2026, 11, 23),
        );

        final jsonStr = await backupService.buildJsonBackup();
        final preview = backupService.parseBackupJson(jsonStr);
        expect(preview.walletCount, 1);
        expect(preview.transactionCount, 1);

        // Restore ke database baru yang kosong
        final db2 = AppDatabase(NativeDatabase.memory());
        addTearDown(db2.close);
        final restoreService = BackupService(db2);
        await restoreService.restoreBackup(preview, replaceExisting: true);

        final wallets = await db2.getWalletsWithBalances();
        expect(wallets.length, 1);
        expect(wallets.first.wallet.name, 'Tunai');
        expect(wallets.first.balance, 185000);
      },
    );
  });

  group('Ekspor Laporan CSV & PDF', () {
    test('menghasilkan CSV dan PDF valid tanpa error', () async {
      final cashId = await createWallet('Tunai', 200000);
      final foodCatId = await db.findCategoryIdByName(
        'Makanan & Minuman',
        'expense',
      );
      final date = DateTime(2026, 11, 23, 12, 30);
      await db.saveTransactionWithMemory(
        type: 'expense',
        amount: 25000,
        walletId: cashId,
        categoryId: foodCatId,
        itemName: 'Nasi Goreng',
        occurredAt: date,
      );

      final period = AppDateUtils.periodForDate(date, 1);
      final exporter = ReportExportService(db);

      final csv = await exporter.buildCsv(period);
      expect(csv, contains('Nasi Goreng'));
      expect(csv, contains('25000'));

      final pdfBytes = await exporter.buildPdfBytes(
        ReportData(
          period: period,
          previousPeriod: AppDateUtils.previousPeriod(period, 1),
          summary: const PeriodSummary(income: 0, expense: 25000),
          previousSummary: const PeriodSummary(income: 0, expense: 0),
          categories: const [],
          trend: const [],
        ),
      );
      expect(pdfBytes.length, greaterThan(100));
      expect(String.fromCharCodes(pdfBytes.take(5)), '%PDF-');
    });
  });
}
