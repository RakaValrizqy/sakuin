import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sakuin/core/db/app_database.dart';
import 'package:sakuin/core/db/db_provider.dart';

final walletsWithBalancesProvider = StreamProvider<List<WalletWithBalance>>((
  ref,
) {
  final db = ref.watch(appDatabaseProvider);
  return db.watchWalletsWithBalances();
});

final allWalletsWithBalancesProvider = StreamProvider<List<WalletWithBalance>>((
  ref,
) {
  final db = ref.watch(appDatabaseProvider);
  return db.watchWalletsWithBalances(includeArchived: true);
});

final totalBalanceProvider = Provider<int>((ref) {
  final wallets =
      ref.watch(walletsWithBalancesProvider).valueOrNull ?? const [];
  var sum = 0;
  for (final item in wallets) {
    if (item.wallet.includeInTotal) {
      sum += item.balance;
    }
  }
  return sum;
});

final walletActionsProvider = Provider<WalletActions>((ref) {
  return WalletActions(ref.watch(appDatabaseProvider));
});

class WalletActions {
  WalletActions(this._db);

  final AppDatabase _db;

  Future<int> saveWallet({
    int? id,
    required String name,
    required String type,
    required String icon,
    required int color,
    required int initialBalance,
    required bool includeInTotal,
  }) async {
    if (id != null) {
      await (_db.update(_db.wallets)..where((w) => w.id.equals(id))).write(
        WalletsCompanion(
          name: Value(name.trim()),
          type: Value(type),
          icon: Value(icon),
          color: Value(color),
          initialBalance: Value(initialBalance),
          includeInTotal: Value(includeInTotal),
        ),
      );
      return id;
    }

    final existing = await _db.select(_db.wallets).get();
    return _db
        .into(_db.wallets)
        .insert(
          WalletsCompanion.insert(
            name: name.trim(),
            type: type,
            icon: icon,
            color: color,
            initialBalance: Value(initialBalance),
            includeInTotal: Value(includeInTotal),
            sortOrder: Value(existing.length),
          ),
        );
  }

  Future<void> setArchived(int walletId, bool archived) async {
    await (_db.update(_db.wallets)..where((w) => w.id.equals(walletId))).write(
      WalletsCompanion(isArchived: Value(archived)),
    );
  }

  /// Hapus permanen jika kosong, atau arsipkan jika sudah memiliki transaksi/hutang.
  /// Mengembalikan `true` jika dihapus permanen, `false` jika diarsipkan.
  Future<bool> deleteOrArchiveWallet(int walletId) async {
    final refs = await _db.countWalletReferences(walletId);
    if (refs == 0) {
      await (_db.delete(_db.wallets)..where((w) => w.id.equals(walletId))).go();
      return true;
    }
    await setArchived(walletId, true);
    return false;
  }

  Future<void> reorder(List<int> orderedIds) => _db.reorderWallets(orderedIds);

  /// Koreksi saldo dengan membuat transaksi penyesuaian (income/expense).
  Future<int?> adjustBalance({
    required int walletId,
    required int currentBalance,
    required int actualBalance,
  }) async {
    final diff = actualBalance - currentBalance;
    if (diff == 0) return null;
    final type = diff > 0 ? 'income' : 'expense';
    final catId = await _db.findCategoryIdByName('Lainnya', type);
    return _db.saveTransactionWithMemory(
      type: type,
      amount: diff.abs(),
      walletId: walletId,
      categoryId: catId,
      itemName: 'Koreksi saldo',
      note: 'Penyesuaian saldo dompet',
      occurredAt: DateTime.now(),
      updateItemMemory: false,
    );
  }
}

String walletTypeLabel(String type) => switch (type) {
  'cash' => 'Tunai',
  'bank' => 'Rekening Bank',
  'ewallet' => 'E-Wallet',
  _ => 'Lainnya',
};
