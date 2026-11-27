import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sakuin/core/db/app_database.dart';
import 'package:sakuin/core/db/db_provider.dart';
import 'package:sakuin/core/services/gmail_imap_client.dart';
import 'package:sakuin/core/utils/date_utils.dart';
import 'package:sakuin/core/utils/qris_email_parser.dart';
import 'package:sakuin/features/transaction/transaction_providers.dart';

class GmailQrisConfig {
  const GmailQrisConfig({
    this.email = '',
    this.appPassword = '',
    this.enabled = false,
    this.autoSyncOnOpen = true,
    this.autoSaveWithoutReview = false,
    this.lookbackDays = 14,
    this.defaultWalletId,
    this.ignoreOnOrBeforeDayKey,
  });

  final String email;
  final String appPassword;
  final bool enabled;
  final bool autoSyncOnOpen;
  final bool autoSaveWithoutReview;
  final int lookbackDays;
  final int? defaultWalletId;

  /// Batas tanggal (format YYYYMMDD) yang diabaikan saat sinkron email.
  /// Contoh: 20261125 -> transaksi pada 25 Nov 2026 dan sebelumnya tidak diperiksa/dimasukkan.
  final int? ignoreOnOrBeforeDayKey;

  bool get isConfigured =>
      enabled && email.trim().isNotEmpty && appPassword.trim().isNotEmpty;
}

class QrisSyncResult {
  const QrisSyncResult({this.newDrafts = 0, this.autoSaved = 0, this.error});

  final int newDrafts;
  final int autoSaved;
  final String? error;
}

final pendingQrisDraftsProvider = StreamProvider<List<ImportedQrisDraft>>((
  ref,
) {
  return ref.watch(appDatabaseProvider).watchPendingQrisDrafts();
});

final qrisSyncServiceProvider = Provider<QrisSyncService>((ref) {
  return QrisSyncService(ref);
});

