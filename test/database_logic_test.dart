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

  group('Pos Budget di Dalam Satu Saku (Wallet Pockets)', () {
    test('membagi saldo Mandiri 500k -> Harian 200k + Tabungan 300k, pindah pos, transfer lintas saku, & transaksi per pos', () async {
      final mandiriId = await createWallet('Mandiri', 500000);
      final bcaId = await createWallet('BCA', 1000000);

      final harianId = await db
          .into(db.walletPockets)
          .insert(
            WalletPocketsCompanion.insert(
              walletId: mandiriId,
              name: 'Uang Harian',
              icon: 'food',
              color: 0xFFEA580C,
            ),
          );
      final tabunganId = await db
          .into(db.walletPockets)
          .insert(
            WalletPocketsCompanion.insert(
              walletId: mandiriId,
              name: 'Tabungan',
              icon: 'savings',
              color: 0xFF15803D,
            ),
          );

      // 1. Alokasi manual: 200k ke Uang Harian & 300k ke Tabungan
      await db.allocateOrMovePocket(
        walletId: mandiriId,
        fromPocketId: null,
        toPocketId: harianId,
        amount: 200000,
      );
      await db.allocateOrMovePocket(
        walletId: mandiriId,
        fromPocketId: null,
        toPocketId: tabunganId,
        amount: 300000,
      );

      var pockets = await db.getPocketsForWallet(mandiriId);
      expect(
        pockets.firstWhere((p) => p.pocket.id == harianId).balance,
        200000,
      );
      expect(
        pockets.firstWhere((p) => p.pocket.id == tabunganId).balance,
        300000,
      );
      expect(await db.getWalletUnallocatedBalance(mandiriId), 0);
      expect((await db.getWalletWithBalance(mandiriId))?.balance, 500000);

      // 2. Transfer antar budget di saku yang sama (Harian -> Tabungan 50k)
      await db.allocateOrMovePocket(
        walletId: mandiriId,
        fromPocketId: harianId,
        toPocketId: tabunganId,
        amount: 50000,
      );
      pockets = await db.getPocketsForWallet(mandiriId);
      expect(
        pockets.firstWhere((p) => p.pocket.id == harianId).balance,
        150000,
      );
      expect(
        pockets.firstWhere((p) => p.pocket.id == tabunganId).balance,
        350000,
      );
      expect((await db.getWalletWithBalance(mandiriId))?.balance, 500000);

      // 3. Transfer dari saku lain (BCA -> Mandiri: Tabungan Rp 100k, fee 2.5k)
      final now = DateTime(2026, 11, 26, 10, 0);
      await db.saveTransactionWithMemory(
        type: 'transfer',
        amount: 100000,
        walletId: bcaId,
        toWalletId: mandiriId,
        toPocketId: tabunganId,
        fee: 2500,
        occurredAt: now,
        updateItemMemory: false,
      );
      pockets = await db.getPocketsForWallet(mandiriId);
      expect(
        pockets.firstWhere((p) => p.pocket.id == tabunganId).balance,
        450000,
      );
      expect((await db.getWalletWithBalance(mandiriId))?.balance, 600000);
      expect((await db.getWalletWithBalance(bcaId))?.balance, 897500);

      // 4. Pengeluaran 25k dari Mandiri -> Uang Harian
      final foodCatId = await db.findCategoryIdByName(
        'Makanan & Minuman',
        'expense',
      );
      await db.saveTransactionWithMemory(
        type: 'expense',
        amount: 25000,
        walletId: mandiriId,
        pocketId: harianId,
        categoryId: foodCatId,
        itemName: 'Makan siang',
        occurredAt: now,
      );
      pockets = await db.getPocketsForWallet(mandiriId);
      expect(
        pockets.firstWhere((p) => p.pocket.id == harianId).balance,
        125000,
      );
      expect((await db.getWalletWithBalance(mandiriId))?.balance, 575000);
      expect(await db.getWalletUnallocatedBalance(mandiriId), 0);

      // 5. Backup & Restore v2 mempertahankan seluruh pos budget & saldonya
      final backupSvc = BackupService(db);
      final json = await backupSvc.buildJsonBackup();
      final preview = backupSvc.parseBackupJson(json);

      final db2 = AppDatabase(NativeDatabase.memory());
      addTearDown(db2.close);
      await BackupService(db2).restoreBackup(preview, replaceExisting: true);
      final restoredPockets = await db2.getPocketsForWallet(mandiriId);
      expect(restoredPockets.length, 2);
      expect(
        restoredPockets.firstWhere((p) => p.pocket.id == tabunganId).balance,
        450000,
      );
      expect(
        restoredPockets.firstWhere((p) => p.pocket.id == harianId).balance,
        125000,
      );
    });

    test(
      'watchAllActivePockets mengabaikan pos dari dompet yang sudah diarsipkan',
      () async {
        final aktifId = await createWallet('Mandiri', 500000);
        final arsipId = await createWallet('Dompet Lama', 800000);

        final tabAktifId = await db
            .into(db.walletPockets)
            .insert(
              WalletPocketsCompanion.insert(
                walletId: aktifId,
                name: 'Tabungan',
                icon: 'savings',
                color: 0xFF15803D,
              ),
            );
        final tabArsipId = await db
            .into(db.walletPockets)
            .insert(
              WalletPocketsCompanion.insert(
                walletId: arsipId,
                name: 'Tabungan',
                icon: 'savings',
                color: 0xFF15803D,
              ),
            );

        await db.allocateOrMovePocket(
          walletId: aktifId,
          fromPocketId: null,
          toPocketId: tabAktifId,
          amount: 300000,
        );
        await db.allocateOrMovePocket(
          walletId: arsipId,
          fromPocketId: null,
          toPocketId: tabArsipId,
          amount: 600000,
        );

        // Sebelum diarsipkan, kedua pos Tabungan masuk (total 900 rb)
        var activePockets = await db.watchAllActivePockets().first;
        expect(activePockets.length, 2);

        // Arsipkan Dompet Lama -> hanya pos dari Mandiri (300 rb) yang boleh muncul
        await (db.update(db.wallets)..where((w) => w.id.equals(arsipId))).write(
          const WalletsCompanion(isArchived: Value(true)),
        );

        activePockets = await db.watchAllActivePockets().first;
        expect(activePockets.length, 1);
        expect(activePockets.first.pocket.walletId, aktifId);
        expect(activePockets.first.balance, 300000);
      },
    );
  });

  group('Pecah Transaksi (Split Komponen) & Antrean QRIS', () {
    test('memecah transaksi 20k jadi Es Teh 5k + Nasi Ayam Geprek 15k tanpa dobel hitung & ingat Item Memory', () async {
      final mandiriId = await createWallet('Mandiri', 500000);
      final foodCatId = await db.findCategoryIdByName(
        'Makanan & Minuman',
        'expense',
      );
      final shopCatId = await db.findCategoryIdByName('Belanja', 'expense');
      final now = DateTime(2026, 11, 26, 12, 0);

      // Simpan transaksi tunggal 20k (mis. hasil QRIS)
      final origTxId = await db.saveTransactionWithMemory(
        type: 'expense',
        amount: 20000,
        walletId: mandiriId,
        categoryId: foodCatId,
        itemName: 'WARUNG GEPREK',
        externalRef: 'gmail_uid:999',
        occurredAt: now,
      );
      expect((await db.getWalletWithBalance(mandiriId))?.balance, 480000);

      // Pecah menjadi 2 komponen: 5k Es Teh + 15k Nasi Ayam Geprek
      final groupId = await db.saveSplitTransactions(
        type: 'expense',
        walletId: mandiriId,
        occurredAt: now,
        replaceSingleTransactionId: origTxId,
        components: [
          SplitComponentInput(
            itemName: 'Es Teh',
            amount: 5000,
            categoryId: foodCatId,
            note: 'QRIS WARUNG GEPREK',
          ),
          SplitComponentInput(
            itemName: 'Nasi Ayam Geprek',
            amount: 15000,
            categoryId: shopCatId,
            note: 'QRIS WARUNG GEPREK',
          ),
        ],
      );

      // Saldo Mandiri tetap 480.000 (tidak dobel hitung!)
      expect((await db.getWalletWithBalance(mandiriId))?.balance, 480000);

      // Laporan periode tepat 20.000
      final dayKey = AppDateUtils.toDayKey(now);
      final summary = await db.getPeriodSummary(dayKey, dayKey);
      expect(summary.expense, 20000);

      // Kedua komponen tersimpan dengan splitGroupId & externalRef tetap terjaga
      final siblings = await db.getTransactionsBySplitGroup(groupId);
      expect(siblings.length, 2);
      expect(siblings.every((t) => t.externalRef == 'gmail_uid:999'), isTrue);

      // Item memory mengingat Es Teh & Nasi Ayam Geprek
      final memEsTeh = await db.searchItemMemory('es teh');
      final memGeprek = await db.searchItemMemory('geprek');
      expect(memEsTeh.first.lastAmount, 5000);
      expect(memGeprek.first.lastAmount, 15000);

      // Dedup antrean QRIS: emailUid yang sama tidak masuk dua kali
      final firstDraft = await db.insertQrisDraftIfNew(
        emailUid: 'gmail_uid:777',
        sender: 'livin@bankmandiri.co.id',
        subject: 'Transaksi QRIS Berhasil',
        bankName: 'Mandiri',
        merchantName: 'WARUNG GEPREK',
        amount: 20000,
        occurredAt: now,
        suggestedWalletId: mandiriId,
      );
      final dupDraft = await db.insertQrisDraftIfNew(
        emailUid: 'gmail_uid:777',
        sender: 'livin@bankmandiri.co.id',
        subject: 'Transaksi QRIS Berhasil',
        bankName: 'Mandiri',
        merchantName: 'WARUNG GEPREK',
        amount: 20000,
        occurredAt: now,
        suggestedWalletId: mandiriId,
      );
      expect(firstDraft, isNotNull);
      expect(dupDraft, isNull);
    });
  });
}
