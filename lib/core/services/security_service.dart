import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:sakuin/core/utils/crypto_utils.dart';

class SecurityService {
  SecurityService()
    : _storage = const FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
      ),
      _localAuth = LocalAuthentication();

  static const _channel = MethodChannel('id.rakavalrizqy.sakuin/security');
  static const _kPinHash = 'sakuin_pin_hash';
  static const _kPinSalt = 'sakuin_pin_salt';

  final FlutterSecureStorage _storage;
  final LocalAuthentication _localAuth;

  Future<bool> hasPin() async {
    final hash = await _storage.read(key: _kPinHash);
    return hash != null && hash.isNotEmpty;
  }

  Future<void> setPin(String pin) async {
    final salt = CryptoUtils.generateSalt();
    final hash = CryptoUtils.hashPin(pin, salt);
    await _storage.write(key: _kPinSalt, value: salt);
    await _storage.write(key: _kPinHash, value: hash);
  }

  Future<bool> verifyPin(String pin) async {
    final salt = await _storage.read(key: _kPinSalt);
    final hash = await _storage.read(key: _kPinHash);
    if (salt == null || hash == null) return false;
    return CryptoUtils.verifyPin(pin, salt, hash);
  }

  Future<void> clearPin() async {
    await _storage.delete(key: _kPinHash);
    await _storage.delete(key: _kPinSalt);
  }

  Future<bool> canCheckBiometrics() async {
    try {
      final supported = await _localAuth.isDeviceSupported();
      final canCheck = await _localAuth.canCheckBiometrics;
      return supported && canCheck;
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticateBiometric() async {
    try {
      return await _localAuth.authenticate(
        localizedReason: 'Buka kunci Sakuin dengan biometrik',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  Future<void> setSecureScreenFlag(bool enabled) async {
    try {
      await _channel.invokeMethod('setSecureFlag', {'enabled': enabled});
    } catch (_) {
      // Diabaikan pada platform non-Android (mis. widget test).
    }
  }
}

final securityServiceProvider = Provider<SecurityService>((ref) {
  return SecurityService();
});