class QrisSyncService {
  QrisSyncService(this._ref)
    : _storage = const FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
      );

  static const _kEmail = 'sakuin_gmail_email';
  static const _kAppPass = 'sakuin_gmail_app_password';
  static const _kEnabled = 'sakuin_gmail_enabled';
  static const _kAutoSync = 'sakuin_gmail_auto_sync';
  static const _kAutoSave = 'sakuin_gmail_auto_save';
  static const _kLookbackDays = 'sakuin_gmail_lookback_days';
  static const _kDefaultWalletId = 'sakuin_gmail_default_wallet_id';
  static const _kIgnoreOnOrBeforeDayKey = 'sakuin_gmail_ignore_cutoff_day';

  final Ref _ref;
  final FlutterSecureStorage _storage;

  AppDatabase get _db => _ref.read(appDatabaseProvider);

  /// Mengembalikan true jika [occurredAt] berada pada atau sebelum [ignoreOnOrBeforeDayKey]
  /// sehingga transaksi harus dilewati dan tidak masuk antrean review.
  static bool shouldIgnoreTransactionDate(
    DateTime occurredAt,
    int? ignoreOnOrBeforeDayKey,
  ) {
    if (ignoreOnOrBeforeDayKey == null) return false;
    return AppDateUtils.toDayKey(occurredAt.toLocal()) <=
        ignoreOnOrBeforeDayKey;
  }

  /// Menghitung tanggal `SINCE` paling efisien untuk query IMAP Gmail,
  /// dengan memperhitungkan perbedaan zona waktu server (UTC/PST vs WIB)
  /// agar email dini hari setelah batas tanggal tidak terlewat.
  static DateTime computeImapSinceDate({
    required DateTime now,
    required int lookbackDays,
    int? ignoreOnOrBeforeDayKey,
  }) {
    final today = DateTime(now.year, now.month, now.day);
    final lookbackSince = today.subtract(Duration(days: lookbackDays));
    if (ignoreOnOrBeforeDayKey == null) return lookbackSince;

    final cutoffDate = AppDateUtils.fromDayKey(ignoreOnOrBeforeDayKey);
    return cutoffDate.isAfter(lookbackSince) ? cutoffDate : lookbackSince;
  }

  Future<GmailQrisConfig> loadConfig() async {
    try {
      final email = await _storage.read(key: _kEmail) ?? '';
      final pass = await _storage.read(key: _kAppPass) ?? '';
      final enabled = (await _storage.read(key: _kEnabled)) == '1';
      final autoSync = (await _storage.read(key: _kAutoSync)) != '0';
      final autoSave = (await _storage.read(key: _kAutoSave)) == '1';
      final lookback =
          int.tryParse(await _storage.read(key: _kLookbackDays) ?? '14') ?? 14;
      final defaultWallet = int.tryParse(
        await _storage.read(key: _kDefaultWalletId) ?? '',
      );
      final ignoreCutoffDay = int.tryParse(
        await _storage.read(key: _kIgnoreOnOrBeforeDayKey) ?? '',
      );
      return GmailQrisConfig(
        email: email,
        appPassword: pass,
        enabled: enabled,
        autoSyncOnOpen: autoSync,
        autoSaveWithoutReview: autoSave,
        lookbackDays: lookback,
        defaultWalletId: defaultWallet,
        ignoreOnOrBeforeDayKey: ignoreCutoffDay,
      );
    } catch (_) {
      return const GmailQrisConfig();
    }
  }

  Future<void> saveConfig(GmailQrisConfig config) async {
    await _storage.write(key: _kEmail, value: config.email.trim());
    await _storage.write(
      key: _kAppPass,
      value: config.appPassword.replaceAll(' ', '').trim(),
    );
    await _storage.write(key: _kEnabled, value: config.enabled ? '1' : '0');
    await _storage.write(
      key: _kAutoSync,
      value: config.autoSyncOnOpen ? '1' : '0',
    );
    await _storage.write(
      key: _kAutoSave,
      value: config.autoSaveWithoutReview ? '1' : '0',
    );
    await _storage.write(
      key: _kLookbackDays,
      value: config.lookbackDays.toString(),
    );
    if (config.defaultWalletId != null) {
      await _storage.write(
        key: _kDefaultWalletId,
        value: config.defaultWalletId.toString(),
      );
    } else {
      await _storage.delete(key: _kDefaultWalletId);
    }
    if (config.ignoreOnOrBeforeDayKey != null) {
      await _storage.write(
        key: _kIgnoreOnOrBeforeDayKey,
        value: config.ignoreOnOrBeforeDayKey.toString(),
      );
    } else {
      await _storage.delete(key: _kIgnoreOnOrBeforeDayKey);
    }
  }

  Future<void> disconnect() async {
    await _storage.delete(key: _kEmail);
    await _storage.delete(key: _kAppPass);
    await _storage.write(key: _kEnabled, value: '0');
  }

  Future<void> testConnection(String email, String appPassword) {
    return GmailImapClient().testConnection(
      email: email,
      appPassword: appPassword,
    );
  }

  /// Sinkronisasi email QRIS dari Gmail ke antrean Review (atau langsung simpan jika diaktifkan).
  Future<QrisSyncResult> syncNow() async {
    final config = await loadConfig();
    if (!config.isConfigured) {
      return const QrisSyncResult();
    }

    try {
      final existingDrafts = await _db.select(_db.importedQrisDrafts).get();
      final seenUids = existingDrafts.map((d) => d.emailUid).toSet();

      final rawMessages = await GmailImapClient().fetchRecentQrisEmails(
        email: config.email,
        appPassword: config.appPassword,
        lookbackDays: config.lookbackDays,
        alreadyImportedUids: seenUids,
        ignoreOnOrBeforeDayKey: config.ignoreOnOrBeforeDayKey,
      );
      if (rawMessages.isEmpty) return const QrisSyncResult();

      final wallets = await _db.getWalletsWithBalances();
      final foodCatId = await _db.findCategoryIdByName(
        'Makanan & Minuman',
        'expense',
      );
      final otherCatId = await _db.findCategoryIdByName('Lainnya', 'expense');
      final defaultCatId = foodCatId ?? otherCatId;

      var newDrafts = 0;
      var autoSaved = 0;

      for (final msg in rawMessages) {
        final parsed = QrisEmailParser.parse(
          from: msg.from,
          subject: msg.subject,
          rawBody: msg.body,
          emailDate: msg.date,
        );
        if (parsed == null) continue;
        if (shouldIgnoreTransactionDate(
          parsed.occurredAt,
          config.ignoreOnOrBeforeDayKey,
        )) {
          continue;
        }

        final matchedWalletId = _matchWallet(
          wallets,
          parsed.bankName,
          config.defaultWalletId,
        );

        if (config.autoSaveWithoutReview && matchedWalletId != null) {
          final draftId = await _db.insertQrisDraftIfNew(
            emailUid: msg.uid,
            sender: msg.from,
            subject: msg.subject,
            bankName: parsed.bankName,
            merchantName: parsed.merchantName,
            amount: parsed.amount,
            occurredAt: parsed.occurredAt,
            suggestedWalletId: matchedWalletId,
            rawSnippet: parsed.snippet,
            status: 'confirmed',
          );
          if (draftId != null) {
            await _ref
                .read(transactionActionsProvider)
                .saveTransaction(
                  type: 'expense',
                  amount: parsed.amount,
                  walletId: matchedWalletId,
                  categoryId: defaultCatId,
                  itemName: parsed.merchantName,
                  note: 'QRIS ${parsed.bankName}',
                  occurredAt: parsed.occurredAt,
                );
            autoSaved++;
          }
        } else {
          final draftId = await _db.insertQrisDraftIfNew(
            emailUid: msg.uid,
            sender: msg.from,
            subject: msg.subject,
            bankName: parsed.bankName,
            merchantName: parsed.merchantName,
            amount: parsed.amount,
            occurredAt: parsed.occurredAt,
            suggestedWalletId: matchedWalletId,
            rawSnippet: parsed.snippet,
            status: 'pending',
          );
          if (draftId != null) newDrafts++;
        }
      }

      return QrisSyncResult(newDrafts: newDrafts, autoSaved: autoSaved);
    } catch (e) {
      return QrisSyncResult(error: '$e');
    }
  }

  int? _matchWallet(
    List<WalletWithBalance> wallets,
    String bankName,
    int? fallbackWalletId,
  ) {
    final lowerBank = bankName.toLowerCase();
    for (final wb in wallets) {
      final wName = wb.wallet.name.toLowerCase();
      if (wName.contains(lowerBank) || lowerBank.contains(wName)) {
        return wb.wallet.id;
      }
    }
    if (fallbackWalletId != null &&
        wallets.any((w) => w.wallet.id == fallbackWalletId)) {
      return fallbackWalletId;
    }
    return wallets.isNotEmpty ? wallets.first.wallet.id : null;
  }

  /// Konfirmasi 1 ketukan dari antrean Review -> simpan sebagai pengeluaran atau pemasukan,
  /// sekaligus melatih pasangan Merchant <-> Item, Kategori, Dompet, & Pos Budget otomatis.
  Future<void> confirmDraftAsSingle(
    ImportedQrisDraft draft, {
    required int walletId,
    int? categoryId,
    int? pocketId,
    String? itemName,
    String? merchantName,
  }) async {
    final txType = draft.txType == 'income' ? 'income' : 'expense';
    final fallbackCat =
        categoryId ??
        (txType == 'income'
            ? (await _db.findCategoryIdByName('Lainnya', 'income') ??
                  await _db.findCategoryIdByName('Bonus', 'income'))
            : (await _db.findCategoryIdByName('Makanan & Minuman', 'expense') ??
                  await _db.findCategoryIdByName('Lainnya', 'expense')));
    final effectiveMerchant =
        (merchantName != null && merchantName.trim().isNotEmpty)
        ? merchantName.trim()
        : draft.merchantName.trim();
    final isGenericMerchant =
        effectiveMerchant.toLowerCase() == 'pembayaran qris' ||
        effectiveMerchant.toLowerCase().startsWith('transaksi ') ||
        effectiveMerchant.toLowerCase().startsWith('dana masuk ');
    final finalItemName = (itemName != null && itemName.trim().isNotEmpty)
        ? itemName.trim()
        : effectiveMerchant;
    final noteBase = txType == 'income'
        ? 'Notifikasi Masuk ${draft.bankName}'
        : 'QRIS ${draft.bankName}';
    await _db.saveTransactionWithMemory(
      type: txType,
      amount: draft.amount,
      walletId: walletId,
      categoryId: fallbackCat,
      pocketId: pocketId,
      itemName: finalItemName,
      merchantName: isGenericMerchant ? null : effectiveMerchant,
      note: noteBase,
      externalRef: draft.emailUid,
      occurredAt: DateTime.fromMillisecondsSinceEpoch(draft.occurredAt)
          .toLocal(),
    );
    await _db.markQrisDraftStatus(draft.id, 'confirmed');
    _ref.read(transactionRevisionProvider.notifier).state++;
  }

  Future<void> markDraftConfirmed(int draftId) =>
      _db.markQrisDraftStatus(draftId, 'confirmed');

  Future<void> dismissDraft(int draftId) =>
      _db.markQrisDraftStatus(draftId, 'dismissed');

  /// Hapus antrean review pending yang tanggal transaksinya <= [cutoffDayKey].
  /// Dihapus (bukan ditandai dismissed) agar jika pengguna memundurkan batas tanggal
  /// ke hari sebelumnya di kemudian hari, email tersebut bisa masuk kembali saat sinkron.
  Future<int> dismissPendingDraftsOnOrBefore(int cutoffDayKey) async {
    final pending = await (_db.select(
      _db.importedQrisDrafts,
    )..where((d) => d.status.equals('pending'))).get();
    var removed = 0;
    for (final draft in pending) {
      final occurred = DateTime.fromMillisecondsSinceEpoch(draft.occurredAt)
          .toLocal();
      if (shouldIgnoreTransactionDate(occurred, cutoffDayKey)) {
        await (_db.delete(
          _db.importedQrisDrafts,
        )..where((d) => d.id.equals(draft.id))).go();
        removed++;
      }
    }
    return removed;
  }

  /// Pulihkan draft yang sebelumnya berstatus 'dismissed' namun tanggal transaksinya
  /// lolos filter batas tanggal terbaru ([cutoffDayKey]) kembali ke antrean 'pending'.
  Future<int> restoreDismissedDraftsAfter(int? cutoffDayKey) async {
    final dismissed = await (_db.select(
      _db.importedQrisDrafts,
    )..where((d) => d.status.equals('dismissed'))).get();
    var restored = 0;
    for (final draft in dismissed) {
      final occurred = DateTime.fromMillisecondsSinceEpoch(draft.occurredAt)
          .toLocal();
      if (!shouldIgnoreTransactionDate(occurred, cutoffDayKey)) {
        await _db.markQrisDraftStatus(draft.id, 'pending');
        restored++;
      }
    }
    return restored;
  }
}
