import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sakuin/core/db/app_database.dart';
import 'package:sakuin/core/db/db_provider.dart';
import 'package:sakuin/core/services/notification_service.dart';
import 'package:sakuin/core/utils/date_utils.dart';
import 'package:sakuin/features/transaction/transaction_providers.dart';

final recurringRulesProvider = StreamProvider<List<RecurringRule>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.recurringRules)..orderBy([
        (r) => OrderingTerm.desc(r.isActive),
        (r) => OrderingTerm.asc(r.nextDue),
      ]))
      .watch();
});

final pendingRecurringRulesProvider = Provider<List<RecurringRule>>((ref) {
  final rules = ref.watch(recurringRulesProvider).valueOrNull ?? const [];
  final todayKey = AppDateUtils.toDayKey(DateTime.now());
  return rules
      .where((r) => r.isActive && !r.autoCreate && r.nextDue <= todayKey)
      .toList();
});

final recurringServiceProvider = Provider<RecurringService>((ref) {
  return RecurringService(ref);
});

class RecurringService {
  RecurringService(this._ref);

  final Ref _ref;
  AppDatabase get _db => _ref.read(appDatabaseProvider);

  static int computeNextDue({
    required int currentDueDayKey,
    required String frequency,
    int? dayOfWeek,
    int? dayOfMonth,
  }) {
    final current = AppDateUtils.fromDayKey(currentDueDayKey);
    switch (frequency) {
      case 'daily':
        return AppDateUtils.toDayKey(current.add(const Duration(days: 1)));
      case 'weekly':
        return AppDateUtils.toDayKey(current.add(const Duration(days: 7)));
      case 'monthly':
      default:
        final dom = (dayOfMonth ?? current.day).clamp(1, 28);
        final next = DateTime(current.year, current.month + 1, dom);
        return AppDateUtils.toDayKey(next);
    }
  }

  /// Proses aturan yang jatuh tempo saat aplikasi dibuka.
  Future<int> processDueRules({DateTime? now}) async {
    final today = now ?? DateTime.now();
    final todayKey = AppDateUtils.toDayKey(today);
    final rules =
        await (_db.select(_db.recurringRules)..where(
              (r) =>
                  r.isActive.equals(true) &
                  r.nextDue.isSmallerOrEqualValue(todayKey),
            ))
            .get();

    var createdCount = 0;
    final notif = _ref.read(notificationServiceProvider);

    for (final rule in rules) {
      if (rule.autoCreate) {
        var dueKey = rule.nextDue;
        var guard = 0;
        while (dueKey <= todayKey && guard < 31) {
          final dueDate = AppDateUtils.fromDayKey(dueKey);
          await _db.saveTransactionWithMemory(
            type: rule.type,
            amount: rule.amount,
            walletId: rule.walletId,
            categoryId: rule.categoryId,
            itemName: rule.title,
            note: rule.note.isEmpty ? 'Transaksi berulang' : rule.note,
            occurredAt: DateTime(
              dueDate.year,
              dueDate.month,
              dueDate.day,
              9,
              0,
            ),
            updateItemMemory: false,
          );
          createdCount++;
          dueKey = computeNextDue(
            currentDueDayKey: dueKey,
            frequency: rule.frequency,
            dayOfWeek: rule.dayOfWeek,
            dayOfMonth: rule.dayOfMonth,
          );
          guard++;
        }
        await (_db.update(_db.recurringRules)
              ..where((r) => r.id.equals(rule.id)))
            .write(RecurringRulesCompanion(nextDue: Value(dueKey)));
        await notif.showRecurringNotification(
          ruleId: rule.id,
          title: rule.title,
          amount: rule.amount,
          autoCreated: true,
        );
      } else {
        await notif.showRecurringNotification(
          ruleId: rule.id,
          title: rule.title,
          amount: rule.amount,
          autoCreated: false,
        );
      }
    }

    if (createdCount > 0) {
      _ref.read(transactionRevisionProvider.notifier).state++;
    }
    return createdCount;
  }

  Future<void> confirmRuleNow(RecurringRule rule) async {
    await _ref
        .read(transactionActionsProvider)
        .saveTransaction(
          type: rule.type,
          amount: rule.amount,
          walletId: rule.walletId,
          categoryId: rule.categoryId,
          itemName: rule.title,
          note: rule.note.isEmpty ? 'Transaksi berulang' : rule.note,
          occurredAt: DateTime.now(),
        );
    final nextDue = computeNextDue(
      currentDueDayKey: rule.nextDue,
      frequency: rule.frequency,
      dayOfWeek: rule.dayOfWeek,
      dayOfMonth: rule.dayOfMonth,
    );
    await (_db.update(_db.recurringRules)..where((r) => r.id.equals(rule.id)))
        .write(RecurringRulesCompanion(nextDue: Value(nextDue)));
  }

  Future<void> skipRuleOccurrence(RecurringRule rule) async {
    final nextDue = computeNextDue(
      currentDueDayKey: rule.nextDue,
      frequency: rule.frequency,
      dayOfWeek: rule.dayOfWeek,
      dayOfMonth: rule.dayOfMonth,
    );
    await (_db.update(_db.recurringRules)..where((r) => r.id.equals(rule.id)))
        .write(RecurringRulesCompanion(nextDue: Value(nextDue)));
  }

  Future<int> saveRule({
    int? id,
    required String title,
    required String type,
    required int amount,
    int? categoryId,
    required int walletId,
    required String note,
    required String frequency,
    int? dayOfWeek,
    int? dayOfMonth,
    required int nextDue,
    required bool autoCreate,
    required bool isActive,
  }) async {
    if (id != null) {
      await (_db.update(
        _db.recurringRules,
      )..where((r) => r.id.equals(id))).write(
        RecurringRulesCompanion(
          title: Value(title.trim()),
          type: Value(type),
          amount: Value(amount),
          categoryId: Value(categoryId),
          walletId: Value(walletId),
          note: Value(note.trim()),
          frequency: Value(frequency),
          dayOfWeek: Value(dayOfWeek),
          dayOfMonth: Value(dayOfMonth),
          nextDue: Value(nextDue),
          autoCreate: Value(autoCreate),
          isActive: Value(isActive),
        ),
      );
      return id;
    }
    return _db
        .into(_db.recurringRules)
        .insert(
          RecurringRulesCompanion.insert(
            title: title.trim(),
            type: type,
            amount: amount,
            categoryId: Value(categoryId),
            walletId: walletId,
            note: Value(note.trim()),
            frequency: frequency,
            dayOfWeek: Value(dayOfWeek),
            dayOfMonth: Value(dayOfMonth),
            nextDue: nextDue,
            autoCreate: Value(autoCreate),
            isActive: Value(isActive),
          ),
        );
  }

  Future<void> toggleActive(int id, bool active) async {
    await (_db.update(_db.recurringRules)..where((r) => r.id.equals(id))).write(
      RecurringRulesCompanion(isActive: Value(active)),
    );
  }

  Future<void> deleteRule(int id) async {
    await (_db.delete(_db.recurringRules)..where((r) => r.id.equals(id))).go();
  }
}

String frequencyLabel(String freq) => switch (freq) {
  'daily' => 'Harian',
  'weekly' => 'Mingguan',
  _ => 'Bulanan',
};
