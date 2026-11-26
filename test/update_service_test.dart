import 'package:flutter_test/flutter_test.dart';
import 'package:sakuin/core/services/update_service.dart';

void main() {
  group('UpdateService version comparison', () {
    test('compares semver versions accurately', () {
      expect(UpdateService.compareVersions('1.1.0', '1.0.0'), greaterThan(0));
      expect(UpdateService.compareVersions('v1.0.10', '1.0.2'), greaterThan(0));
      expect(UpdateService.compareVersions('2.0.0', '1.9.9'), greaterThan(0));
      expect(UpdateService.compareVersions('1.1.0', '1.1.0'), 0);
      expect(UpdateService.compareVersions('1.0.0', '1.1.0'), lessThan(0));
      expect(
        UpdateService.compareVersions('v1.2.0-build.5', '1.1.0+2'),
        greaterThan(0),
      );
    });
  });

  group('UpdateService ABI & Release parsing', () {
    final releaseJson = {
      'tag_name': 'v1.1.0',
      'name': 'Sakuin v1.1.0',
      'draft': false,
      'prerelease': false,
      'published_at': '2026-11-26T06:00:00Z',
      'body': '### Apa yang Baru\n- Pos Budget di dalam Saku\n- Auto update',
      'assets': [
        {
          'name': 'app-armeabi-v7a-release.apk',
          'size': 15000000,
          'browser_download_url': 'https://github.com/RakaValrizqy/sakuin/releases/download/v1.1.0/app-armeabi-v7a-release.apk',
        },
        {
          'name': 'app-arm64-v8a-release.apk',
          'size': 16500000,
          'url': 'https://api.github.com/repos/RakaValrizqy/sakuin/releases/assets/987654',
          'browser_download_url': 'https://github.com/RakaValrizqy/sakuin/releases/download/v1.1.0/app-arm64-v8a-release.apk',
        },
      ],
    };

    test('picks matching arm64-v8a APK and parses release notes', () {
      final update = UpdateService.parseGitHubReleaseJson(
        releaseJson,
        currentVersionName: '1.0.0',
        supportedAbis: const ['arm64-v8a', 'armeabi-v7a'],
      );
      expect(update, isNotNull);
      expect(update!.versionName, '1.1.0');
      expect(update.apkFileName, 'app-arm64-v8a-release.apk');
      expect(
        update.apiAssetUrl,
        'https://api.github.com/repos/RakaValrizqy/sakuin/releases/assets/987654',
      );
      expect(update.changelog, contains('Pos Budget'));
    });

    test('returns null when already on latest version', () {
      final update = UpdateService.parseGitHubReleaseJson(
        releaseJson,
        currentVersionName: '1.1.0',
        supportedAbis: const ['arm64-v8a'],
      );
      expect(update, isNull);
    });

    test('rejects non-GitHub or insecure HTTP URLs', () {
      expect(
        UpdateService.isTrustedGitHubUrl(
          'https://github.com/RakaValrizqy/sakuin/releases/download/v1.1.0/app.apk',
        ),
        isTrue,
      );
      expect(
        UpdateService.isTrustedGitHubUrl(
          'https://api.github.com/repos/RakaValrizqy/sakuin/releases/assets/123',
        ),
        isTrue,
      );
      expect(
        UpdateService.isTrustedGitHubUrl(
          'https://objects.githubusercontent.com/github-production-release-asset/app.apk',
        ),
        isTrue,
      );
      expect(
        UpdateService.isTrustedGitHubUrl(
          'http://github.com/RakaValrizqy/sakuin/releases/download/v1.1.0/app.apk',
        ),
        isFalse,
      );
      expect(
        UpdateService.isTrustedGitHubUrl('https://evil.example.com/app.apk'),
        isFalse,
      );
    });
  });
}
