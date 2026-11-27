import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sakuin/core/db/app_database.dart';
import 'package:sakuin/core/db/db_provider.dart';
import 'package:share_plus/share_plus.dart';

class BackupPreview {
  const BackupPreview({
    required this.schemaVersion,
    required this.exportedAt,
    required this.walletCount,
    required this.categoryCount,
    required this.transactionCount,
    required this.debtCount,
    required this.budgetCount,
    required this.recurringCount,
    required this.rawData,
  });

  final int schemaVersion;
  final DateTime? exportedAt;
  final int walletCount;
  final int categoryCount;
  final int transactionCount;
  final int debtCount;
  final int budgetCount;
  final int recurringCount;
  final Map<String, dynamic> rawData;
}

class BackupService {
  BackupService(this._db);

  static const int currentBackupVersion = 4;
  final AppDatabase _db;

  Future<String> buildJsonBackup() async {
    final wallets = await _db.select(_db.wallets).get();
    final pockets = await _db.select(_db.walletPockets).get();
    final pocketAllocations = await _db.select(_db.pocketAllocations).get();
    final categories = await _db.select(_db.categories).get();
    final transactions = await _db.select(_db.transactions).get();
    final itemMemory = await _db.select(_db.itemMemory).get();
    final merchantMemory = await _db.select(_db.merchantMemory).get();
    final recurringRules = await _db.select(_db.recurringRules).get();
    final people = await _db.select(_db.people).get();
    final debts = await _db.select(_db.debts).get();
    final debtPayments = await _db.select(_db.debtPayments).get();
    final budgets = await _db.select(_db.budgets).get();

    final payload = {
      'app': 'sakuin',
      'backup_version': currentBackupVersion,
      'db_schema_version': _db.schemaVersion,
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'data': {
        'wallets': wallets.map((e) => e.toJson()).toList(),
        'wallet_pockets': pockets.map((e) => e.toJson()).toList(),
        'pocket_allocations': pocketAllocations.map((e) => e.toJson()).toList(),
        'categories': categories.map((e) => e.toJson()).toList(),
        'transactions': transactions.map((e) => e.toJson()).toList(),
        'item_memory': itemMemory.map((e) => e.toJson()).toList(),
        'merchant_memory': merchantMemory.map((e) => e.toJson()).toList(),
        'recurring_rules': recurringRules.map((e) => e.toJson()).toList(),
        'people': people.map((e) => e.toJson()).toList(),
        'debts': debts.map((e) => e.toJson()).toList(),
        'debt_payments': debtPayments.map((e) => e.toJson()).toList(),
        'budgets': budgets.map((e) => e.toJson()).toList(),
      },
    };

    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  String _defaultBackupFilename() {
    final now = DateTime.now();
    final stamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    return 'sakuin_backup_$stamp.json';
  }

  /// Simpan lewat Storage Access Framework (pengguna bisa memilih Google Drive langsung).
  Future<String?> exportViaSaf() async {
    final jsonText = await buildJsonBackup();
    final bytes = Uint8List.fromList(utf8.encode(jsonText));
    final savedPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Simpan Cadangan Sakuin',
      fileName: _defaultBackupFilename(),
      type: FileType.custom,
      allowedExtensions: const ['json'],
      bytes: bytes,
    );
    return savedPath;
  }

