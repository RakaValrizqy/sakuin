import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sakuin/core/services/settings_service.dart';
import 'package:sakuin/core/services/update_service.dart';
import 'package:sakuin/core/utils/date_utils.dart';

Future<void> showUpdateAvailableSheet(
  BuildContext context, {
  required String currentVersion,
  required ReleaseUpdateInfo update,
  bool allowSkip = true,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _UpdateAvailableSheet(
      currentVersion: currentVersion,
      update: update,
      allowSkip: allowSkip,
    ),
  );
}

class _UpdateAvailableSheet extends ConsumerStatefulWidget {
  const _UpdateAvailableSheet({
    required this.currentVersion,
    required this.update,
    required this.allowSkip,
  });

  final String currentVersion;
  final ReleaseUpdateInfo update;
  final bool allowSkip;

  @override
  ConsumerState<_UpdateAvailableSheet> createState() =>
      _UpdateAvailableSheetState();
}

class _UpdateAvailableSheetState extends ConsumerState<_UpdateAvailableSheet> {
  bool _downloading = false;
  double _progress = 0;
  int _receivedBytes = 0;
  int _totalBytes = 0;
  File? _downloadedFile;
  bool _waitingInstallPermission = false;
  String? _error;

  Future<void> _startDownloadAndInstall() async {
    if (_downloading) return;
    setState(() {
      _downloading = true;
      _error = null;
      _progress = 0;
      _receivedBytes = 0;
      _totalBytes = widget.update.apkSizeBytes;
    });

    final updater = ref.read(updateServiceProvider);
    try {
      final file = await updater.downloadUpdateApk(
        widget.update,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _receivedBytes = received;
            _totalBytes = total;
            _progress = total > 0 ? (received / total).clamp(0.0, 1.0) : 0;
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _downloadedFile = file;
        _downloading = false;
        _progress = 1.0;
      });
      await _triggerInstall(file);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _error = 'Gagal mengunduh pembaruan: $e';
      });
    }
  }

  Future<void> _triggerInstall(File file) async {
    final updater = ref.read(updateServiceProvider);
    final canInstall = await updater.canRequestPackageInstalls();
    if (!canInstall) {
      if (!mounted) return;
      setState(() => _waitingInstallPermission = true);
      await updater.openInstallPermissionSettings();
      return;
    }
    try {
      await updater.installApk(file.path);
      if (mounted) {
        setState(() => _waitingInstallPermission = false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Gagal membuka pemasang APK: $e');
    }
  }

  String _formatMb(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final u = widget.update;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.system_update_rounded,
                      color: cs.primary,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Pembaruan Tersedia', style: tt.titleLarge),
                        Text(
                          'v${widget.currentVersion} → v${u.versionName}${u.formattedSize.isNotEmpty ? ' • ${u.formattedSize}' : ''}',
                          style: tt.bodySmall?.copyWith(
                            color: cs.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (u.publishedAt != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Dirilis ${AppDateUtils.formatDayDate(u.publishedAt!)} • Update tanpa uninstall (data aman)',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: 14),

              Text('Apa yang Baru & Berubah', style: tt.titleSmall),
              const SizedBox(height: 8),
              Flexible(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: SingleChildScrollView(
                    child: _ChangelogView(markdown: u.changelog),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              if (_downloading) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: _progress > 0 ? _progress : null,
                    minHeight: 8,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _totalBytes > 0
                      ? 'Mengunduh ${(_progress * 100).round()}% (${_formatMb(_receivedBytes)} / ${_formatMb(_totalBytes)})'
                      : 'Mengunduh pembaruan...',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 10),
              ],

              if (_waitingInstallPermission) ...[
                Card(
                  color: cs.secondaryContainer.withValues(alpha: 0.5),
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'Aktifkan izin "Izinkan dari sumber ini" untuk Sakuin di Pengaturan Android, lalu ketuk Pasang Sekarang di bawah.',
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],

              if (_error != null) ...[
                Text(_error!, style: tt.bodySmall?.copyWith(color: cs.error)),
                const SizedBox(height: 10),
              ],

              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _downloading
                      ? null
                      : () {
                          if (_downloadedFile != null) {
                            _triggerInstall(_downloadedFile!);
                          } else {
                            _startDownloadAndInstall();
                          }
                        },
                  icon: Icon(
                    _downloadedFile != null
                        ? Icons.install_mobile_rounded
                        : Icons.download_rounded,
                  ),
                  label: Text(
                    _downloading
                        ? 'Mengunduh...'
                        : (_downloadedFile != null
                              ? 'Pasang Sekarang'
                              : 'Perbarui Sekarang'),
                  ),
                ),
              ),
              if (!_downloading) ...[
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (widget.allowSkip)
                      TextButton(
                        onPressed: () async {
                          await ref
                              .read(settingsProvider.notifier)
                              .setSkippedUpdateTag(u.tagName);
                          if (context.mounted) Navigator.of(context).pop();
                        },
                        child: const Text('Lewati versi ini'),
                      )
                    else
                      const SizedBox.shrink(),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Nanti saja'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Renderer ringan untuk rangkuman markdown release notes (tanpa library eksternal).
class _ChangelogView extends StatelessWidget {
  const _ChangelogView({required this.markdown});

  final String markdown;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final lines = markdown
        .split('\n')
        .map((l) => l.trimRight())
        .where((l) => l.trim().isNotEmpty)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [for (final raw in lines) _buildLine(raw.trim(), tt, cs)],
    );
  }

  Widget _buildLine(String line, TextTheme tt, ColorScheme cs) {
    if (line.startsWith('### ') || line.startsWith('## ')) {
      final clean = line.replaceFirst(RegExp(r'^#+\s*'), '');
      return Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Text(clean, style: tt.titleSmall?.copyWith(color: cs.primary)),
      );
    }
    if (line.startsWith('- ') || line.startsWith('* ')) {
      final clean = line.substring(2).replaceAll('**', '').replaceAll('`', '');
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('•  '),
            Expanded(child: Text(clean, style: tt.bodyMedium)),
          ],
        ),
      );
    }
    final clean = line.replaceAll('**', '').replaceAll('`', '');
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(clean, style: tt.bodyMedium),
    );
  }
}
