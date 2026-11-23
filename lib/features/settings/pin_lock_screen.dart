import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sakuin/core/services/security_service.dart';
import 'package:sakuin/core/services/settings_service.dart';
import 'package:sakuin/core/utils/haptics.dart';

enum PinScreenMode { unlock, setup }

class PinLockScreen extends ConsumerStatefulWidget {
  const PinLockScreen({super.key, required this.mode, this.onUnlocked});

  final PinScreenMode mode;
  final VoidCallback? onUnlocked;

  @override
  ConsumerState<PinLockScreen> createState() => _PinLockScreenState();
}

class _PinLockScreenState extends ConsumerState<PinLockScreen> {
  String _entered = '';
  String? _firstPin; // dipakai saat mode setup (konfirmasi)
  String? _error;
  bool _verifying = false;

  @override
  void initState() {
    super.initState();
    if (widget.mode == PinScreenMode.unlock) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometric());
    }
  }

  Future<void> _tryBiometric() async {
    final settings = ref.read(settingsProvider);
    if (!settings.biometricEnabled) return;
    final security = ref.read(securityServiceProvider);
    final ok = await security.authenticateBiometric();
    if (ok && mounted) {
      widget.onUnlocked?.call();
    }
  }

  void _appendDigit(String d) {
    if (_entered.length >= 6 || _verifying) return;
    AppHaptics.selection(ref.read(settingsProvider).hapticsEnabled);
    setState(() {
      _error = null;
      _entered += d;
    });

    // Untuk mode unlock, verifikasi otomatis saat 4/5/6 digit jika cocok
    if (widget.mode == PinScreenMode.unlock && _entered.length >= 4) {
      _checkUnlock(silentOnFail: _entered.length < 6);
    }
  }

  void _backspace() {
    if (_entered.isEmpty || _verifying) return;
    setState(() {
      _error = null;
      _entered = _entered.substring(0, _entered.length - 1);
    });
  }

  Future<void> _checkUnlock({required bool silentOnFail}) async {
    setState(() => _verifying = true);
    final ok = await ref.read(securityServiceProvider).verifyPin(_entered);
    if (!mounted) return;
    if (ok) {
      AppHaptics.light(ref.read(settingsProvider).hapticsEnabled);
      setState(() => _verifying = false);
      widget.onUnlocked?.call();
      return;
    }
    setState(() {
      _verifying = false;
      if (!silentOnFail) {
        _error = 'PIN salah, coba lagi';
        _entered = '';
      }
    });
  }

  Future<void> _submitSetupOrUnlock() async {
    if (_entered.length < 4) {
      setState(() => _error = 'PIN minimal 4 digit');
      return;
    }

    if (widget.mode == PinScreenMode.unlock) {
      await _checkUnlock(silentOnFail: false);
      return;
    }

    // Mode setup: 2 langkah (buat -> konfirmasi)
    if (_firstPin == null) {
      setState(() {
        _firstPin = _entered;
        _entered = '';
        _error = null;
      });
    } else {
      if (_entered != _firstPin) {
        setState(() {
          _error = 'Konfirmasi PIN tidak cocok. Ulangi dari awal.';
          _firstPin = null;
          _entered = '';
        });
        return;
      }
      await ref.read(securityServiceProvider).setPin(_entered);
      await ref.read(settingsProvider.notifier).setPinEnabled(true);
      AppHaptics.medium(ref.read(settingsProvider).hapticsEnabled);
      if (mounted) Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final biometricEnabled = ref.watch(
      settingsProvider.select((s) => s.biometricEnabled),
    );

    final title = widget.mode == PinScreenMode.unlock
        ? 'Masukkan PIN Sakuin'
        : (_firstPin == null ? 'Buat PIN Baru (4–6 digit)' : 'Konfirmasi PIN');

    Widget digitButton(String label, {VoidCallback? onTap, IconData? icon}) {
      return SizedBox(
        width: 76,
        height: 68,
        child: Material(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Center(
              child: icon != null
                  ? Icon(icon, size: 26)
                  : Text(
                      label,
                      style: tt.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: widget.mode == PinScreenMode.setup
          ? AppBar(title: const Text('Atur Kunci PIN'))
          : null,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            Icon(Icons.lock_rounded, size: 48, color: cs.primary),
            const SizedBox(height: 16),
            Text(title, style: tt.headlineSmall),
            const SizedBox(height: 20),

            // Indikator titik PIN (maks 6)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < 6; i++)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < _entered.length
                          ? cs.primary
                          : cs.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 24,
              child: _error != null
                  ? Text(
                      _error!,
                      style: tt.bodyMedium?.copyWith(color: cs.error),
                    )
                  : null,
            ),
            const Spacer(),

            // Keypad angka
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      digitButton('1', onTap: () => _appendDigit('1')),
                      digitButton('2', onTap: () => _appendDigit('2')),
                      digitButton('3', onTap: () => _appendDigit('3')),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      digitButton('4', onTap: () => _appendDigit('4')),
                      digitButton('5', onTap: () => _appendDigit('5')),
                      digitButton('6', onTap: () => _appendDigit('6')),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      digitButton('7', onTap: () => _appendDigit('7')),
                      digitButton('8', onTap: () => _appendDigit('8')),
                      digitButton('9', onTap: () => _appendDigit('9')),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      if (widget.mode == PinScreenMode.unlock &&
                          biometricEnabled)
                        digitButton(
                          '',
                          icon: Icons.fingerprint_rounded,
                          onTap: _tryBiometric,
                        )
                      else
                        const SizedBox(width: 76, height: 68),
                      digitButton('0', onTap: () => _appendDigit('0')),
                      digitButton(
                        '',
                        icon: Icons.backspace_outlined,
                        onTap: _backspace,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _entered.length >= 4 && !_verifying
                      ? _submitSetupOrUnlock
                      : null,
                  child: Text(
                    widget.mode == PinScreenMode.unlock
                        ? 'Buka Kunci'
                        : (_firstPin == null ? 'Lanjut' : 'Simpan PIN'),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
