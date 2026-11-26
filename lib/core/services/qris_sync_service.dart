import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sakuin/core/db/app_database.dart';
import 'package:sakuin/core/db/db_provider.dart';
import 'package:sakuin/core/services/gmail_imap_client.dart';
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
  });

  final String email;
  final String appPassword;
  final bool enabled;
  final bool autoSyncOnOpen;
  final bool autoSaveWithoutReview;
  final int lookbackDays;
  final int? defaultWalletId;

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

  final Ref _ref;
  final FlutterSecureStorage _storage;

  AppDatabase get _db => _ref.read(appDatabaseProvider);

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
      return GmailQrisConfig(
        email: email,
        appPassword: pass,
        enabled: enabled,
        autoSyncOnOpen: autoSync,
        autoSaveWithoutReview: autoSave,
        lookbackDays: lookback,
        defaultWalletId: defaultWallet,
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

  /// Konfirmasi 1 ketukan dari antrean Review -> simpan sebagai pengeluaran.
  Future<void> confirmDraftAsSingle(
    ImportedQrisDraft draft, {
    required int walletId,
    int? categoryId,
    int? pocketId,
  }) async {
    final fallbackCat =
        categoryId ??
        await _db.findCategoryIdByName('Makanan & Minuman', 'expense') ??
        await _db.findCategoryIdByName('Lainnya', 'expense');
    await _db.saveTransactionWithMemory(
      type: 'expense',
      amount: draft.amount,
      walletId: walletId,
      categoryId: fallbackCat,
      pocketId: pocketId,
      itemName: draft.merchantName,
      note: 'QRIS ${draft.bankName}',
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
}
