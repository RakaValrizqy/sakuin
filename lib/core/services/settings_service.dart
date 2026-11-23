import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  const AppSettings({
    this.periodStartDay = 1,
    this.themeMode = ThemeMode.system,
    this.hapticsEnabled = true,
    this.quickSaveMode = false,
    this.hideBalances = false,
    this.secureScreen = false,
    this.reminderEnabled = false,
    this.reminderHour = 20,
    this.reminderMinute = 0,
    this.backupReminderEnabled = false,
    this.lastBackupMillis,
    this.pinEnabled = false,
    this.biometricEnabled = false,
    this.autoLockSeconds = 0, // 0 = langsung, 60 = 1 menit, 300 = 5 menit
    this.lastWalletId,
    this.onboardingCompleted = false,
  });

  final int periodStartDay;
  final ThemeMode themeMode;
  final bool hapticsEnabled;
  final bool quickSaveMode;
  final bool hideBalances;
  final bool secureScreen;
  final bool reminderEnabled;
  final int reminderHour;
  final int reminderMinute;
  final bool backupReminderEnabled;
  final int? lastBackupMillis;
  final bool pinEnabled;
  final bool biometricEnabled;
  final int autoLockSeconds;
  final int? lastWalletId;
  final bool onboardingCompleted;

  AppSettings copyWith({
    int? periodStartDay,
    ThemeMode? themeMode,
    bool? hapticsEnabled,
    bool? quickSaveMode,
    bool? hideBalances,
    bool? secureScreen,
    bool? reminderEnabled,
    int? reminderHour,
    int? reminderMinute,
    bool? backupReminderEnabled,
    int? lastBackupMillis,
    bool clearLastBackup = false,
    bool? pinEnabled,
    bool? biometricEnabled,
    int? autoLockSeconds,
    int? lastWalletId,
    bool clearLastWallet = false,
    bool? onboardingCompleted,
  }) {
    return AppSettings(
      periodStartDay: periodStartDay ?? this.periodStartDay,
      themeMode: themeMode ?? this.themeMode,
      hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
      quickSaveMode: quickSaveMode ?? this.quickSaveMode,
      hideBalances: hideBalances ?? this.hideBalances,
      secureScreen: secureScreen ?? this.secureScreen,
      reminderEnabled: reminderEnabled ?? this.reminderEnabled,
      reminderHour: reminderHour ?? this.reminderHour,
      reminderMinute: reminderMinute ?? this.reminderMinute,
      backupReminderEnabled:
          backupReminderEnabled ?? this.backupReminderEnabled,
      lastBackupMillis: clearLastBackup
          ? null
          : (lastBackupMillis ?? this.lastBackupMillis),
      pinEnabled: pinEnabled ?? this.pinEnabled,
      biometricEnabled: biometricEnabled ?? this.biometricEnabled,
      autoLockSeconds: autoLockSeconds ?? this.autoLockSeconds,
      lastWalletId: clearLastWallet
          ? null
          : (lastWalletId ?? this.lastWalletId),
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
    );
  }
}