  /// Bagikan lewat Share Sheet sistem (Google Drive, WhatsApp, Files, dll).
  Future<void> exportViaShareSheet() async {
    final jsonText = await buildJsonBackup();
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/${_defaultBackupFilename()}');
    await file.writeAsString(jsonText);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/json')],
        subject: 'Cadangan Data Sakuin',
        text: 'File cadangan data aplikasi Sakuin.',
      ),
    );
  }

  /// Pilih file cadangan `.json` dari perangkat atau Google Drive (SAF) dan pratinjau isinya.
  Future<BackupPreview?> pickAndPreviewBackup() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Pilih File Cadangan Sakuin',
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;

    final picked = result.files.first;
    String content;
    if (picked.bytes != null) {
      content = utf8.decode(picked.bytes!);
    } else if (picked.path != null) {
      content = await File(picked.path!).readAsString();
    } else {
      throw const FormatException('File cadangan tidak dapat dibaca.');
    }

    return parseBackupJson(content);
  }

  BackupPreview parseBackupJson(String content) {
    final decoded = jsonDecode(content);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Format file cadangan tidak valid.');
    }
    if (decoded['app'] != 'sakuin') {
      throw const FormatException('File ini bukan cadangan aplikasi Sakuin.');
    }
    final version = decoded['backup_version'];
    if (version is! int || version > currentBackupVersion) {
      throw FormatException(
        'Versi cadangan ($version) lebih baru dari aplikasi saat ini. Perbarui Sakuin terlebih dahulu.',
      );
    }
    final data = decoded['data'];
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Bagian data pada file cadangan rusak.');
    }

    List<dynamic> listOf(String k) =>
        (data[k] is List) ? data[k] as List<dynamic> : const [];

    return BackupPreview(
      schemaVersion: version,
      exportedAt: decoded['exported_at'] is String
          ? DateTime.tryParse(decoded['exported_at'] as String)?.toLocal()
          : null,
      walletCount: listOf('wallets').length,
      categoryCount: listOf('categories').length,
      transactionCount: listOf('transactions').length,
      debtCount: listOf('debts').length,
      budgetCount: listOf('budgets').length,
      recurringCount: listOf('recurring_rules').length,
      rawData: data,
    );
  }

  /// Restore data: [replaceExisting] = true menimpa seluruh data; false menggabungkan (merge).
  Future<void> restoreBackup(
    BackupPreview preview, {
    required bool replaceExisting,
  }) async {
    final data = preview.rawData;
    List<Map<String, dynamic>> tableRows(String key) {
      final raw = data[key];
      if (raw is! List) return const [];
      return raw.whereType<Map<String, dynamic>>().toList();
    }

    final walletRows = tableRows('wallets');
    final pocketRows = tableRows('wallet_pockets');
    final pocketAllocRows = tableRows('pocket_allocations');
    final categoryRows = tableRows('categories');
    final txRows = tableRows('transactions');
    final memoryRows = tableRows('item_memory');
    final merchantMemoryRows = tableRows('merchant_memory');
    final recurringRows = tableRows('recurring_rules');
    final peopleRows = tableRows('people');
    final debtRows = tableRows('debts');
    final debtPaymentRows = tableRows('debt_payments');
    final budgetRows = tableRows('budgets');

    await _db.transaction(() async {
      if (replaceExisting) {
        await _db.delete(_db.debtPayments).go();
        await _db.delete(_db.debts).go();
        await _db.delete(_db.people).go();
        await _db.delete(_db.budgets).go();
        await _db.delete(_db.recurringRules).go();
        await _db.delete(_db.merchantMemory).go();
        await _db.delete(_db.itemMemory).go();
        await _db.delete(_db.transactions).go();
        await _db.delete(_db.pocketAllocations).go();
        await _db.delete(_db.walletPockets).go();
        await _db.delete(_db.categories).go();
        await _db.delete(_db.wallets).go();

        for (final row in walletRows) {
          final w = Wallet.fromJson(row);
          await _db
              .into(_db.wallets)
              .insert(w, mode: InsertMode.insertOrReplace);
        }
        for (final row in pocketRows) {
          final pk = WalletPocket.fromJson(row);
          await _db
              .into(_db.walletPockets)
              .insert(pk, mode: InsertMode.insertOrReplace);
        }
        for (final row in pocketAllocRows) {
          final pa = PocketAllocation.fromJson(row);
          await _db
              .into(_db.pocketAllocations)
              .insert(pa, mode: InsertMode.insertOrReplace);
        }
        for (final row in categoryRows) {
          final c = Category.fromJson(row);
          await _db
              .into(_db.categories)
              .insert(c, mode: InsertMode.insertOrReplace);
        }
        for (final row in txRows) {
          final t = Transaction.fromJson(row);
          await _db
              .into(_db.transactions)
              .insert(t, mode: InsertMode.insertOrReplace);
        }
        for (final row in memoryRows) {
          final m = ItemMemoryData.fromJson(row);
          await _db
              .into(_db.itemMemory)
              .insert(m, mode: InsertMode.insertOrReplace);
        }
        for (final row in merchantMemoryRows) {
          final mm = MerchantMemoryData.fromJson(row);
          await _db
              .into(_db.merchantMemory)
              .insert(mm, mode: InsertMode.insertOrReplace);
        }
        for (final row in recurringRows) {
          final r = RecurringRule.fromJson(row);
          await _db
              .into(_db.recurringRules)
              .insert(r, mode: InsertMode.insertOrReplace);
        }
        for (final row in peopleRows) {
          final pe = Person.fromJson(row);
          await _db
              .into(_db.people)
              .insert(pe, mode: InsertMode.insertOrReplace);
        }
        for (final row in debtRows) {
          final d = Debt.fromJson(row);
          await _db.into(_db.debts).insert(d, mode: InsertMode.insertOrReplace);
        }
        for (final row in debtPaymentRows) {
          final dp = DebtPayment.fromJson(row);
          await _db
              .into(_db.debtPayments)
              .insert(dp, mode: InsertMode.insertOrReplace);
        }
        for (final row in budgetRows) {
          final b = Budget.fromJson(row);
          await _db
              .into(_db.budgets)
              .insert(b, mode: InsertMode.insertOrReplace);
        }
      } else {
        // Mode Gabung (Merge): petakan ID lama -> ID baru agar tidak bentrok
        final walletIdMap = <int, int>{};
        final existingWallets = await _db.select(_db.wallets).get();
        for (final row in walletRows) {
          final w = Wallet.fromJson(row);
          final match = existingWallets
              .where((e) => e.name.toLowerCase() == w.name.toLowerCase())
              .firstOrNull;
          if (match != null) {
            walletIdMap[w.id] = match.id;
          } else {
            final newId = await _db
                .into(_db.wallets)
                .insert(
                  WalletsCompanion.insert(
                    name: w.name,
                    type: w.type,
                    icon: w.icon,
                    color: w.color,
                    initialBalance: Value(w.initialBalance),
                    includeInTotal: Value(w.includeInTotal),
                    isArchived: Value(w.isArchived),
                    sortOrder: Value(w.sortOrder),
                  ),
                );
            walletIdMap[w.id] = newId;
          }
        }

        final pocketIdMap = <int, int>{};
        final existingPockets = await _db.select(_db.walletPockets).get();
        for (final row in pocketRows) {
          final pk = WalletPocket.fromJson(row);
          final mappedWallet = walletIdMap[pk.walletId];
          if (mappedWallet == null) continue;
          final match = existingPockets
              .where(
                (e) =>
                    e.walletId == mappedWallet &&
                    e.name.toLowerCase() == pk.name.toLowerCase(),
              )
              .firstOrNull;
          if (match != null) {
            pocketIdMap[pk.id] = match.id;
          } else {
            final newId = await _db
                .into(_db.walletPockets)
                .insert(
                  WalletPocketsCompanion.insert(
                    walletId: mappedWallet,
                    name: pk.name,
                    icon: pk.icon,
                    color: pk.color,
                    targetAmount: Value(pk.targetAmount),
                    sortOrder: Value(pk.sortOrder),
                    isArchived: Value(pk.isArchived),
                  ),
                );
            pocketIdMap[pk.id] = newId;
          }
        }

        for (final row in pocketAllocRows) {
          final pa = PocketAllocation.fromJson(row);
          final mappedWallet = walletIdMap[pa.walletId];
          if (mappedWallet == null) continue;
          await _db
              .into(_db.pocketAllocations)
              .insert(
                PocketAllocationsCompanion.insert(
                  walletId: mappedWallet,
                  fromPocketId: Value(
                    pa.fromPocketId == null
                        ? null
                        : pocketIdMap[pa.fromPocketId],
                  ),
                  toPocketId: Value(
                    pa.toPocketId == null ? null : pocketIdMap[pa.toPocketId],
                  ),
                  amount: pa.amount,
                  note: Value(pa.note),
                  createdAt: pa.createdAt,
                ),
              );
        }

        final categoryIdMap = <int, int>{};
        final existingCats = await _db.select(_db.categories).get();
        for (final row in categoryRows) {
          final c = Category.fromJson(row);
          final match = existingCats
              .where(
                (e) =>
                    e.type == c.type &&
                    e.name.toLowerCase() == c.name.toLowerCase(),
              )
              .firstOrNull;
          if (match != null) {
            categoryIdMap[c.id] = match.id;
          } else {
            final newId = await _db
                .into(_db.categories)
                .insert(
                  CategoriesCompanion.insert(
                    name: c.name,
                    type: c.type,
                    icon: c.icon,
                    color: c.color,
                    sortOrder: Value(c.sortOrder),
                    isArchived: Value(c.isArchived),
                  ),
                );
            categoryIdMap[c.id] = newId;
          }
        }

        for (final row in txRows) {
          final t = Transaction.fromJson(row);
          final mappedWallet = walletIdMap[t.walletId];
          if (mappedWallet == null) continue;
          await _db
              .into(_db.transactions)
              .insert(
                TransactionsCompanion.insert(
                  type: t.type,
                  amount: t.amount,
                  categoryId: Value(
                    t.categoryId == null ? null : categoryIdMap[t.categoryId],
                  ),
                  walletId: mappedWallet,
                  toWalletId: Value(
                    t.toWalletId == null ? null : walletIdMap[t.toWalletId],
                  ),
                  pocketId: Value(
                    t.pocketId == null ? null : pocketIdMap[t.pocketId],
                  ),
                  toPocketId: Value(
                    t.toPocketId == null ? null : pocketIdMap[t.toPocketId],
                  ),
                  fee: Value(t.fee),
                  note: Value(t.note),
                  itemName: Value(t.itemName),
                  merchantName: Value(t.merchantName),
                  splitGroupId: Value(t.splitGroupId),
                  externalRef: Value(t.externalRef),
                  occurredAt: t.occurredAt,
                  dayKey: t.dayKey,
                  createdAt: t.createdAt,
                  updatedAt: t.updatedAt,
                ),
              );
        }

        for (final row in memoryRows) {
          final m = ItemMemoryData.fromJson(row);
          await _db.upsertItemMemory(
            displayName: m.displayName,
            type: m.type,
            amount: m.lastAmount,
            merchantName: m.lastMerchantName,
            categoryId: m.lastCategoryId == null
                ? null
                : categoryIdMap[m.lastCategoryId],
            walletId: m.lastWalletId == null
                ? null
                : walletIdMap[m.lastWalletId],
            pocketId: m.lastPocketId == null
                ? null
                : pocketIdMap[m.lastPocketId],
            note: m.lastNote,
            isPinned: m.isPinned,
          );
        }

        for (final row in merchantMemoryRows) {
          final mm = MerchantMemoryData.fromJson(row);
          await _db.upsertMerchantMemory(
            displayMerchant: mm.displayMerchant,
            type: mm.type,
            itemName: mm.lastItemName,
            amount: mm.lastAmount,
            categoryId: mm.lastCategoryId == null
                ? null
                : categoryIdMap[mm.lastCategoryId],
            walletId: mm.lastWalletId == null
                ? null
                : walletIdMap[mm.lastWalletId],
            pocketId: mm.lastPocketId == null
                ? null
                : pocketIdMap[mm.lastPocketId],
            note: mm.lastNote,
          );
        }

        final peopleIdMap = <int, int>{};
        for (final row in peopleRows) {
          final pe = Person.fromJson(row);
          final created = await _db.findOrCreatePerson(
            pe.name,
            phone: pe.phone,
          );
          peopleIdMap[pe.id] = created.id;
        }

        final debtIdMap = <int, int>{};
        for (final row in debtRows) {
          final d = Debt.fromJson(row);
          final mappedPerson = peopleIdMap[d.personId];
          if (mappedPerson == null) continue;
          final newId = await _db
              .into(_db.debts)
              .insert(
                DebtsCompanion.insert(
                  personId: mappedPerson,
                  direction: d.direction,
                  principal: d.principal,
                  note: Value(d.note),
                  createdAt: d.createdAt,
                  dueDate: Value(d.dueDate),
                  walletId: Value(
                    d.walletId == null ? null : walletIdMap[d.walletId],
                  ),
                  status: Value(d.status),
                ),
              );
          debtIdMap[d.id] = newId;
        }

        for (final row in debtPaymentRows) {
          final dp = DebtPayment.fromJson(row);
          final mappedDebt = debtIdMap[dp.debtId];
          if (mappedDebt == null) continue;
          await _db
              .into(_db.debtPayments)
              .insert(
                DebtPaymentsCompanion.insert(
                  debtId: mappedDebt,
                  amount: dp.amount,
                  paidAt: dp.paidAt,
                  walletId: Value(
                    dp.walletId == null ? null : walletIdMap[dp.walletId],
                  ),
                  note: Value(dp.note),
                ),
              );
        }
      }
    });
  }
}

final backupServiceProvider = Provider<BackupService>((ref) {
  return BackupService(ref.watch(appDatabaseProvider));
});
