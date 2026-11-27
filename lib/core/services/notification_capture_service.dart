import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sakuin/core/db/app_database.dart';
import 'package:sakuin/core/db/db_provider.dart';
import 'package:sakuin/core/services/qris_sync_service.dart';
import 'package:sakuin/core/utils/notification_tx_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationCaptureStatus {
  const NotificationCaptureStatus({
    required this.enabledInApp,
    required this.osPermissionGranted,
  });

  final bool enabledInApp;
  final bool osPermissionGranted;

  bool get isActive => enabledInApp && osPermissionGranted;
}

class NotificationCaptureService {
  NotificationCaptureService(this._ref);

  static const _channel = MethodChannel('id.rakavalrizqy.sakuin/notif_capture');
  static const _kEnabledPref = 'sakuin_notif_capture_enabled';

  final Ref _ref;
  AppDatabase get _db => _ref.read(appDatabaseProvider);

  Future<bool> isOsPermissionGranted() async {
    try {
      return await _channel.invokeMethod<bool>(
            'isNotificationListenerEnabled',
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<void> openOsListenerSettings() async {
    try {
      await _channel.invokeMethod('openNotificationListenerSettings');
    } catch (_) {}
  }

  Future<void> openAppInfoSettings() async {
    try {
      await _channel.invokeMethod('openAppInfoSettings');
    } catch (_) {}
  }

  Future<bool> isEnabledInApp() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_kEnabledPref) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> setEnabled(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kEnabledPref, enabled);
      await _channel.invokeMethod('setNotificationCaptureEnabled', {
        'enabled': enabled,
      });
    } catch (_) {}
  }

  Future<NotificationCaptureStatus> getStatus() async {
    final enabled = await isEnabledInApp();
    final granted = await isOsPermissionGranted();
    // Pastikan flag native selalu sinkron dengan preferensi aplikasi
    if (enabled) {
      try {
        await _channel.invokeMethod('setNotificationCaptureEnabled', {
          'enabled': true,
        });
      } catch (_) {}
    }
    return NotificationCaptureStatus(
      enabledInApp: enabled,
      osPermissionGranted: granted,
    );
  }

  /// Tarik antrean notifikasi bank/e-wallet yang tertangkap secara lokal di HP
  /// dan masukkan ke antrean Review yang sama dengan Auto QRIS (dedup otomatis).
  Future<int> importCapturedNotifications() async {
    final enabled = await isEnabledInApp();
    if (!enabled) return 0;

    List<dynamic> rawItems;
    try {
      rawItems =
          await _channel.invokeMethod<List<dynamic>>(
            'consumeCapturedNotifications',
          ) ??
          const [];
    } catch (_) {
      return 0;
    }
    if (rawItems.isEmpty) return 0;

    final qrisCfg = await _ref.read(qrisSyncServiceProvider).loadConfig();
    final wallets = await _db.getWalletsWithBalances();
    var added = 0;

    for (final raw in rawItems) {
      if (raw is! Map) continue;
      final pkg = (raw['packageName'] as String?) ?? '';
      final title = (raw['title'] as String?) ?? '';
      final text = (raw['text'] as String?) ?? '';
      final tsMillis = (raw['timestamp'] as num?)?.toInt() ?? 0;
      final ts = tsMillis > 0
          ? DateTime.fromMillisecondsSinceEpoch(tsMillis).toLocal()
          : DateTime.now();

      if (QrisSyncService.shouldIgnoreTransactionDate(
        ts,
        qrisCfg.ignoreOnOrBeforeDayKey,
      )) {
        continue;
      }

      final parsed = NotificationTxParser.parse(
        packageName: pkg,
        title: title,
        text: text,
        timestamp: ts,
      );
      if (parsed == null) continue;

      final matchedWalletId = _matchWallet(
        wallets,
        parsed.bankName,
        qrisCfg.defaultWalletId,
      );

      final draftId = await _db.insertQrisDraftIfNew(
        emailUid: parsed.uid,
        sender: 'Notifikasi ${parsed.bankName}',
        subject: parsed.title,
        bankName: parsed.bankName,
        merchantName: parsed.merchantName,
        amount: parsed.amount,
        occurredAt: parsed.occurredAt,
        suggestedWalletId: matchedWalletId,
        rawSnippet: parsed.snippet,
        status: 'pending',
      );
      if (draftId != null) added++;
    }

    return added;
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
}

final notificationCaptureServiceProvider = Provider<NotificationCaptureService>(
  (ref) => NotificationCaptureService(ref),
);

final notificationCaptureStatusProvider =
    FutureProvider<NotificationCaptureStatus>((ref) {
      return ref.watch(notificationCaptureServiceProvider).getStatus();
    });
