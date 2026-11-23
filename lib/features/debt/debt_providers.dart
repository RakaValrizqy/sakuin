import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sakuin/core/db/app_database.dart';
import 'package:sakuin/core/db/db_provider.dart';
import 'package:sakuin/core/services/notification_service.dart';
import 'package:sakuin/core/utils/currency_formatter.dart';
import 'package:sakuin/core/utils/date_utils.dart';
import 'package:share_plus/share_plus.dart';

final allDebtsProvider = StreamProvider<List<DebtWithSummary>>((ref) {
  return ref.watch(appDatabaseProvider).watchDebtsWithSummary();
});

final peopleProvider = StreamProvider<List<Person>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(
    db.people,
  )..orderBy([(p) => OrderingTerm.asc(p.name)])).watch();
});

final personDebtSummariesProvider = StreamProvider<List<PersonDebtSummary>>((
  ref,
) {
  return ref.watch(appDatabaseProvider).watchPersonDebtSummaries();
});

final debtPaymentsProvider = StreamProvider.family<List<DebtPayment>, int>((
  ref,
  debtId,
) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.debtPayments)
        ..where((dp) => dp.debtId.equals(debtId))
        ..orderBy([(dp) => OrderingTerm.desc(dp.paidAt)]))
      .watch();
});

class DebtTotals {
  const DebtTotals({required this.iOweTotal, required this.theyOweTotal});

  final int iOweTotal;
  final int theyOweTotal;

  /// Positif = lebih banyak piutang (akan diterima); Negatif = lebih banyak hutang.
  int get net => theyOweTotal - iOweTotal;
}

final debtTotalsProvider = Provider<DebtTotals>((ref) {
  final debts = ref.watch(allDebtsProvider).valueOrNull ?? const [];
  var iOwe = 0;
  var theyOwe = 0;
  for (final d in debts) {
    if (d.debt.status != 'open') continue;
    if (d.debt.direction == 'i_owe') {
      iOwe += d.remaining;
    } else {
      theyOwe += d.remaining;
    }
  }
  return DebtTotals(iOweTotal: iOwe, theyOweTotal: theyOwe);
});

final debtActionsProvider = Provider<DebtActions>((ref) {
  return DebtActions(ref);
});

class DebtActions {
  DebtActions(this._ref);

  final Ref _ref;
  AppDatabase get _db => _ref.read(appDatabaseProvider);
  NotificationService get _notif => _ref.read(notificationServiceProvider);

  Future<int> saveDebt({
    int? existingId,
    required String personName,
    String? personPhone,
    required String direction,
    required int principal,
    required String note,
    required DateTime createdAt,
    DateTime? dueDate,
    int? walletId,
  }) async {
    final person = await _db.findOrCreatePerson(personName, phone: personPhone);
    late int debtId;
    if (existingId != null) {
      await (_db.update(
        _db.debts,
      )..where((d) => d.id.equals(existingId))).write(
        DebtsCompanion(
          personId: Value(person.id),
          direction: Value(direction),
          principal: Value(principal),
          note: Value(note.trim()),
          createdAt: Value(createdAt.toUtc().millisecondsSinceEpoch),
          dueDate: Value(dueDate?.toUtc().millisecondsSinceEpoch),
          walletId: Value(walletId),
        ),
      );
      debtId = existingId;
    } else {
      debtId = await _db
          .into(_db.debts)
          .insert(
            DebtsCompanion.insert(
              personId: person.id,
              direction: direction,
              principal: principal,
              note: Value(note.trim()),
              createdAt: createdAt.toUtc().millisecondsSinceEpoch,
              dueDate: Value(dueDate?.toUtc().millisecondsSinceEpoch),
              walletId: Value(walletId),
            ),
          );
    }

    await _notif.scheduleDebtReminder(
      debtId: debtId,
      personName: person.name,
      direction: direction,
      remaining: principal,
      dueDate: dueDate,
    );
    return debtId;
  }

  Future<void> addPayment({
    required DebtWithSummary debtSummary,
    required int amount,
    required DateTime paidAt,
    int? walletId,
    String note = '',
  }) async {
    await _db.addDebtPayment(
      debtId: debtSummary.debt.id,
      amount: amount,
      paidAt: paidAt,
      walletId: walletId,
      note: note,
    );
    final newRemaining = (debtSummary.remaining - amount).clamp(
      0,
      debtSummary.debt.principal,
    );
    if (newRemaining <= 0) {
      await _notif.cancelDebtReminder(debtSummary.debt.id);
    } else if (debtSummary.debt.dueDate != null) {
      await _notif.scheduleDebtReminder(
        debtId: debtSummary.debt.id,
        personName: debtSummary.person.name,
        direction: debtSummary.debt.direction,
        remaining: newRemaining,
        dueDate: DateTime.fromMillisecondsSinceEpoch(debtSummary.debt.dueDate!)
            .toLocal(),
      );
    }
  }

  Future<void> deletePayment(int paymentId, int debtId) async {
    await _db.deleteDebtPayment(paymentId, debtId);
  }

  Future<void> deleteDebt(int debtId) async {
    await (_db.delete(_db.debts)..where((d) => d.id.equals(debtId))).go();
    await _notif.cancelDebtReminder(debtId);
  }

  Future<void> shareBillingReminder(DebtWithSummary item) async {
    final amountStr = CurrencyFormatter.format(item.remaining);
    final duePart = item.debt.dueDate != null
        ? ' (jatuh tempo ${AppDateUtils.formatShortDate(DateTime.fromMillisecondsSinceEpoch(item.debt.dueDate!).toLocal())})'
        : '';
    final notePart = item.debt.note.isNotEmpty
        ? ' untuk "${item.debt.note}"'
        : '';

    final message = item.debt.direction == 'they_owe'
        ? 'Halo ${item.person.name}, izin mengingatkan ya 😊 Masih ada sisa catatan pinjaman sebesar $amountStr$notePart$duePart. Terima kasih banyak!'
        : 'Halo ${item.person.name}, catatan hutang saya ke kamu masih tersisa $amountStr$notePart$duePart. Akan segera saya selesaikan ya. Terima kasih!';

    await SharePlus.instance.share(
      ShareParams(text: message, subject: 'Pengingat Catatan Hutang-Piutang'),
    );
  }
}
