import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

class AppVersionInfo {
  const AppVersionInfo({
    required this.versionName,
    required this.versionCode,
    required this.supportedAbis,
  });

  final String versionName;
  final int versionCode;
  final List<String> supportedAbis;
}

class ReleaseUpdateInfo {
  const ReleaseUpdateInfo({
    required this.tagName,
    required this.versionName,
    required this.title,
    required this.changelog,
    required this.apkDownloadUrl,
    required this.apkFileName,
    required this.apkSizeBytes,
    this.apiAssetUrl,
    this.publishedAt,
  });

  final String tagName;
  final String versionName;
  final String title;
  final String changelog;
  final String apkDownloadUrl;
  final String? apiAssetUrl;
  final String apkFileName;
  final int apkSizeBytes;
  final DateTime? publishedAt;

  String get formattedSize {
    if (apkSizeBytes <= 0) return '';
    final mb = apkSizeBytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }
}

class UpdateCheckResult {
  const UpdateCheckResult({
    required this.currentVersion,
    this.availableUpdate,
    this.errorMessage,
  });

  final String currentVersion;
  final ReleaseUpdateInfo? availableUpdate;
  final String? errorMessage;

  bool get hasUpdate => availableUpdate != null;
}

class UpdateService {
  UpdateService()
    : _storage = const FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
      );

  static const _channel = MethodChannel('id.rakavalrizqy.sakuin/updater');
  static const _kGitHubToken = 'sakuin_github_update_token';
  static const _latestReleaseUrl =
      'https://api.github.com/repos/RakaValrizqy/sakuin/releases/latest';

  final FlutterSecureStorage _storage;

  Future<String?> getGitHubToken() async {
    try {
      final token = await _storage.read(key: _kGitHubToken);
      if (token == null || token.trim().isEmpty) return null;
      return token.trim();
    } catch (_) {
      return null;
    }
  }

  Future<bool> hasGitHubToken() async {
    final token = await getGitHubToken();
    return token != null && token.isNotEmpty;
  }

  Future<void> saveGitHubToken(String? token) async {
    final cleaned = token?.trim() ?? '';
    if (cleaned.isEmpty) {
      await _storage.delete(key: _kGitHubToken);
    } else {
      await _storage.write(key: _kGitHubToken, value: cleaned);
    }
  }

  /// Sinkronkan jadwal WorkManager latar belakang (1x/24 jam, hanya saat ada internet &
  /// baterai tidak rendah, memakai ETag 304) untuk mengirim notifikasi saat ada rilis baru.
  Future<void> syncBackgroundUpdateWorker({required bool enabled}) async {
    try {
      final token = await getGitHubToken();
      await _channel.invokeMethod('configureBackgroundUpdateCheck', {
        'enabled': enabled,
        'githubToken': token,
      });
    } catch (_) {
      // Diabaikan di lingkungan non-Android / unit test.
    }
  }

  Future<AppVersionInfo> getAppInfo() async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>('getAppInfo');
      if (raw != null) {
        final abis =
            (raw['supportedAbis'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const ['arm64-v8a'];
        return AppVersionInfo(
          versionName: (raw['versionName'] as String?) ?? '1.6.0',
          versionCode: (raw['versionCode'] as int?) ?? 11,
          supportedAbis: abis,
        );
      }
    } catch (_) {
      // Fallback di lingkungan non-Android / unit test.
    }
    return const AppVersionInfo(
      versionName: '1.6.0',
      versionCode: 11,
      supportedAbis: ['arm64-v8a'],
    );
  }

  Future<bool> canRequestPackageInstalls() async {
    try {
      return await _channel.invokeMethod<bool>('canRequestPackageInstalls') ??
          true;
    } catch (_) {
      return true;
    }
  }

  Future<void> openInstallPermissionSettings() async {
    try {
      await _channel.invokeMethod('openInstallPermissionSettings');
    } catch (_) {}
  }

  Future<void> installApk(String filePath) async {
    await _channel.invokeMethod('installApk', {'filePath': filePath});
  }

  /// Bandingkan dua versi semver (mis. "1.1.0" vs "1.0.0", atau "v1.0.10" vs "v1.0.2").
  /// Mengembalikan >0 jika [remote] lebih baru daripada [local].
  static int compareVersions(String remote, String local) {
    List<int> parseParts(String raw) {
      var clean = raw.trim().toLowerCase();
      if (clean.startsWith('v')) clean = clean.substring(1);
      // Pisahkan metadata (+build) atau prerelease (-beta)
      clean = clean.split('+').first.split('-').first;
      return clean.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    }

    final r = parseParts(remote);
    final l = parseParts(local);
    final len = r.length > l.length ? r.length : l.length;
    for (var i = 0; i < len; i++) {
      final rv = i < r.length ? r[i] : 0;
      final lv = i < l.length ? l[i] : 0;
      if (rv != lv) return rv.compareTo(lv);
    }
    return 0;
  }

  /// Pilih asset APK paling cocok untuk arsitektur CPU perangkat (arm64-v8a / armeabi-v7a / x86_64).
  static Map<String, dynamic>? pickBestApkAsset(
    List<dynamic> assets,
    List<String> supportedAbis,
  ) {
    final apkAssets = assets
        .whereType<Map<String, dynamic>>()
        .where(
          (a) => (a['name'] as String? ?? '').toLowerCase().endsWith('.apk'),
        )
        .toList();
    if (apkAssets.isEmpty) return null;

    for (final abi in supportedAbis) {
      final lowerAbi = abi.toLowerCase();
      for (final asset in apkAssets) {
        final name = (asset['name'] as String? ?? '').toLowerCase();
        if (name.contains(lowerAbi)) return asset;
      }
    }

    // Fallback: arm64-v8a atau APK pertama
    for (final asset in apkAssets) {
      final name = (asset['name'] as String? ?? '').toLowerCase();
      if (name.contains('arm64-v8a')) return asset;
    }
    return apkAssets.first;
  }

  static ReleaseUpdateInfo? parseGitHubReleaseJson(
    Map<String, dynamic> json, {
    required String currentVersionName,
    required List<String> supportedAbis,
  }) {
    if (json['draft'] == true || json['prerelease'] == true) return null;
    final tagName = (json['tag_name'] as String?)?.trim() ?? '';
    if (tagName.isEmpty) return null;

    final remoteVersion = tagName.startsWith('v')
        ? tagName.substring(1)
        : tagName;
    if (compareVersions(remoteVersion, currentVersionName) <= 0) {
      return null;
    }

    final assets = (json['assets'] as List?) ?? const [];
    final bestAsset = pickBestApkAsset(assets, supportedAbis);
    if (bestAsset == null) return null;

    final downloadUrl = (bestAsset['browser_download_url'] as String?) ?? '';
    if (!isTrustedGitHubUrl(downloadUrl)) return null;

    final rawApiAssetUrl = (bestAsset['url'] as String?)?.trim();
    final apiAssetUrl =
        rawApiAssetUrl != null && isTrustedGitHubUrl(rawApiAssetUrl)
        ? rawApiAssetUrl
        : null;

    final body = (json['body'] as String?)?.trim() ?? '';
    return ReleaseUpdateInfo(
      tagName: tagName,
      versionName: remoteVersion,
      title: (json['name'] as String?)?.trim().isNotEmpty == true
          ? (json['name'] as String).trim()
          : 'Sakuin $tagName',
      changelog: body.isEmpty
          ? 'Peningkatan performa dan perbaikan bug.'
          : body,
      apkDownloadUrl: downloadUrl,
      apiAssetUrl: apiAssetUrl,
      apkFileName: (bestAsset['name'] as String?) ?? 'sakuin-update.apk',
      apkSizeBytes: (bestAsset['size'] as int?) ?? 0,
      publishedAt: json['published_at'] is String
          ? DateTime.tryParse(json['published_at'] as String)?.toLocal()
          : null,
    );
  }

  static bool isTrustedGitHubUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') return false;
    final host = uri.host.toLowerCase();
    return host == 'github.com' ||
        host.endsWith('.github.com') ||
        host.endsWith('.githubusercontent.com');
  }

  Future<UpdateCheckResult> checkForUpdate() async {
    final appInfo = await getAppInfo();
    final token = await getGitHubToken();
    final hasToken = token != null && token.isNotEmpty;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(Uri.parse(_latestReleaseUrl));
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.github+json',
      );
      request.headers.set(HttpHeaders.userAgentHeader, 'Sakuin-Android-App');
      if (hasToken) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      if (response.statusCode != 200) {
        final message = switch (response.statusCode) {
          404 =>
            hasToken
                ? 'Rilis tidak ditemukan atau Token GitHub belum memiliki izin baca Contents (HTTP 404).'
                : 'Repo GitHub masih Private atau rilis belum tersedia (HTTP 404). Ubah repo ke Public atau masukkan Token GitHub di Pengaturan → Pembaruan Aplikasi.',
          401 || 403 =>
            hasToken
                ? 'Token GitHub ditolak atau kedaluwarsa (HTTP ${response.statusCode}). Periksa ulang token di Pengaturan.'
                : 'Akses GitHub dibatasi sementara (HTTP ${response.statusCode}). Coba lagi nanti atau gunakan Token GitHub.',
          _ => 'Tidak dapat memeriksa pembaruan (HTTP ${response.statusCode})',
        };
        return UpdateCheckResult(
          currentVersion: appInfo.versionName,
          errorMessage: message,
        );
      }
      final bodyStr = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(bodyStr);
      if (decoded is! Map<String, dynamic>) {
        return UpdateCheckResult(
          currentVersion: appInfo.versionName,
          errorMessage: 'Respons GitHub tidak valid',
        );
      }
      final update = parseGitHubReleaseJson(
        decoded,
        currentVersionName: appInfo.versionName,
        supportedAbis: appInfo.supportedAbis,
      );
      return UpdateCheckResult(
        currentVersion: appInfo.versionName,
        availableUpdate: update,
      );
    } on SocketException {
      return UpdateCheckResult(
        currentVersion: appInfo.versionName,
        errorMessage: 'Tidak ada koneksi internet',
      );
    } catch (e) {
      return UpdateCheckResult(
        currentVersion: appInfo.versionName,
        errorMessage: 'Gagal memeriksa pembaruan: $e',
      );
    } finally {
      client.close(force: true);
    }
  }

  /// Unduh APK dari GitHub Release ke folder cache `updates/` dengan progress real-time.
  /// Untuk repo Private (dengan token), menggunakan endpoint Asset API + manual redirect
  /// agar header Authorization tidak diteruskan ke URL CDN signed.
  Future<File> downloadUpdateApk(
    ReleaseUpdateInfo info, {
    required void Function(int received, int total) onProgress,
  }) async {
    if (!isTrustedGitHubUrl(info.apkDownloadUrl)) {
      throw const FormatException(
        'URL unduhan tidak berasal dari GitHub resmi.',
      );
    }

    final token = await getGitHubToken();
    final usePrivateApi =
        token != null &&
        token.isNotEmpty &&
        info.apiAssetUrl != null &&
        isTrustedGitHubUrl(info.apiAssetUrl!);

    final cacheDir = await getTemporaryDirectory();
    final updateDir = Directory('${cacheDir.path}/updates');
    if (!await updateDir.exists()) {
      await updateDir.create(recursive: true);
    }

    final outFile = File('${updateDir.path}/${info.apkFileName}');
    final tempFile = File('${updateDir.path}/${info.apkFileName}.part');

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      HttpClientResponse response;
      if (usePrivateApi) {
        final apiReq = await client.getUrl(Uri.parse(info.apiAssetUrl!));
        apiReq.followRedirects = false;
        apiReq.headers.set(HttpHeaders.userAgentHeader, 'Sakuin-Android-App');
        apiReq.headers.set(
          HttpHeaders.acceptHeader,
          'application/octet-stream',
        );
        apiReq.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
        final apiRes = await apiReq.close();

        if (apiRes.isRedirect ||
            apiRes.statusCode == 301 ||
            apiRes.statusCode == 302 ||
            apiRes.statusCode == 303 ||
            apiRes.statusCode == 307 ||
            apiRes.statusCode == 308) {
          final location = apiRes.headers.value(HttpHeaders.locationHeader);
          await apiRes.drain<void>();
          if (location == null || !isTrustedGitHubUrl(location)) {
            throw const FormatException(
              'URL pengalihan unduhan tidak berasal dari GitHub resmi.',
            );
          }
          final cdnReq = await client.getUrl(Uri.parse(location));
          cdnReq.headers.set(HttpHeaders.userAgentHeader, 'Sakuin-Android-App');
          response = await cdnReq.close();
        } else {
          response = apiRes;
        }
      } else {
        final request = await client.getUrl(Uri.parse(info.apkDownloadUrl));
        request.headers.set(HttpHeaders.userAgentHeader, 'Sakuin-Android-App');
        response = await request.close();
      }

      if (response.statusCode != 200) {
        throw HttpException(
          'Gagal mengunduh APK (HTTP ${response.statusCode})',
        );
      }

      final total = response.contentLength > 0
          ? response.contentLength
          : info.apkSizeBytes;
      var received = 0;

      final sink = tempFile.openWrite();
      try {
        await for (final chunk in response) {
          sink.add(chunk);
          received += chunk.length;
          onProgress(received, total);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }

      if (await outFile.exists()) {
        await outFile.delete();
      }
      return await tempFile.rename(outFile.path);
    } catch (_) {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> cleanupOldApks() async {
    try {
      final cacheDir = await getTemporaryDirectory();
      final updateDir = Directory('${cacheDir.path}/updates');
      if (await updateDir.exists()) {
        await for (final entity in updateDir.list()) {
          if (entity is File &&
              (entity.path.endsWith('.apk') || entity.path.endsWith('.part'))) {
            await entity.delete();
          }
        }
      }
    } catch (_) {}
  }
}

final updateServiceProvider = Provider<UpdateService>((ref) {
  return UpdateService();
});

final appVersionInfoProvider = FutureProvider<AppVersionInfo>((ref) {
  return ref.watch(updateServiceProvider).getAppInfo();
});

final hasGitHubTokenProvider = FutureProvider<bool>((ref) {
  return ref.watch(updateServiceProvider).hasGitHubToken();
});
