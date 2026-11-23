import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sakuin/core/db/app_database.dart';
import 'package:sakuin/core/db/db_provider.dart';

final expenseCategoriesProvider = StreamProvider<List<Category>>((ref) {
  return ref.watch(appDatabaseProvider).watchCategories(type: 'expense');
});

final incomeCategoriesProvider = StreamProvider<List<Category>>((ref) {
  return ref.watch(appDatabaseProvider).watchCategories(type: 'income');
});

final allCategoriesProvider = StreamProvider<List<Category>>((ref) {
  return ref.watch(appDatabaseProvider).watchCategories(includeArchived: true);
});

final categoryActionsProvider = Provider<CategoryActions>((ref) {
  return CategoryActions(ref.watch(appDatabaseProvider));
});

class CategoryActions {
  CategoryActions(this._db);

  final AppDatabase _db;

  Future<int> saveCategory({
    int? id,
    required String name,
    required String type,
    required String icon,
    required int color,
  }) async {
    if (id != null) {
      await (_db.update(_db.categories)..where((c) => c.id.equals(id))).write(
        CategoriesCompanion(
          name: Value(name.trim()),
          type: Value(type),
          icon: Value(icon),
          color: Value(color),
        ),
      );
      return id;
    }

    final existing = await (_db.select(
      _db.categories,
    )..where((c) => c.type.equals(type))).get();
    return _db
        .into(_db.categories)
        .insert(
          CategoriesCompanion.insert(
            name: name.trim(),
            type: type,
            icon: icon,
            color: color,
            sortOrder: Value(existing.length),
          ),
        );
  }

  Future<void> setArchived(int id, bool archived) async {
    await (_db.update(_db.categories)..where((c) => c.id.equals(id))).write(
      CategoriesCompanion(isArchived: Value(archived)),
    );
  }
}