class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier() : super(const AppSettings()) {
    _load();
  }

  static const _kPeriodStartDay = 'period_start_day';
  static const _kThemeMode = 'theme_mode';
  static const _kHaptics = 'haptics_enabled';
  static const _kQuickSave = 'quick_save_mode';
  static const _kHideBalances = 'hide_balances';
  static const _kSecureScreen = 'secure_screen';
  static const _kReminderEnabled = 'reminder_enabled';
  static const _kReminderHour = 'reminder_hour';
  static const _kReminderMinute = 'reminder_minute';
  static const _kBackupReminder = 'backup_reminder_enabled';
  static const _kLastBackupMillis = 'last_backup_millis';
  static const _kPinEnabled = 'pin_enabled';
  static const _kBiometricEnabled = 'biometric_enabled';
  static const _kAutoLockSeconds = 'auto_lock_seconds';
  static const _kLastWalletId = 'last_wallet_id';
  static const _kOnboardingCompleted = 'onboarding_completed';

  SharedPreferences? _prefs;
  bool _loaded = false;
  bool get isLoaded => _loaded;

  Future<SharedPreferences> _getPrefs() async =>
      _prefs ??= await SharedPreferences.getInstance();

  Future<void> _load() async {
    final prefs = await _getPrefs();
    final themeIndex = prefs.getInt(_kThemeMode) ?? 0;
    final themeMode = switch (themeIndex) {
      1 => ThemeMode.light,
      2 => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    state = AppSettings(
      periodStartDay: (prefs.getInt(_kPeriodStartDay) ?? 1).clamp(1, 28),
      themeMode: themeMode,
      hapticsEnabled: prefs.getBool(_kHaptics) ?? true,
      quickSaveMode: prefs.getBool(_kQuickSave) ?? false,
      hideBalances: prefs.getBool(_kHideBalances) ?? false,
      secureScreen: prefs.getBool(_kSecureScreen) ?? false,
      reminderEnabled: prefs.getBool(_kReminderEnabled) ?? false,
      reminderHour: prefs.getInt(_kReminderHour) ?? 20,
      reminderMinute: prefs.getInt(_kReminderMinute) ?? 0,
      backupReminderEnabled: prefs.getBool(_kBackupReminder) ?? false,
      lastBackupMillis: prefs.getInt(_kLastBackupMillis),
      pinEnabled: prefs.getBool(_kPinEnabled) ?? false,
      biometricEnabled: prefs.getBool(_kBiometricEnabled) ?? false,
      autoLockSeconds: prefs.getInt(_kAutoLockSeconds) ?? 0,
      lastWalletId: prefs.getInt(_kLastWalletId),
      onboardingCompleted: prefs.getBool(_kOnboardingCompleted) ?? false,
    );
    _loaded = true;
  }

  Future<void> setPeriodStartDay(int day) async {
    final safe = day.clamp(1, 28);
    state = state.copyWith(periodStartDay: safe);
    final prefs = await _getPrefs();
    await prefs.setInt(_kPeriodStartDay, safe);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    final prefs = await _getPrefs();
    final idx = switch (mode) {
      ThemeMode.light => 1,
      ThemeMode.dark => 2,
      ThemeMode.system => 0,
    };
    await prefs.setInt(_kThemeMode, idx);
  }

  Future<void> setHapticsEnabled(bool v) async {
    state = state.copyWith(hapticsEnabled: v);
    final prefs = await _getPrefs();
    await prefs.setBool(_kHaptics, v);
  }

  Future<void> setQuickSaveMode(bool v) async {
    state = state.copyWith(quickSaveMode: v);
    final prefs = await _getPrefs();
    await prefs.setBool(_kQuickSave, v);
  }

  Future<void> setHideBalances(bool v) async {
    state = state.copyWith(hideBalances: v);
    final prefs = await _getPrefs();
    await prefs.setBool(_kHideBalances, v);
  }

  Future<void> setSecureScreen(bool v) async {
    state = state.copyWith(secureScreen: v);
    final prefs = await _getPrefs();
    await prefs.setBool(_kSecureScreen, v);
  }

  Future<void> setReminder({
    required bool enabled,
    int? hour,
    int? minute,
  }) async {
    final h = hour ?? state.reminderHour;
    final m = minute ?? state.reminderMinute;
    state = state.copyWith(
      reminderEnabled: enabled,
      reminderHour: h,
      reminderMinute: m,
    );
    final prefs = await _getPrefs();
    await prefs.setBool(_kReminderEnabled, enabled);
    await prefs.setInt(_kReminderHour, h);
    await prefs.setInt(_kReminderMinute, m);
  }

  Future<void> setBackupReminderEnabled(bool v) async {
    state = state.copyWith(backupReminderEnabled: v);
    final prefs = await _getPrefs();
    await prefs.setBool(_kBackupReminder, v);
  }

  Future<void> recordLastBackupNow() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    state = state.copyWith(lastBackupMillis: now);
    final prefs = await _getPrefs();
    await prefs.setInt(_kLastBackupMillis, now);
  }

  Future<void> setPinEnabled(bool v) async {
    state = state.copyWith(pinEnabled: v);
    final prefs = await _getPrefs();
    await prefs.setBool(_kPinEnabled, v);
  }

  Future<void> setBiometricEnabled(bool v) async {
    state = state.copyWith(biometricEnabled: v);
    final prefs = await _getPrefs();
    await prefs.setBool(_kBiometricEnabled, v);
  }

  Future<void> setAutoLockSeconds(int seconds) async {
    state = state.copyWith(autoLockSeconds: seconds);
    final prefs = await _getPrefs();
    await prefs.setInt(_kAutoLockSeconds, seconds);
  }

  Future<void> setLastWalletId(int walletId) async {
    state = state.copyWith(lastWalletId: walletId);
    final prefs = await _getPrefs();
    await prefs.setInt(_kLastWalletId, walletId);
  }

  Future<void> setOnboardingCompleted(bool v) async {
    state = state.copyWith(onboardingCompleted: v);
    final prefs = await _getPrefs();
    await prefs.setBool(_kOnboardingCompleted, v);
  }
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>((
  ref,
) {
  return SettingsNotifier();
});
