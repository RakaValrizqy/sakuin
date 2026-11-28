import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sakuin/core/constants/default_categories.dart';
import 'package:sakuin/core/utils/date_utils.dart';

part 'app_database.g.dart';

// ---------------------------------------------------------------------------
// Tables
// ---------------------------------------------------------------------------

class Wallets extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get type => text()(); // cash | bank | ewallet | other
  TextColumn get icon => text()();
  IntColumn get color => integer()();
  IntColumn get initialBalance => integer().withDefault(const Constant(0))();
  BoolColumn get includeInTotal =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
}

class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get type => text()(); // income | expense
  TextColumn get icon => text()();
  IntColumn get color => integer()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
}

@TableIndex(name: 'idx_wallet_pockets_wallet_id', columns: {#walletId})
class WalletPockets extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get walletId => integer().references(Wallets, #id)();
  TextColumn get name => text()();
  TextColumn get icon => text()();
  IntColumn get color => integer()();
  IntColumn get targetAmount => integer().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
}

@TableIndex(name: 'idx_pocket_alloc_wallet_id', columns: {#walletId})
@TableIndex(name: 'idx_pocket_alloc_from', columns: {#fromPocketId})
@TableIndex(name: 'idx_pocket_alloc_to', columns: {#toPocketId})
class PocketAllocations extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get walletId => integer().references(Wallets, #id)();
  @ReferenceName('outgoingAllocations')
  IntColumn get fromPocketId =>
      integer().nullable().references(WalletPockets, #id)();
  @ReferenceName('incomingAllocations')
  IntColumn get toPocketId =>
      integer().nullable().references(WalletPockets, #id)();
  IntColumn get amount => integer()();
  TextColumn get note => text().withDefault(const Constant(''))();
  IntColumn get createdAt => integer()();
}

@TableIndex(name: 'idx_tx_day_key', columns: {#dayKey})
@TableIndex(name: 'idx_tx_wallet_id', columns: {#walletId})
@TableIndex(name: 'idx_tx_to_wallet_id', columns: {#toWalletId})
@TableIndex(name: 'idx_tx_pocket_id', columns: {#pocketId})
@TableIndex(name: 'idx_tx_to_pocket_id', columns: {#toPocketId})
@TableIndex(name: 'idx_tx_category_id', columns: {#categoryId})
@TableIndex(name: 'idx_tx_type_day_key', columns: {#type, #dayKey})
@TableIndex(name: 'idx_tx_occurred_at', columns: {#occurredAt})
@TableIndex(name: 'idx_tx_split_group_id', columns: {#splitGroupId})
class Transactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get type => text()(); // income | expense | transfer
  IntColumn get amount => integer()();
  IntColumn get categoryId =>
      integer().nullable().references(Categories, #id)();
  @ReferenceName('outgoingTransactions')
  IntColumn get walletId => integer().references(Wallets, #id)();
  @ReferenceName('incomingTransactions')
  IntColumn get toWalletId => integer().nullable().references(Wallets, #id)();
  @ReferenceName('pocketTransactions')
  IntColumn get pocketId =>
      integer().nullable().references(WalletPockets, #id)();
  @ReferenceName('incomingPocketTransactions')
  IntColumn get toPocketId =>
      integer().nullable().references(WalletPockets, #id)();
  IntColumn get fee => integer().withDefault(const Constant(0))();
  TextColumn get note => text().withDefault(const Constant(''))();
  TextColumn get itemName => text().nullable()();
  TextColumn get merchantName => text().nullable()();
  TextColumn get splitGroupId => text().nullable()();
  TextColumn get externalRef => text().nullable()();
  IntColumn get occurredAt => integer()(); // UTC epoch millis
  IntColumn get dayKey => integer()(); // Local yyyymmdd
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
}

@TableIndex(name: 'idx_qris_drafts_status', columns: {#status})
class ImportedQrisDrafts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get emailUid => text().unique()();
  TextColumn get sender => text()();
  TextColumn get subject => text()();
  TextColumn get bankName => text()();
  TextColumn get merchantName => text()();
  IntColumn get amount => integer()();
  IntColumn get occurredAt => integer()(); // UTC epoch millis
  IntColumn get suggestedWalletId =>
      integer().nullable().references(Wallets, #id)();
  TextColumn get rawSnippet => text().withDefault(const Constant(''))();
  TextColumn get txType =>
      text().withDefault(const Constant('expense'))(); // expense | income
  TextColumn get status => text().withDefault(
    const Constant('pending'),
  )(); // pending | confirmed | dismissed
  IntColumn get createdAt => integer()();
}

@TableIndex(
  name: 'idx_item_memory_rank',
  columns: {#isPinned, #useCount, #lastUsedAt},
)
class ItemMemory extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get nameNormalized => text().unique()();
  TextColumn get displayName => text()();
  TextColumn get type => text()(); // income | expense
  IntColumn get lastAmount => integer()();
  TextColumn get lastMerchantName => text().nullable()();
  IntColumn get lastCategoryId =>
      integer().nullable().references(Categories, #id)();
  IntColumn get lastWalletId => integer().nullable().references(Wallets, #id)();
  IntColumn get lastPocketId =>
      integer().nullable().references(WalletPockets, #id)();
  TextColumn get lastNote => text().withDefault(const Constant(''))();
  IntColumn get useCount => integer().withDefault(const Constant(1))();
  IntColumn get lastUsedAt => integer()();
  BoolColumn get isPinned => boolean().withDefault(const Constant(false))();
}

@TableIndex(name: 'idx_merchant_memory_rank', columns: {#useCount, #lastUsedAt})
class MerchantMemory extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get merchantNormalized => text().unique()();
  TextColumn get displayMerchant => text()();
  TextColumn get type => text().withDefault(const Constant('expense'))();
  TextColumn get lastItemName => text().nullable()();
  IntColumn get lastAmount => integer()();
  IntColumn get lastCategoryId =>
      integer().nullable().references(Categories, #id)();
  IntColumn get lastWalletId => integer().nullable().references(Wallets, #id)();
  IntColumn get lastPocketId =>
      integer().nullable().references(WalletPockets, #id)();
  TextColumn get lastNote => text().withDefault(const Constant(''))();
  IntColumn get useCount => integer().withDefault(const Constant(1))();
  IntColumn get lastUsedAt => integer()();
}

class RecurringRules extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text()();
  TextColumn get type => text()(); // income | expense
  IntColumn get amount => integer()();
  IntColumn get categoryId =>
      integer().nullable().references(Categories, #id)();
  IntColumn get walletId => integer().references(Wallets, #id)();
  TextColumn get note => text().withDefault(const Constant(''))();
  TextColumn get frequency => text()(); // daily | weekly | monthly
  IntColumn get dayOfWeek => integer().nullable()(); // 1 (Mon) .. 7 (Sun)
  IntColumn get dayOfMonth => integer().nullable()(); // 1 .. 28
  IntColumn get nextDue => integer()(); // yyyymmdd
  BoolColumn get autoCreate => boolean().withDefault(const Constant(true))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
}

@DataClassName('Person')
class People extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get phone => text().nullable()();
  TextColumn get note => text().withDefault(const Constant(''))();
}

@TableIndex(name: 'idx_debts_person_id', columns: {#personId})
@TableIndex(name: 'idx_debts_status', columns: {#status})
@TableIndex(name: 'idx_debts_wallet_id', columns: {#walletId})
class Debts extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get personId => integer().references(People, #id)();
  TextColumn get direction => text()(); // i_owe | they_owe
  IntColumn get principal => integer()();
  TextColumn get note => text().withDefault(const Constant(''))();
  IntColumn get createdAt => integer()();
  IntColumn get dueDate => integer().nullable()(); // UTC epoch millis
  IntColumn get walletId => integer().nullable().references(Wallets, #id)();
  TextColumn get status =>
      text().withDefault(const Constant('open'))(); // open | settled
}

@TableIndex(name: 'idx_debt_payments_debt_id', columns: {#debtId})
@TableIndex(name: 'idx_debt_payments_wallet_id', columns: {#walletId})
class DebtPayments extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get debtId =>
      integer().references(Debts, #id, onDelete: KeyAction.cascade)();
  IntColumn get amount => integer()();
  IntColumn get paidAt => integer()();
  IntColumn get walletId => integer().nullable().references(Wallets, #id)();
  TextColumn get note => text().withDefault(const Constant(''))();
}

class Budgets extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get categoryId =>
      integer().nullable().references(Categories, #id)(); // null = total
  IntColumn get amount => integer()();
  TextColumn get periodType => text().withDefault(const Constant('monthly'))();
}

// ---------------------------------------------------------------------------
// DTOs for SQL Aggregate Queries
// ---------------------------------------------------------------------------

class WalletWithBalance {
  const WalletWithBalance({required this.wallet, required this.balance});

  final Wallet wallet;
  final int balance;
}

class PocketWithBalance {
  const PocketWithBalance({required this.pocket, required this.balance});

  final WalletPocket pocket;
  final int balance;

  double? get targetProgress {
    final target = pocket.targetAmount;
    if (target == null || target <= 0) return null;
    return (balance / target).clamp(0.0, 1.0);
  }
}

class TransactionDetail {
  const TransactionDetail({
    required this.transaction,
    required this.wallet,
    this.toWallet,
    this.category,
    this.pocketName,
    this.toPocketName,
  });

  final Transaction transaction;
  final Wallet wallet;
  final Wallet? toWallet;
  final Category? category;
  final String? pocketName;
  final String? toPocketName;
}

class PeriodSummary {
  const PeriodSummary({required this.income, required this.expense});

  final int income;
  final int expense;

  int get net => income - expense;
}

class CategoryAggregate {
  const CategoryAggregate({
    required this.categoryId,
    required this.categoryName,
    required this.icon,
    required this.color,
    required this.total,
    required this.count,
  });

  final int? categoryId;
  final String categoryName;
  final String icon;
  final int color;
  final int total;
  final int count;
}

class DailyTrendPoint {
  const DailyTrendPoint({
    required this.dayKey,
    required this.income,
    required this.expense,
  });

  final int dayKey;
  final int income;
  final int expense;
}

class DebtWithSummary {
  const DebtWithSummary({
    required this.debt,
    required this.person,
    required this.paidTotal,
    this.walletName,
  });

  final Debt debt;
  final Person person;
  final int paidTotal;
  final String? walletName;

  int get remaining => (debt.principal - paidTotal).clamp(0, debt.principal);
  double get progress =>
      debt.principal <= 0 ? 1.0 : (paidTotal / debt.principal).clamp(0.0, 1.0);
  bool get isOverdue =>
      debt.status == 'open' &&
      debt.dueDate != null &&
      DateTime.fromMillisecondsSinceEpoch(debt.dueDate!)
          .isBefore(DateTime.now());
}

class PersonDebtSummary {
  const PersonDebtSummary({
    required this.person,
    required this.iOweRemaining,
    required this.theyOweRemaining,
    required this.openCount,
  });

  final Person person;
  final int iOweRemaining;
  final int theyOweRemaining;
  final int openCount;

  /// Positif = mereka berutang ke saya; Negatif = saya berutang ke mereka.
  int get netTheyOwe => theyOweRemaining - iOweRemaining;
}

// ---------------------------------------------------------------------------
// Database
// ---------------------------------------------------------------------------

class SplitComponentInput {
  const SplitComponentInput({
    required this.itemName,
    required this.amount,
    this.categoryId,
    this.pocketId,
    this.note = '',
  });

  final String itemName;
  final int amount;
  final int? categoryId;
  final int? pocketId;
  final String note;
}

@DriftDatabase(
  tables: [
    Wallets,
    WalletPockets,
    PocketAllocations,
    Categories,
    Transactions,
    ItemMemory,
    MerchantMemory,
    RecurringRules,
    People,
    Debts,
    DebtPayments,
    Budgets,
    ImportedQrisDrafts,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  /// Versi skema Drift. Naikkan angka ini saat menambah/mengubah tabel di masa depan
  /// dan tambahkan langkah migrasi non-destruktif di [migration.onUpgrade]
  /// agar update APK tanpa uninstall tetap mempertahankan seluruh data pengguna.
  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _seedDefaultCategories();
    },
    onUpgrade: (m, from, to) async {
      // Migrasi bertahap non-destruktif — JANGAN pernah drop tabel pengguna.
      if (from < 2) {
        await m.createTable(walletPockets);
        await m.createTable(pocketAllocations);
        await m.addColumn(transactions, transactions.pocketId);
        await m.addColumn(transactions, transactions.toPocketId);
        await m.addColumn(itemMemory, itemMemory.lastPocketId);
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_wallet_pockets_wallet_id ON wallet_pockets (wallet_id)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_pocket_alloc_wallet_id ON pocket_allocations (wallet_id)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_pocket_alloc_from ON pocket_allocations (from_pocket_id)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_pocket_alloc_to ON pocket_allocations (to_pocket_id)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_tx_pocket_id ON transactions (pocket_id)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_tx_to_pocket_id ON transactions (to_pocket_id)',
        );
      }
      if (from < 3) {
        await m.addColumn(transactions, transactions.splitGroupId);
        await m.addColumn(transactions, transactions.externalRef);
        await m.createTable(importedQrisDrafts);
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_tx_split_group_id ON transactions (split_group_id)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_qris_drafts_status ON imported_qris_drafts (status)',
        );
      }
      if (from < 4) {
        await m.addColumn(transactions, transactions.merchantName);
        await m.addColumn(itemMemory, itemMemory.lastMerchantName);
        await m.addColumn(importedQrisDrafts, importedQrisDrafts.txType);
        await m.createTable(merchantMemory);
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_merchant_memory_rank ON merchant_memory (use_count, last_used_at)',
        );
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await customStatement('PRAGMA journal_mode = WAL');
      // Pastikan kategori default tersedia jika tabel kosong (mis. setelah restore parsial)
      final catCount = await _countCategories();
      if (catCount == 0) {
        await _seedDefaultCategories();
      }
    },
  );

  Future<int> _countCategories() async {
    final row = await customSelect('SELECT COUNT(*) AS c FROM categories')
        .getSingle();
    return row.read<int>('c');
  }

  Future<void> _seedDefaultCategories() async {
    await batch((b) {
      for (final seed in DefaultSeeds.categories) {
        b.insert(
          categories,
          CategoriesCompanion.insert(
            name: seed.name,
            type: seed.type,
            icon: seed.icon,
            color: seed.color,
            sortOrder: Value(seed.sortOrder),
          ),
        );
      }
    });
  }

  // -------------------------------------------------------------------------
  // Wallets (SQL-aggregated balances)
  // -------------------------------------------------------------------------

  static const String _walletBalanceSql = '''
SELECT
  w.id,
  w.name,
  w.type,
  w.icon,
  w.color,
  w.initial_balance,
  w.include_in_total,
  w.is_archived,
  w.sort_order,
  w.initial_balance
  + COALESCE((SELECT SUM(t.amount) FROM transactions t WHERE t.wallet_id = w.id AND t.type = 'income'), 0)
  - COALESCE((SELECT SUM(t.amount) FROM transactions t WHERE t.wallet_id = w.id AND t.type = 'expense'), 0)
  - COALESCE((SELECT SUM(t.amount + t.fee) FROM transactions t WHERE t.wallet_id = w.id AND t.type = 'transfer'), 0)
  + COALESCE((SELECT SUM(t.amount) FROM transactions t WHERE t.to_wallet_id = w.id AND t.type = 'transfer'), 0)
  + COALESCE((SELECT SUM(CASE WHEN d.direction = 'i_owe' THEN d.principal ELSE -d.principal END) FROM debts d WHERE d.wallet_id = w.id), 0)
  + COALESCE((SELECT SUM(CASE WHEN d.direction = 'they_owe' THEN dp.amount ELSE -dp.amount END) FROM debt_payments dp INNER JOIN debts d ON d.id = dp.debt_id WHERE dp.wallet_id = w.id), 0)
  AS balance
FROM wallets w
''';

  WalletWithBalance _mapWalletBalanceRow(QueryRow row) {
    final wallet = Wallet(
      id: row.read<int>('id'),
      name: row.read<String>('name'),
      type: row.read<String>('type'),
      icon: row.read<String>('icon'),
      color: row.read<int>('color'),
      initialBalance: row.read<int>('initial_balance'),
      includeInTotal: row.read<bool>('include_in_total'),
      isArchived: row.read<bool>('is_archived'),
      sortOrder: row.read<int>('sort_order'),
    );
    return WalletWithBalance(wallet: wallet, balance: row.read<int>('balance'));
  }

  Stream<List<WalletWithBalance>> watchWalletsWithBalances({
    bool includeArchived = false,
  }) {
    final whereClause = includeArchived ? '' : 'WHERE w.is_archived = 0';
    final sql =
        '$_walletBalanceSql $whereClause ORDER BY w.sort_order ASC, w.id ASC';
    return customSelect(
      sql,
      readsFrom: {wallets, transactions, debts, debtPayments},
    ).watch().map((rows) => rows.map(_mapWalletBalanceRow).toList());
  }

  Future<List<WalletWithBalance>> getWalletsWithBalances({
    bool includeArchived = false,
  }) async {
    final whereClause = includeArchived ? '' : 'WHERE w.is_archived = 0';
    final sql =
        '$_walletBalanceSql $whereClause ORDER BY w.sort_order ASC, w.id ASC';
    final rows = await customSelect(sql).get();
    return rows.map(_mapWalletBalanceRow).toList();
  }

  Future<WalletWithBalance?> getWalletWithBalance(int walletId) async {
    final sql = '$_walletBalanceSql WHERE w.id = ?';
    final rows = await customSelect(
      sql,
      variables: [Variable.withInt(walletId)],
    ).get();
    if (rows.isEmpty) return null;
    return _mapWalletBalanceRow(rows.first);
  }

  Future<int> countWalletReferences(int walletId) async {
    final row = await customSelect(
      '''
      SELECT
        (SELECT COUNT(*) FROM transactions WHERE wallet_id = ? OR to_wallet_id = ?) +
        (SELECT COUNT(*) FROM debts WHERE wallet_id = ?) +
        (SELECT COUNT(*) FROM debt_payments WHERE wallet_id = ?) +
        (SELECT COUNT(*) FROM recurring_rules WHERE wallet_id = ?) AS total
      ''',
      variables: [
        Variable.withInt(walletId),
        Variable.withInt(walletId),
        Variable.withInt(walletId),
        Variable.withInt(walletId),
        Variable.withInt(walletId),
      ],
    ).getSingle();
    return row.read<int>('total');
  }

  Future<void> reorderWallets(List<int> orderedIds) async {
    await transaction(() async {
      for (var i = 0; i < orderedIds.length; i++) {
        await (update(wallets)..where((w) => w.id.equals(orderedIds[i]))).write(
          WalletsCompanion(sortOrder: Value(i)),
        );
      }
    });
  }

  // -------------------------------------------------------------------------
  // Wallet Pockets / Pos Budget di dalam Saku (SQL-aggregated balances)
  // -------------------------------------------------------------------------

  static const String _pocketBalanceSql = '''
SELECT
  p.id,
  p.wallet_id,
  p.name,
  p.icon,
  p.color,
  p.target_amount,
  p.sort_order,
  p.is_archived,
  COALESCE((SELECT SUM(pa.amount) FROM pocket_allocations pa WHERE pa.to_pocket_id = p.id), 0)
  - COALESCE((SELECT SUM(pa.amount) FROM pocket_allocations pa WHERE pa.from_pocket_id = p.id), 0)
  + COALESCE((SELECT SUM(t.amount) FROM transactions t WHERE t.pocket_id = p.id AND t.type = 'income'), 0)
  - COALESCE((SELECT SUM(t.amount) FROM transactions t WHERE t.pocket_id = p.id AND t.type = 'expense'), 0)
  - COALESCE((SELECT SUM(t.amount + t.fee) FROM transactions t WHERE t.pocket_id = p.id AND t.type = 'transfer'), 0)
  + COALESCE((SELECT SUM(t.amount) FROM transactions t WHERE t.to_pocket_id = p.id AND t.type = 'transfer'), 0)
  AS balance
FROM wallet_pockets p
''';

  PocketWithBalance _mapPocketBalanceRow(QueryRow r) {
    final pocket = WalletPocket(
      id: r.read<int>('id'),
      walletId: r.read<int>('wallet_id'),
      name: r.read<String>('name'),
      icon: r.read<String>('icon'),
      color: r.read<int>('color'),
      targetAmount: r.readNullable<int>('target_amount'),
      sortOrder: r.read<int>('sort_order'),
      isArchived: r.read<bool>('is_archived'),
    );
    return PocketWithBalance(pocket: pocket, balance: r.read<int>('balance'));
  }

  Stream<List<PocketWithBalance>> watchPocketsForWallet(
    int walletId, {
    bool includeArchived = false,
  }) {
    final archSql = includeArchived ? '' : 'AND p.is_archived = 0';
    return customSelect(
      '$_pocketBalanceSql WHERE p.wallet_id = ? $archSql ORDER BY p.sort_order ASC, p.id ASC',
      variables: [Variable.withInt(walletId)],
      readsFrom: {walletPockets, pocketAllocations, transactions},
    ).watch().map((rows) => rows.map(_mapPocketBalanceRow).toList());
  }

  Stream<List<PocketWithBalance>> watchAllActivePockets() {
    return customSelect(
      '$_pocketBalanceSql INNER JOIN wallets w ON w.id = p.wallet_id WHERE p.is_archived = 0 AND w.is_archived = 0 ORDER BY p.wallet_id ASC, p.sort_order ASC, p.id ASC',
      readsFrom: {wallets, walletPockets, pocketAllocations, transactions},
    ).watch().map((rows) => rows.map(_mapPocketBalanceRow).toList());
  }

  Future<List<PocketWithBalance>> getPocketsForWallet(
    int walletId, {
    bool includeArchived = false,
  }) async {
    final archSql = includeArchived ? '' : 'AND p.is_archived = 0';
    final rows = await customSelect(
      '$_pocketBalanceSql WHERE p.wallet_id = ? $archSql ORDER BY p.sort_order ASC, p.id ASC',
      variables: [Variable.withInt(walletId)],
    ).get();
    return rows.map(_mapPocketBalanceRow).toList();
  }

  Future<int> getWalletUnallocatedBalance(int walletId) async {
    final wb = await getWalletWithBalance(walletId);
    if (wb == null) return 0;
    final pockets = await getPocketsForWallet(walletId, includeArchived: true);
    var allocated = 0;
    for (final p in pockets) {
      allocated += p.balance;
    }
    return wb.balance - allocated;
  }

  /// Alokasi manual (dari Saldo Bebas ke Pos, atau tarik kembali ke Saldo Bebas)
  /// maupun transfer antar Pos di dalam saku yang sama.
  Future<int> allocateOrMovePocket({
    required int walletId,
    int? fromPocketId,
    int? toPocketId,
    required int amount,
    String note = '',
  }) async {
    if (amount <= 0 || fromPocketId == toPocketId) {
      throw ArgumentError('Nominal harus > 0 dan asal/tujuan harus berbeda');
    }
    return into(pocketAllocations).insert(
      PocketAllocationsCompanion.insert(
        walletId: walletId,
        fromPocketId: Value(fromPocketId),
        toPocketId: Value(toPocketId),
        amount: amount,
        note: Value(note.trim()),
        createdAt: DateTime.now().toUtc().millisecondsSinceEpoch,
      ),
    );
  }

  /// Atur saldo Pos secara manual langsung ke angka target (selisihnya diambil/dikembalikan ke Saldo Bebas).
  Future<void> setPocketBalanceManually({
    required int walletId,
    required int pocketId,
    required int targetBalance,
    String note = 'Alokasi manual',
  }) async {
    final pockets = await getPocketsForWallet(walletId, includeArchived: true);
    final current =
        pockets.where((p) => p.pocket.id == pocketId).firstOrNull?.balance ?? 0;
    final diff = targetBalance - current;
    if (diff == 0) return;
    if (diff > 0) {
      await allocateOrMovePocket(
        walletId: walletId,
        fromPocketId: null,
        toPocketId: pocketId,
        amount: diff,
        note: note,
      );
    } else {
      await allocateOrMovePocket(
        walletId: walletId,
        fromPocketId: pocketId,
        toPocketId: null,
        amount: diff.abs(),
        note: note,
      );
    }
  }

  /// Kembalikan saldo tersisa ke Saldo Bebas lalu hapus jika belum dipakai transaksi, atau arsipkan.
  Future<bool> deleteOrArchivePocket(int walletId, int pocketId) async {
    return transaction(() async {
      final pockets = await getPocketsForWallet(
        walletId,
        includeArchived: true,
      );
      final current =
          pockets.where((p) => p.pocket.id == pocketId).firstOrNull?.balance ??
          0;
      if (current != 0) {
        await allocateOrMovePocket(
          walletId: walletId,
          fromPocketId: current > 0 ? pocketId : null,
          toPocketId: current > 0 ? null : pocketId,
          amount: current.abs(),
          note: 'Pengembalian saldo pos',
        );
      }

      final txRefRow = await customSelect(
        'SELECT COUNT(*) AS cnt FROM transactions WHERE pocket_id = ? OR to_pocket_id = ?',
        variables: [Variable.withInt(pocketId), Variable.withInt(pocketId)],
      ).getSingle();
      final txRefs = txRefRow.read<int>('cnt');

      if (txRefs == 0) {
        await (delete(pocketAllocations)..where(
              (pa) =>
                  pa.fromPocketId.equals(pocketId) |
                  pa.toPocketId.equals(pocketId),
            ))
            .go();
        await (update(itemMemory)
              ..where((m) => m.lastPocketId.equals(pocketId)))
            .write(const ItemMemoryCompanion(lastPocketId: Value(null)));
        await (delete(walletPockets)..where((p) => p.id.equals(pocketId))).go();
        return true;
      }

      await (update(walletPockets)..where((p) => p.id.equals(pocketId))).write(
        const WalletPocketsCompanion(isArchived: Value(true)),
      );
      return false;
    });
  }

  Stream<List<PocketAllocation>> watchRecentPocketAllocations(
    int walletId, {
    int limit = 20,
  }) {
    final q = select(pocketAllocations)
      ..where((pa) => pa.walletId.equals(walletId))
      ..orderBy([(pa) => OrderingTerm.desc(pa.createdAt)])
      ..limit(limit);
    return q.watch();
  }

  // -------------------------------------------------------------------------
  // Categories (ordered by recent usage or sort_order)
  // -------------------------------------------------------------------------

  Stream<List<Category>> watchCategories({
    String? type,
    bool includeArchived = false,
  }) {
    final q = select(categories);
    if (type != null) {
      q.where((c) => c.type.equals(type));
    }
    if (!includeArchived) {
      q.where((c) => c.isArchived.equals(false));
    }
    q.orderBy([
      (c) => OrderingTerm.asc(c.sortOrder),
      (c) => OrderingTerm.asc(c.id),
    ]);
    return q.watch();
  }

  /// Mengurutkan kategori berdasarkan pemakaian terbaru lalu sort_order (smart defaults).
  Future<List<Category>> getCategoriesByRecentUsage(String type) async {
    final rows = await customSelect(
      '''
      SELECT c.*, COALESCE(MAX(t.occurred_at), 0) AS last_used
      FROM categories c
      LEFT JOIN transactions t ON t.category_id = c.id
      WHERE c.type = ? AND c.is_archived = 0
      GROUP BY c.id
      ORDER BY last_used DESC, c.sort_order ASC, c.id ASC
      ''',
      variables: [Variable.withString(type)],
    ).get();

    return rows
        .map(
          (r) => Category(
            id: r.read<int>('id'),
            name: r.read<String>('name'),
            type: r.read<String>('type'),
            icon: r.read<String>('icon'),
            color: r.read<int>('color'),
            sortOrder: r.read<int>('sort_order'),
            isArchived: r.read<bool>('is_archived'),
          ),
        )
        .toList();
  }

  Future<int?> findCategoryIdByName(String name, String type) async {
    final q = select(categories)
      ..where((c) => c.name.equals(name) & c.type.equals(type))
      ..limit(1);
    final cat = await q.getSingleOrNull();
    return cat?.id;
  }

  // -------------------------------------------------------------------------
  // Transactions (Keyset Pagination + CRUD + Item Memory Upsert)
  // -------------------------------------------------------------------------

  static String normalizeItemName(String raw) =>
      raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  Future<int> saveTransactionWithMemory({
    required String type,
    required int amount,
    required int walletId,
    int? categoryId,
    int? toWalletId,
    int? pocketId,
    int? toPocketId,
    int fee = 0,
    String note = '',
    String? itemName,
    String? merchantName,
    String? splitGroupId,
    String? externalRef,
    required DateTime occurredAt,
    int? existingId,
    bool updateItemMemory = true,
  }) async {
    final nowMillis = DateTime.now().toUtc().millisecondsSinceEpoch;
    final occurredMillis = occurredAt.toUtc().millisecondsSinceEpoch;
    final dayKey = AppDateUtils.toDayKey(occurredAt);
    final trimmedItem = itemName?.trim();
    final cleanItem = (trimmedItem == null || trimmedItem.isEmpty)
        ? null
        : trimmedItem;
    final trimmedMerchant = merchantName?.trim();
    final cleanMerchant = (trimmedMerchant == null || trimmedMerchant.isEmpty)
        ? null
        : trimmedMerchant;

    return transaction(() async {
      late int txId;
      if (existingId != null) {
        await (update(
          transactions,
        )..where((t) => t.id.equals(existingId))).write(
          TransactionsCompanion(
            type: Value(type),
            amount: Value(amount),
            categoryId: Value(categoryId),
            walletId: Value(walletId),
            toWalletId: Value(toWalletId),
            pocketId: Value(pocketId),
            toPocketId: Value(toPocketId),
            fee: Value(fee),
            note: Value(note.trim()),
            itemName: Value(cleanItem),
            merchantName: Value(cleanMerchant),
            splitGroupId: splitGroupId != null
                ? Value(splitGroupId)
                : const Value.absent(),
            externalRef: externalRef != null
                ? Value(externalRef)
                : const Value.absent(),
            occurredAt: Value(occurredMillis),
            dayKey: Value(dayKey),
            updatedAt: Value(nowMillis),
          ),
        );
        txId = existingId;
      } else {
        txId = await into(transactions).insert(
          TransactionsCompanion.insert(
            type: type,
            amount: amount,
            categoryId: Value(categoryId),
            walletId: walletId,
            toWalletId: Value(toWalletId),
            pocketId: Value(pocketId),
            toPocketId: Value(toPocketId),
            fee: Value(fee),
            note: Value(note.trim()),
            itemName: Value(cleanItem),
            merchantName: Value(cleanMerchant),
            splitGroupId: Value(splitGroupId),
            externalRef: Value(externalRef),
            occurredAt: occurredMillis,
            dayKey: dayKey,
            createdAt: nowMillis,
            updatedAt: nowMillis,
          ),
        );
      }

      if (updateItemMemory && (type == 'income' || type == 'expense')) {
        if (cleanItem != null) {
          await upsertItemMemory(
            displayName: cleanItem,
            type: type,
            amount: amount,
            merchantName: cleanMerchant,
            categoryId: categoryId,
            walletId: walletId,
            pocketId: pocketId,
            note: note.trim(),
          );
        }
        if (cleanMerchant != null) {
          await upsertMerchantMemory(
            displayMerchant: cleanMerchant,
            type: type,
            itemName: cleanItem,
            amount: amount,
            categoryId: categoryId,
            walletId: walletId,
            pocketId: pocketId,
            note: note.trim(),
          );
        }
      }

      return txId;
    });
  }

  /// Pecah satu transaksi (atau edit pecahan yang sudah ada) menjadi beberapa komponen
  /// secara atomik tanpa dobel hitung saldo maupun laporan kategori.
  Future<String> saveSplitTransactions({
    required String type,
    required int walletId,
    required DateTime occurredAt,
    required List<SplitComponentInput> components,
    String? merchantName,
    int? replaceSingleTransactionId,
    String? existingSplitGroupId,
    String? externalRef,
  }) async {
    if (components.isEmpty) {
      throw ArgumentError('Minimal harus ada 1 komponen pecahan');
    }
    final groupId =
        existingSplitGroupId ??
        'split_${DateTime.now().microsecondsSinceEpoch}';
    final nowMillis = DateTime.now().toUtc().millisecondsSinceEpoch;
    final occurredMillis = occurredAt.toUtc().millisecondsSinceEpoch;
    final dayKey = AppDateUtils.toDayKey(occurredAt);
    final trimmedMerchant = merchantName?.trim();
    String? cleanMerchant = (trimmedMerchant == null || trimmedMerchant.isEmpty)
        ? null
        : trimmedMerchant;

    return transaction(() async {
      String? preservedRef = externalRef;
      if (replaceSingleTransactionId != null) {
        final orig =
            await (select(transactions)
                  ..where((t) => t.id.equals(replaceSingleTransactionId)))
                .getSingleOrNull();
        preservedRef ??= orig?.externalRef;
        cleanMerchant ??= orig?.merchantName;
        await (delete(
          transactions,
        )..where((t) => t.id.equals(replaceSingleTransactionId))).go();
      } else if (existingSplitGroupId != null) {
        final siblings = await (select(
          transactions,
        )..where((t) => t.splitGroupId.equals(existingSplitGroupId))).get();
        if (preservedRef == null) {
          for (final s in siblings) {
            if (s.externalRef != null) {
              preservedRef = s.externalRef;
              break;
            }
          }
        }
        if (cleanMerchant == null) {
          for (final s in siblings) {
            if (s.merchantName != null && s.merchantName!.trim().isNotEmpty) {
              cleanMerchant = s.merchantName;
              break;
            }
          }
        }
        await (delete(
          transactions,
        )..where((t) => t.splitGroupId.equals(existingSplitGroupId))).go();
      }

      var totalAmount = 0;
      for (var i = 0; i < components.length; i++) {
        final comp = components[i];
        totalAmount += comp.amount;
        final cleanName = comp.itemName.trim();
        await into(transactions).insert(
          TransactionsCompanion.insert(
            type: type,
            amount: comp.amount,
            categoryId: Value(comp.categoryId),
            walletId: walletId,
            pocketId: Value(comp.pocketId),
            note: Value(comp.note.trim()),
            itemName: Value(cleanName.isEmpty ? null : cleanName),
            merchantName: Value(cleanMerchant),
            splitGroupId: Value(components.length > 1 ? groupId : null),
            externalRef: Value(preservedRef),
            occurredAt: occurredMillis,
            dayKey: dayKey,
            createdAt: nowMillis + i,
            updatedAt: nowMillis + i,
          ),
        );
        if (cleanName.isNotEmpty && (type == 'income' || type == 'expense')) {
          await upsertItemMemory(
            displayName: cleanName,
            type: type,
            amount: comp.amount,
            merchantName: cleanMerchant,
            categoryId: comp.categoryId,
            walletId: walletId,
            pocketId: comp.pocketId,
            note: comp.note.trim(),
          );
        }
      }

      final resolvedMerchant = cleanMerchant;
      if (resolvedMerchant != null && (type == 'income' || type == 'expense')) {
        final first = components.first;
        await upsertMerchantMemory(
          displayMerchant: resolvedMerchant,
          type: type,
          itemName: first.itemName.trim().isEmpty
              ? null
              : first.itemName.trim(),
          amount: totalAmount,
          categoryId: first.categoryId,
          walletId: walletId,
          pocketId: first.pocketId,
          note: first.note.trim(),
        );
      }

      return groupId;
    });
  }

  Future<List<Transaction>> getTransactionsBySplitGroup(String groupId) {
    return (select(transactions)
          ..where((t) => t.splitGroupId.equals(groupId))
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();
  }

  // -------------------------------------------------------------------------
  // Imported QRIS Email Drafts (Antrean Review & Dedup)
  // -------------------------------------------------------------------------

  Stream<List<ImportedQrisDraft>> watchPendingQrisDrafts() {
    return (select(importedQrisDrafts)
          ..where((d) => d.status.equals('pending'))
          ..orderBy([(d) => OrderingTerm.desc(d.occurredAt)]))
        .watch();
  }

  Future<bool> hasImportedEmailUid(String emailUid) async {
    final row =
        await (select(importedQrisDrafts)
              ..where((d) => d.emailUid.equals(emailUid))
              ..limit(1))
            .getSingleOrNull();
    return row != null;
  }

  Future<int?> insertQrisDraftIfNew({
    required String emailUid,
    required String sender,
    required String subject,
    required String bankName,
    required String merchantName,
    required int amount,
    required DateTime occurredAt,
    int? suggestedWalletId,
    String rawSnippet = '',
    String txType = 'expense',
    String status = 'pending',
  }) async {
    if (await hasImportedEmailUid(emailUid)) return null;
    return into(importedQrisDrafts).insert(
      ImportedQrisDraftsCompanion.insert(
        emailUid: emailUid,
        sender: sender,
        subject: subject,
        bankName: bankName,
        merchantName: merchantName,
        amount: amount,
        occurredAt: occurredAt.toUtc().millisecondsSinceEpoch,
        suggestedWalletId: Value(suggestedWalletId),
        rawSnippet: Value(rawSnippet),
        txType: Value(txType),
        status: Value(status),
        createdAt: DateTime.now().toUtc().millisecondsSinceEpoch,
      ),
    );
  }

  Future<void> markQrisDraftStatus(int draftId, String status) async {
    await (update(importedQrisDrafts)..where((d) => d.id.equals(draftId)))
        .write(ImportedQrisDraftsCompanion(status: Value(status)));
  }

  /// Restore transaksi utuh setelah Undo delete.
  Future<int> restoreDeletedTransaction(Transaction tx) {
    return into(transactions).insert(
      TransactionsCompanion(
        id: Value(tx.id),
        type: Value(tx.type),
        amount: Value(tx.amount),
        categoryId: Value(tx.categoryId),
        walletId: Value(tx.walletId),
        toWalletId: Value(tx.toWalletId),
        pocketId: Value(tx.pocketId),
        toPocketId: Value(tx.toPocketId),
        fee: Value(tx.fee),
        note: Value(tx.note),
        itemName: Value(tx.itemName),
        merchantName: Value(tx.merchantName),
        splitGroupId: Value(tx.splitGroupId),
        externalRef: Value(tx.externalRef),
        occurredAt: Value(tx.occurredAt),
        dayKey: Value(tx.dayKey),
        createdAt: Value(tx.createdAt),
        updatedAt: Value(tx.updatedAt),
      ),
      mode: InsertMode.insertOrReplace,
    );
  }

  Future<void> deleteTransactionsByIds(List<int> ids) async {
    if (ids.isEmpty) return;
    await (delete(transactions)..where((t) => t.id.isIn(ids))).go();
  }

  Future<TransactionDetail?> getLatestTransaction() async {
    final list = await fetchTransactionsPage(limit: 1);
    return list.isEmpty ? null : list.first;
  }

  /// Keyset pagination berbasis (occurredAt, id) menurun untuk scroll 120 Hz.
  Future<List<TransactionDetail>> fetchTransactionsPage({
    int limit = 40,
    int? cursorOccurredAt,
    int? cursorId,
    int? startDayKey,
    int? endDayKey,
    String? type,
    int? categoryId,
    int? walletId,
    String? searchQuery,
  }) async {
    final conditions = <String>[];
    final vars = <Variable>[];

    if (cursorOccurredAt != null && cursorId != null) {
      conditions.add('(t.occurred_at < ? OR (t.occurred_at = ? AND t.id < ?))');
      vars.add(Variable.withInt(cursorOccurredAt));
      vars.add(Variable.withInt(cursorOccurredAt));
      vars.add(Variable.withInt(cursorId));
    }
    if (startDayKey != null) {
      conditions.add('t.day_key >= ?');
      vars.add(Variable.withInt(startDayKey));
    }
    if (endDayKey != null) {
      conditions.add('t.day_key <= ?');
      vars.add(Variable.withInt(endDayKey));
    }
    if (type != null && type.isNotEmpty) {
      conditions.add('t.type = ?');
      vars.add(Variable.withString(type));
    }
    if (categoryId != null) {
      conditions.add('t.category_id = ?');
      vars.add(Variable.withInt(categoryId));
    }
    if (walletId != null) {
      conditions.add('(t.wallet_id = ? OR t.to_wallet_id = ?)');
      vars.add(Variable.withInt(walletId));
      vars.add(Variable.withInt(walletId));
    }
    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final like = '%${searchQuery.trim().toLowerCase()}%';
      conditions.add(
        '(LOWER(COALESCE(t.item_name, \'\')) LIKE ? OR LOWER(COALESCE(t.merchant_name, \'\')) LIKE ? OR LOWER(t.note) LIKE ? OR LOWER(COALESCE(c.name, \'\')) LIKE ? OR LOWER(w.name) LIKE ?)',
      );
      vars.add(Variable.withString(like));
      vars.add(Variable.withString(like));
      vars.add(Variable.withString(like));
      vars.add(Variable.withString(like));
      vars.add(Variable.withString(like));
    }

    final whereSql = conditions.isEmpty
        ? ''
        : 'WHERE ${conditions.join(' AND ')}';
    vars.add(Variable.withInt(limit));

    final rows = await customSelect('''
      SELECT
        t.id AS t_id, t.type AS t_type, t.amount AS t_amount, t.category_id AS t_category_id,
        t.wallet_id AS t_wallet_id, t.to_wallet_id AS t_to_wallet_id,
        t.pocket_id AS t_pocket_id, t.to_pocket_id AS t_to_pocket_id, t.fee AS t_fee,
        t.note AS t_note, t.item_name AS t_item_name, t.merchant_name AS t_merchant_name,
        t.split_group_id AS t_split_group_id, t.external_ref AS t_external_ref,
        t.occurred_at AS t_occurred_at,
        t.day_key AS t_day_key, t.created_at AS t_created_at, t.updated_at AS t_updated_at,
        w.id AS w_id, w.name AS w_name, w.type AS w_type, w.icon AS w_icon,
        w.color AS w_color, w.initial_balance AS w_initial_balance,
        w.include_in_total AS w_include_in_total, w.is_archived AS w_is_archived,
        w.sort_order AS w_sort_order,
        tw.id AS tw_id, tw.name AS tw_name, tw.type AS tw_type, tw.icon AS tw_icon,
        tw.color AS tw_color, tw.initial_balance AS tw_initial_balance,
        tw.include_in_total AS tw_include_in_total, tw.is_archived AS tw_is_archived,
        tw.sort_order AS tw_sort_order,
        c.id AS c_id, c.name AS c_name, c.type AS c_type, c.icon AS c_icon,
        c.color AS c_color, c.sort_order AS c_sort_order, c.is_archived AS c_is_archived,
        pk.name AS pk_name,
        tpk.name AS tpk_name
      FROM transactions t
      INNER JOIN wallets w ON w.id = t.wallet_id
      LEFT JOIN wallets tw ON tw.id = t.to_wallet_id
      LEFT JOIN categories c ON c.id = t.category_id
      LEFT JOIN wallet_pockets pk ON pk.id = t.pocket_id
      LEFT JOIN wallet_pockets tpk ON tpk.id = t.to_pocket_id
      $whereSql
      ORDER BY t.occurred_at DESC, t.id DESC
      LIMIT ?
      ''', variables: vars).get();

    return rows.map(_mapTransactionDetailRow).toList();
  }

  Stream<List<TransactionDetail>> watchRecentTransactions({int limit = 10}) {
    return customSelect(
      '''
      SELECT
        t.id AS t_id, t.type AS t_type, t.amount AS t_amount, t.category_id AS t_category_id,
        t.wallet_id AS t_wallet_id, t.to_wallet_id AS t_to_wallet_id,
        t.pocket_id AS t_pocket_id, t.to_pocket_id AS t_to_pocket_id, t.fee AS t_fee,
        t.note AS t_note, t.item_name AS t_item_name, t.merchant_name AS t_merchant_name,
        t.split_group_id AS t_split_group_id, t.external_ref AS t_external_ref,
        t.occurred_at AS t_occurred_at,
        t.day_key AS t_day_key, t.created_at AS t_created_at, t.updated_at AS t_updated_at,
        w.id AS w_id, w.name AS w_name, w.type AS w_type, w.icon AS w_icon,
        w.color AS w_color, w.initial_balance AS w_initial_balance,
        w.include_in_total AS w_include_in_total, w.is_archived AS w_is_archived,
        w.sort_order AS w_sort_order,
        tw.id AS tw_id, tw.name AS tw_name, tw.type AS tw_type, tw.icon AS tw_icon,
        tw.color AS tw_color, tw.initial_balance AS tw_initial_balance,
        tw.include_in_total AS tw_include_in_total, tw.is_archived AS tw_is_archived,
        tw.sort_order AS tw_sort_order,
        c.id AS c_id, c.name AS c_name, c.type AS c_type, c.icon AS c_icon,
        c.color AS c_color, c.sort_order AS c_sort_order, c.is_archived AS c_is_archived,
        pk.name AS pk_name,
        tpk.name AS tpk_name
      FROM transactions t
      INNER JOIN wallets w ON w.id = t.wallet_id
      LEFT JOIN wallets tw ON tw.id = t.to_wallet_id
      LEFT JOIN categories c ON c.id = t.category_id
      LEFT JOIN wallet_pockets pk ON pk.id = t.pocket_id
      LEFT JOIN wallet_pockets tpk ON tpk.id = t.to_pocket_id
      ORDER BY t.occurred_at DESC, t.id DESC
      LIMIT ?
      ''',
      variables: [Variable.withInt(limit)],
      readsFrom: {transactions, wallets, categories, walletPockets},
    ).watch().map((rows) => rows.map(_mapTransactionDetailRow).toList());
  }

  /// Ambil transaksi yang melibatkan salah satu pos budget pada [pocketIds]
  /// (pengeluaran, pemasukan, atau transfer masuk/keluar pos tersebut).
  Future<List<TransactionDetail>> fetchTransactionsForPocketIds(
    Set<int> pocketIds, {
    int? startDayKey,
    int? endDayKey,
    int limit = 200,
  }) async {
    if (pocketIds.isEmpty) return const [];
    final placeholders = List.filled(pocketIds.length, '?').join(',');
    final conditions = <String>[
      '(t.pocket_id IN ($placeholders) OR t.to_pocket_id IN ($placeholders))',
    ];
    final vars = <Variable>[
      for (final id in pocketIds) Variable.withInt(id),
      for (final id in pocketIds) Variable.withInt(id),
    ];
    if (startDayKey != null) {
      conditions.add('t.day_key >= ?');
      vars.add(Variable.withInt(startDayKey));
    }
    if (endDayKey != null) {
      conditions.add('t.day_key <= ?');
      vars.add(Variable.withInt(endDayKey));
    }
    vars.add(Variable.withInt(limit));

    final rows = await customSelect('''
      SELECT
        t.id AS t_id, t.type AS t_type, t.amount AS t_amount, t.category_id AS t_category_id,
        t.wallet_id AS t_wallet_id, t.to_wallet_id AS t_to_wallet_id,
        t.pocket_id AS t_pocket_id, t.to_pocket_id AS t_to_pocket_id, t.fee AS t_fee,
        t.note AS t_note, t.item_name AS t_item_name, t.merchant_name AS t_merchant_name,
        t.split_group_id AS t_split_group_id, t.external_ref AS t_external_ref,
        t.occurred_at AS t_occurred_at,
        t.day_key AS t_day_key, t.created_at AS t_created_at, t.updated_at AS t_updated_at,
        w.id AS w_id, w.name AS w_name, w.type AS w_type, w.icon AS w_icon,
        w.color AS w_color, w.initial_balance AS w_initial_balance,
        w.include_in_total AS w_include_in_total, w.is_archived AS w_is_archived,
        w.sort_order AS w_sort_order,
        tw.id AS tw_id, tw.name AS tw_name, tw.type AS tw_type, tw.icon AS tw_icon,
        tw.color AS tw_color, tw.initial_balance AS tw_initial_balance,
        tw.include_in_total AS tw_include_in_total, tw.is_archived AS tw_is_archived,
        tw.sort_order AS tw_sort_order,
        c.id AS c_id, c.name AS c_name, c.type AS c_type, c.icon AS c_icon,
        c.color AS c_color, c.sort_order AS c_sort_order, c.is_archived AS c_is_archived,
        pk.name AS pk_name,
        tpk.name AS tpk_name
      FROM transactions t
      INNER JOIN wallets w ON w.id = t.wallet_id
      LEFT JOIN wallets tw ON tw.id = t.to_wallet_id
      LEFT JOIN categories c ON c.id = t.category_id
      LEFT JOIN wallet_pockets pk ON pk.id = t.pocket_id
      LEFT JOIN wallet_pockets tpk ON tpk.id = t.to_pocket_id
      WHERE ${conditions.join(' AND ')}
      ORDER BY t.occurred_at DESC, t.id DESC
      LIMIT ?
      ''', variables: vars).get();

    return rows.map(_mapTransactionDetailRow).toList();
  }

  Future<void> updatePocketTargetAmount(int pocketId, int? targetAmount) async {
    await (update(walletPockets)..where((p) => p.id.equals(pocketId))).write(
      WalletPocketsCompanion(targetAmount: Value(targetAmount)),
    );
  }

  TransactionDetail _mapTransactionDetailRow(QueryRow r) {
    final tx = Transaction(
      id: r.read<int>('t_id'),
      type: r.read<String>('t_type'),
      amount: r.read<int>('t_amount'),
      categoryId: r.readNullable<int>('t_category_id'),
      walletId: r.read<int>('t_wallet_id'),
      toWalletId: r.readNullable<int>('t_to_wallet_id'),
      pocketId: r.readNullable<int>('t_pocket_id'),
      toPocketId: r.readNullable<int>('t_to_pocket_id'),
      fee: r.read<int>('t_fee'),
      note: r.read<String>('t_note'),
      itemName: r.readNullable<String>('t_item_name'),
      merchantName: r.readNullable<String>('t_merchant_name'),
      splitGroupId: r.readNullable<String>('t_split_group_id'),
      externalRef: r.readNullable<String>('t_external_ref'),
      occurredAt: r.read<int>('t_occurred_at'),
      dayKey: r.read<int>('t_day_key'),
      createdAt: r.read<int>('t_created_at'),
      updatedAt: r.read<int>('t_updated_at'),
    );
    final wallet = Wallet(
      id: r.read<int>('w_id'),
      name: r.read<String>('w_name'),
      type: r.read<String>('w_type'),
      icon: r.read<String>('w_icon'),
      color: r.read<int>('w_color'),
      initialBalance: r.read<int>('w_initial_balance'),
      includeInTotal: r.read<bool>('w_include_in_total'),
      isArchived: r.read<bool>('w_is_archived'),
      sortOrder: r.read<int>('w_sort_order'),
    );
    final twId = r.readNullable<int>('tw_id');
    final toWallet = twId == null
        ? null
        : Wallet(
            id: twId,
            name: r.read<String>('tw_name'),
            type: r.read<String>('tw_type'),
            icon: r.read<String>('tw_icon'),
            color: r.read<int>('tw_color'),
            initialBalance: r.read<int>('tw_initial_balance'),
            includeInTotal: r.read<bool>('tw_include_in_total'),
            isArchived: r.read<bool>('tw_is_archived'),
            sortOrder: r.read<int>('tw_sort_order'),
          );
    final cId = r.readNullable<int>('c_id');
    final category = cId == null
        ? null
        : Category(
            id: cId,
            name: r.read<String>('c_name'),
            type: r.read<String>('c_type'),
            icon: r.read<String>('c_icon'),
            color: r.read<int>('c_color'),
            sortOrder: r.read<int>('c_sort_order'),
            isArchived: r.read<bool>('c_is_archived'),
          );
    return TransactionDetail(
      transaction: tx,
      wallet: wallet,
      toWallet: toWallet,
      category: category,
      pocketName: r.readNullable<String>('pk_name'),
      toPocketName: r.readNullable<String>('tpk_name'),
    );
  }

  // -------------------------------------------------------------------------
  // Item Memory (Auto-learn + Autocomplete + Quick Items)
  // -------------------------------------------------------------------------

  Future<void> upsertItemMemory({
    required String displayName,
    required String type,
    required int amount,
    String? merchantName,
    int? categoryId,
    int? walletId,
    int? pocketId,
    String note = '',
    bool? isPinned,
  }) async {
    final normalized = normalizeItemName(displayName);
    if (normalized.isEmpty) return;
    final cleanMerchant = merchantName?.trim();
    final effectiveMerchant = (cleanMerchant == null || cleanMerchant.isEmpty)
        ? null
        : cleanMerchant;
    final nowMillis = DateTime.now().toUtc().millisecondsSinceEpoch;

    final existing = await (select(
      itemMemory,
    )..where((m) => m.nameNormalized.equals(normalized))).getSingleOrNull();

    if (existing != null) {
      await (update(itemMemory)..where((m) => m.id.equals(existing.id))).write(
        ItemMemoryCompanion(
          displayName: Value(displayName.trim()),
          type: Value(type),
          lastAmount: Value(amount),
          lastMerchantName: effectiveMerchant != null
              ? Value(effectiveMerchant)
              : const Value.absent(),
          lastCategoryId: Value(categoryId),
          lastWalletId: Value(walletId),
          lastPocketId: Value(pocketId),
          lastNote: Value(note),
          useCount: Value(existing.useCount + 1),
          lastUsedAt: Value(nowMillis),
          isPinned: isPinned != null ? Value(isPinned) : const Value.absent(),
        ),
      );
    } else {
      await into(itemMemory).insert(
        ItemMemoryCompanion.insert(
          nameNormalized: normalized,
          displayName: displayName.trim(),
          type: type,
          lastAmount: amount,
          lastMerchantName: Value(effectiveMerchant),
          lastCategoryId: Value(categoryId),
          lastWalletId: Value(walletId),
          lastPocketId: Value(pocketId),
          lastNote: Value(note),
          useCount: const Value(1),
          lastUsedAt: nowMillis,
          isPinned: Value(isPinned ?? false),
        ),
      );
    }
  }

  Future<void> upsertMerchantMemory({
    required String displayMerchant,
    required String type,
    String? itemName,
    required int amount,
    int? categoryId,
    int? walletId,
    int? pocketId,
    String note = '',
  }) async {
    final normalized = normalizeItemName(displayMerchant);
    if (normalized.isEmpty) return;
    final cleanItem = itemName?.trim();
    final effectiveItem = (cleanItem == null || cleanItem.isEmpty)
        ? null
        : cleanItem;
    final nowMillis = DateTime.now().toUtc().millisecondsSinceEpoch;

    final existing = await (select(
      merchantMemory,
    )..where((m) => m.merchantNormalized.equals(normalized))).getSingleOrNull();

    if (existing != null) {
      await (update(
        merchantMemory,
      )..where((m) => m.id.equals(existing.id))).write(
        MerchantMemoryCompanion(
          displayMerchant: Value(displayMerchant.trim()),
          type: Value(type),
          lastItemName: effectiveItem != null
              ? Value(effectiveItem)
              : const Value.absent(),
          lastAmount: Value(amount),
          lastCategoryId: Value(categoryId),
          lastWalletId: Value(walletId),
          lastPocketId: Value(pocketId),
          lastNote: Value(note),
          useCount: Value(existing.useCount + 1),
          lastUsedAt: Value(nowMillis),
        ),
      );
    } else {
      await into(merchantMemory).insert(
        MerchantMemoryCompanion.insert(
          merchantNormalized: normalized,
          displayMerchant: displayMerchant.trim(),
          type: Value(type),
          lastItemName: Value(effectiveItem),
          lastAmount: amount,
          lastCategoryId: Value(categoryId),
          lastWalletId: Value(walletId),
          lastPocketId: Value(pocketId),
          lastNote: Value(note),
          useCount: const Value(1),
          lastUsedAt: nowMillis,
        ),
      );
    }
  }

  Future<List<MerchantMemoryData>> searchMerchantMemory(
    String query, {
    String? type,
    int limit = 8,
  }) async {
    final normalized = normalizeItemName(query);
    final q = select(merchantMemory);
    if (type != null && (type == 'income' || type == 'expense')) {
      q.where((m) => m.type.equals(type));
    }
    if (normalized.isNotEmpty) {
      q.where((m) => m.merchantNormalized.like('%$normalized%'));
    }
    q.orderBy([
      (m) => OrderingTerm.desc(m.useCount),
      (m) => OrderingTerm.desc(m.lastUsedAt),
    ]);
    q.limit(limit);
    return q.get();
  }

  Stream<List<MerchantMemoryData>> watchAllMerchantMemory() {
    return (select(merchantMemory)..orderBy([
          (m) => OrderingTerm.desc(m.useCount),
          (m) => OrderingTerm.desc(m.lastUsedAt),
        ]))
        .watch();
  }

  Future<MerchantMemoryData?> findMerchantMemoryForName(
    String merchantName, {
    String? type,
  }) async {
    final normalized = normalizeItemName(merchantName);
    if (normalized.isEmpty) return null;
    final exactQ = select(merchantMemory)
      ..where((m) => m.merchantNormalized.equals(normalized));
    if (type != null) {
      exactQ.where((m) => m.type.equals(type));
    }
    exactQ.limit(1);
    final exact = await exactQ.getSingleOrNull();
    if (exact != null) return exact;

    final all = await searchMerchantMemory('', type: type, limit: 100);
    for (final m in all) {
      if (m.merchantNormalized.length >= 3 &&
          (normalized.contains(m.merchantNormalized) ||
              m.merchantNormalized.contains(normalized))) {
        return m;
      }
    }
    return null;
  }

  Future<List<ItemMemoryData>> searchItemMemory(
    String query, {
    String? type,
    int limit = 8,
  }) async {
    final normalized = normalizeItemName(query);
    final q = select(itemMemory);
    if (type != null && (type == 'income' || type == 'expense')) {
      q.where((m) => m.type.equals(type));
    }
    if (normalized.isNotEmpty) {
      q.where((m) => m.nameNormalized.like('%$normalized%'));
    }
    q.orderBy([
      (m) => OrderingTerm.desc(m.isPinned),
      (m) => OrderingTerm.desc(m.useCount),
      (m) => OrderingTerm.desc(m.lastUsedAt),
    ]);
    q.limit(limit);
    return q.get();
  }

  Stream<List<ItemMemoryData>> watchQuickItems({int limit = 12}) {
    final q = select(itemMemory)
      ..orderBy([
        (m) => OrderingTerm.desc(m.isPinned),
        (m) => OrderingTerm.desc(m.useCount),
        (m) => OrderingTerm.desc(m.lastUsedAt),
      ])
      ..limit(limit);
    return q.watch();
  }

  Future<void> togglePinItemMemory(int id, bool pinned) async {
    await (update(itemMemory)..where((m) => m.id.equals(id))).write(
      ItemMemoryCompanion(isPinned: Value(pinned)),
    );
  }

  // -------------------------------------------------------------------------
  // Reports & Aggregates (100% SQL)
  // -------------------------------------------------------------------------

  Stream<PeriodSummary> watchPeriodSummary(int startDayKey, int endDayKey) {
    return customSelect(
      '''
      SELECT
        COALESCE(SUM(CASE WHEN type = 'income' THEN amount ELSE 0 END), 0) AS income,
        COALESCE(SUM(CASE WHEN type = 'expense' THEN amount ELSE 0 END), 0)
          + COALESCE(SUM(CASE WHEN type = 'transfer' AND fee > 0 THEN fee ELSE 0 END), 0) AS expense
      FROM transactions
      WHERE day_key >= ? AND day_key <= ?
      ''',
      variables: [Variable.withInt(startDayKey), Variable.withInt(endDayKey)],
      readsFrom: {transactions},
    ).watchSingle().map(
      (r) => PeriodSummary(
        income: r.read<int>('income'),
        expense: r.read<int>('expense'),
      ),
    );
  }

  Stream<List<Transaction>> watchTransactionsForDay(int dayKey) {
    return (select(
      transactions,
    )..where((t) => t.dayKey.equals(dayKey))).watch();
  }

  Future<PeriodSummary> getPeriodSummary(int startDayKey, int endDayKey) async {
    final r = await customSelect(
      '''
      SELECT
        COALESCE(SUM(CASE WHEN type = 'income' THEN amount ELSE 0 END), 0) AS income,
        COALESCE(SUM(CASE WHEN type = 'expense' THEN amount ELSE 0 END), 0)
          + COALESCE(SUM(CASE WHEN type = 'transfer' AND fee > 0 THEN fee ELSE 0 END), 0) AS expense
      FROM transactions
      WHERE day_key >= ? AND day_key <= ?
      ''',
      variables: [Variable.withInt(startDayKey), Variable.withInt(endDayKey)],
    ).getSingle();
    return PeriodSummary(
      income: r.read<int>('income'),
      expense: r.read<int>('expense'),
    );
  }

  /// Breakdown per kategori (termasuk fee transfer dimasukkan ke kategori "Biaya Admin").
  Future<List<CategoryAggregate>> getCategoryBreakdown({
    required int startDayKey,
    required int endDayKey,
    required String type, // 'expense' | 'income'
  }) async {
    final rows = await customSelect(
      '''
      SELECT
        c.id AS cat_id,
        COALESCE(c.name, 'Tanpa Kategori') AS cat_name,
        COALESCE(c.icon, 'other') AS cat_icon,
        COALESCE(c.color, 4284771979) AS cat_color,
        SUM(t.amount) AS total,
        COUNT(*) AS cnt
      FROM transactions t
      LEFT JOIN categories c ON c.id = t.category_id
      WHERE t.type = ? AND t.day_key >= ? AND t.day_key <= ?
      GROUP BY c.id
      ORDER BY total DESC
      ''',
      variables: [
        Variable.withString(type),
        Variable.withInt(startDayKey),
        Variable.withInt(endDayKey),
      ],
    ).get();

    final list = rows
        .map(
          (r) => CategoryAggregate(
            categoryId: r.readNullable<int>('cat_id'),
            categoryName: r.read<String>('cat_name'),
            icon: r.read<String>('cat_icon'),
            color: r.read<int>('cat_color'),
            total: r.read<int>('total'),
            count: r.read<int>('cnt'),
          ),
        )
        .toList();

    // Tambahkan biaya admin transfer ke kategori "Biaya Admin" pada laporan pengeluaran
    if (type == 'expense') {
      final feeRow = await customSelect(
        '''
        SELECT COALESCE(SUM(fee), 0) AS total_fee, COUNT(*) AS cnt
        FROM transactions
        WHERE type = 'transfer' AND fee > 0 AND day_key >= ? AND day_key <= ?
        ''',
        variables: [Variable.withInt(startDayKey), Variable.withInt(endDayKey)],
      ).getSingle();
      final totalFee = feeRow.read<int>('total_fee');
      final feeCount = feeRow.read<int>('cnt');
      if (totalFee > 0) {
        final adminCat =
            await (select(categories)
                  ..where(
                    (c) =>
                        c.name.equals(DefaultSeeds.adminFeeCategoryName) &
                        c.type.equals('expense'),
                  )
                  ..limit(1))
                .getSingleOrNull();
        final existingIdx = list.indexWhere(
          (e) =>
              (adminCat != null && e.categoryId == adminCat.id) ||
              e.categoryName == DefaultSeeds.adminFeeCategoryName,
        );
        if (existingIdx >= 0) {
          final prev = list[existingIdx];
          list[existingIdx] = CategoryAggregate(
            categoryId: prev.categoryId,
            categoryName: prev.categoryName,
            icon: prev.icon,
            color: prev.color,
            total: prev.total + totalFee,
            count: prev.count + feeCount,
          );
        } else {
          list.add(
            CategoryAggregate(
              categoryId: adminCat?.id,
              categoryName: adminCat?.name ?? DefaultSeeds.adminFeeCategoryName,
              icon: adminCat?.icon ?? 'admin_fee',
              color: adminCat?.color ?? 0xFF475569,
              total: totalFee,
              count: feeCount,
            ),
          );
        }
        list.sort((a, b) => b.total.compareTo(a.total));
      }
    }

    return list;
  }

  Future<List<DailyTrendPoint>> getDailyTrend({
    required int startDayKey,
    required int endDayKey,
    int? walletId,
  }) async {
    final walletFilter = walletId == null
        ? ''
        : 'AND (wallet_id = ? OR to_wallet_id = ?)';
    final vars = <Variable>[
      Variable.withInt(startDayKey),
      Variable.withInt(endDayKey),
      if (walletId != null) Variable.withInt(walletId),
      if (walletId != null) Variable.withInt(walletId),
    ];

    final rows = await customSelect('''
      SELECT
        day_key,
        COALESCE(SUM(CASE WHEN type = 'income' THEN amount ELSE 0 END), 0) AS income,
        COALESCE(SUM(CASE WHEN type = 'expense' THEN amount ELSE 0 END), 0)
          + COALESCE(SUM(CASE WHEN type = 'transfer' AND fee > 0 THEN fee ELSE 0 END), 0) AS expense
      FROM transactions
      WHERE day_key >= ? AND day_key <= ? $walletFilter
      GROUP BY day_key
      ORDER BY day_key ASC
      ''', variables: vars).get();

    return rows
        .map(
          (r) => DailyTrendPoint(
            dayKey: r.read<int>('day_key'),
            income: r.read<int>('income'),
            expense: r.read<int>('expense'),
          ),
        )
        .toList();
  }

  Future<int> getCategorySpentInPeriod({
    required int? categoryId,
    required int startDayKey,
    required int endDayKey,
  }) async {
    if (categoryId == null) {
      final summary = await getPeriodSummary(startDayKey, endDayKey);
      return summary.expense;
    }
    final row = await customSelect(
      '''
      SELECT COALESCE(SUM(amount), 0) AS total
      FROM transactions
      WHERE type = 'expense' AND category_id = ? AND day_key >= ? AND day_key <= ?
      ''',
      variables: [
        Variable.withInt(categoryId),
        Variable.withInt(startDayKey),
        Variable.withInt(endDayKey),
      ],
    ).getSingle();
    var total = row.read<int>('total');

    // Jika kategori adalah Biaya Admin, tambahkan transfer fee
    final adminCatId = await findCategoryIdByName(
      DefaultSeeds.adminFeeCategoryName,
      'expense',
    );
    if (adminCatId != null && adminCatId == categoryId) {
      final feeRow = await customSelect(
        '''
        SELECT COALESCE(SUM(fee), 0) AS total_fee
        FROM transactions
        WHERE type = 'transfer' AND fee > 0 AND day_key >= ? AND day_key <= ?
        ''',
        variables: [Variable.withInt(startDayKey), Variable.withInt(endDayKey)],
      ).getSingle();
      total += feeRow.read<int>('total_fee');
    }

    return total;
  }

  // -------------------------------------------------------------------------
  // Debts & People (SQL aggregates)
  // -------------------------------------------------------------------------

  Stream<List<DebtWithSummary>> watchDebtsWithSummary({
    String? direction,
    String? status,
    int? personId,
  }) {
    final conditions = <String>[];
    final vars = <Variable>[];
    if (direction != null) {
      conditions.add('d.direction = ?');
      vars.add(Variable.withString(direction));
    }
    if (status != null) {
      conditions.add('d.status = ?');
      vars.add(Variable.withString(status));
    }
    if (personId != null) {
      conditions.add('d.person_id = ?');
      vars.add(Variable.withInt(personId));
    }
    final whereSql = conditions.isEmpty
        ? ''
        : 'WHERE ${conditions.join(' AND ')}';

    return customSelect(
      '''
      SELECT
        d.id AS d_id, d.person_id AS d_person_id, d.direction AS d_direction,
        d.principal AS d_principal, d.note AS d_note, d.created_at AS d_created_at,
        d.due_date AS d_due_date, d.wallet_id AS d_wallet_id, d.status AS d_status,
        p.id AS p_id, p.name AS p_name, p.phone AS p_phone, p.note AS p_note,
        w.name AS w_name,
        COALESCE((SELECT SUM(dp.amount) FROM debt_payments dp WHERE dp.debt_id = d.id), 0) AS paid_total
      FROM debts d
      INNER JOIN people p ON p.id = d.person_id
      LEFT JOIN wallets w ON w.id = d.wallet_id
      $whereSql
      ORDER BY
        CASE WHEN d.status = 'open' THEN 0 ELSE 1 END ASC,
        COALESCE(d.due_date, 9223372036854775807) ASC,
        d.created_at DESC
      ''',
      variables: vars,
      readsFrom: {debts, debtPayments, people, wallets},
    ).watch().map(
      (rows) => rows
          .map(
            (r) => DebtWithSummary(
              debt: Debt(
                id: r.read<int>('d_id'),
                personId: r.read<int>('d_person_id'),
                direction: r.read<String>('d_direction'),
                principal: r.read<int>('d_principal'),
                note: r.read<String>('d_note'),
                createdAt: r.read<int>('d_created_at'),
                dueDate: r.readNullable<int>('d_due_date'),
                walletId: r.readNullable<int>('d_wallet_id'),
                status: r.read<String>('d_status'),
              ),
              person: Person(
                id: r.read<int>('p_id'),
                name: r.read<String>('p_name'),
                phone: r.readNullable<String>('p_phone'),
                note: r.read<String>('p_note'),
              ),
              paidTotal: r.read<int>('paid_total'),
              walletName: r.readNullable<String>('w_name'),
            ),
          )
          .toList(),
    );
  }

  Stream<List<PersonDebtSummary>> watchPersonDebtSummaries() {
    return customSelect(
      '''
      SELECT
        p.id AS p_id, p.name AS p_name, p.phone AS p_phone, p.note AS p_note,
        COALESCE(SUM(CASE
          WHEN d.direction = 'i_owe' AND d.status = 'open'
          THEN MAX(0, d.principal - COALESCE((SELECT SUM(dp.amount) FROM debt_payments dp WHERE dp.debt_id = d.id), 0))
          ELSE 0
        END), 0) AS i_owe_rem,
        COALESCE(SUM(CASE
          WHEN d.direction = 'they_owe' AND d.status = 'open'
          THEN MAX(0, d.principal - COALESCE((SELECT SUM(dp.amount) FROM debt_payments dp WHERE dp.debt_id = d.id), 0))
          ELSE 0
        END), 0) AS they_owe_rem,
        COALESCE(SUM(CASE WHEN d.status = 'open' THEN 1 ELSE 0 END), 0) AS open_cnt
      FROM people p
      LEFT JOIN debts d ON d.person_id = p.id
      GROUP BY p.id
      ORDER BY open_cnt DESC, p.name ASC
      ''',
      readsFrom: {people, debts, debtPayments},
    ).watch().map(
      (rows) => rows
          .map(
            (r) => PersonDebtSummary(
              person: Person(
                id: r.read<int>('p_id'),
                name: r.read<String>('p_name'),
                phone: r.readNullable<String>('p_phone'),
                note: r.read<String>('p_note'),
              ),
              iOweRemaining: r.read<int>('i_owe_rem'),
              theyOweRemaining: r.read<int>('they_owe_rem'),
              openCount: r.read<int>('open_cnt'),
            ),
          )
          .toList(),
    );
  }

  /// Tambah pembayaran cicilan hutang & otomatis ubah status ke 'settled' jika lunas.
  Future<int> addDebtPayment({
    required int debtId,
    required int amount,
    required DateTime paidAt,
    int? walletId,
    String note = '',
  }) async {
    return transaction(() async {
      final paymentId = await into(debtPayments).insert(
        DebtPaymentsCompanion.insert(
          debtId: debtId,
          amount: amount,
          paidAt: paidAt.toUtc().millisecondsSinceEpoch,
          walletId: Value(walletId),
          note: Value(note.trim()),
        ),
      );
      await _recalculateDebtStatus(debtId);
      return paymentId;
    });
  }

  Future<void> deleteDebtPayment(int paymentId, int debtId) async {
    await transaction(() async {
      await (delete(debtPayments)..where((dp) => dp.id.equals(paymentId))).go();
      await _recalculateDebtStatus(debtId);
    });
  }

  Future<void> _recalculateDebtStatus(int debtId) async {
    final debt = await (select(
      debts,
    )..where((d) => d.id.equals(debtId))).getSingleOrNull();
    if (debt == null) return;
    final paidRow = await customSelect(
      'SELECT COALESCE(SUM(amount), 0) AS paid FROM debt_payments WHERE debt_id = ?',
      variables: [Variable.withInt(debtId)],
    ).getSingle();
    final paid = paidRow.read<int>('paid');
    final newStatus = paid >= debt.principal ? 'settled' : 'open';
    if (newStatus != debt.status) {
      await (update(debts)..where((d) => d.id.equals(debtId))).write(
        DebtsCompanion(status: Value(newStatus)),
      );
    }
  }

  Future<Person> findOrCreatePerson(String name, {String? phone}) async {
    final trimmed = name.trim();
    final existing = await customSelect(
      'SELECT * FROM people WHERE LOWER(name) = LOWER(?) LIMIT 1',
      variables: [Variable.withString(trimmed)],
    ).getSingleOrNull();
    if (existing != null) {
      return Person(
        id: existing.read<int>('id'),
        name: existing.read<String>('name'),
        phone: existing.readNullable<String>('phone'),
        note: existing.read<String>('note'),
      );
    }
    final id = await into(people).insert(
      PeopleCompanion.insert(
        name: trimmed,
        phone: Value(phone?.trim().isEmpty ?? true ? null : phone!.trim()),
      ),
    );
    return Person(
      id: id,
      name: trimmed,
      phone: phone?.trim().isEmpty ?? true ? null : phone!.trim(),
      note: '',
    );
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/sakuin.db');
    return NativeDatabase.createInBackground(file);
  });
}
