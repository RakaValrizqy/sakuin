import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sakuin/core/constants/app_icons.dart';
import 'package:sakuin/core/constants/default_categories.dart';
import 'package:sakuin/core/services/settings_service.dart';
import 'package:sakuin/core/utils/amount_parser.dart';
import 'package:sakuin/core/utils/haptics.dart';
import 'package:sakuin/core/widgets/category_icon.dart';
import 'package:sakuin/features/wallet/wallet_providers.dart';

/// Onboarding pertama: "Buat dompet pertamamu" dengan chip pintasan nama umum
/// (ikon generik dan warna, bukan logo merek).
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _nameCtrl = TextEditingController();
  final _balanceCtrl = TextEditingController();
  String _type = 'cash';
  String _icon = 'cash';
  int _color = 0xFF15803D;
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _balanceCtrl.dispose();
    super.dispose();
  }

  void _selectPreset(WalletPreset preset) {
    AppHaptics.selection(ref.read(settingsProvider).hapticsEnabled);
    setState(() {
      _nameCtrl.text = preset.name;
      _type = preset.type;
      _icon = preset.icon;
      _color = preset.color;
    });
  }

  Future<void> _addWallet({bool finishAfter = true}) async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih pintasan atau ketik nama dompet')),
      );
      return;
    }
    setState(() => _saving = true);
    final balance = _balanceCtrl.text.trim().isEmpty
        ? 0
        : (AmountParser.parse(_balanceCtrl.text) ?? 0);
    final id = await ref
        .read(walletActionsProvider)
        .saveWallet(
          name: name,
          type: _type,
          icon: _icon,
          color: _color,
          initialBalance: balance,
          includeInTotal: true,
        );
    await ref.read(settingsProvider.notifier).setLastWalletId(id);
    AppHaptics.medium(ref.read(settingsProvider).hapticsEnabled);

    if (finishAfter) {
      await ref.read(settingsProvider.notifier).setOnboardingCompleted(true);
    } else if (mounted) {
      setState(() {
        _saving = false;
        _nameCtrl.clear();
        _balanceCtrl.clear();
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Dompet "$name" ditambahkan')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final wallets =
        ref.watch(walletsWithBalancesProvider).valueOrNull ?? const [];
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    Icons.account_balance_wallet_rounded,
                    color: cs.primary,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Selamat datang di Sakuin', style: tt.titleLarge),
                      Text(
                        'Offline, cepat, dan 100% privat di HP-mu',
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text('Buat dompet pertamamu', style: tt.headlineMedium),
            const SizedBox(height: 6),
            Text(
              'Ketuk pintasan di bawah atau tulis nama dompetmu sendiri.',
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in DefaultSeeds.walletPresets)
                  ActionChip(
                    avatar: Icon(
                      AppIcons.fromKey(preset.icon),
                      size: 18,
                      color: Color(preset.color),
                    ),
                    label: Text(preset.name),
                    onPressed: () => _selectPreset(preset),
                  ),
              ],
            ),
            const SizedBox(height: 18),

            TextField(
              controller: _nameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Nama dompet',
                hintText: 'Contoh: Tunai, BCA, GoPay',
                prefixIcon: Padding(
                  padding: const EdgeInsets.all(8),
                  child: CategoryIconBadge(
                    iconKey: _icon,
                    colorValue: _color,
                    size: 32,
                    iconSize: 18,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _balanceCtrl,
              decoration: const InputDecoration(
                labelText: 'Saldo awal (opsional)',
                prefixText: 'Rp ',
                hintText: '0 (mendukung 500k, 1,5jt)',
              ),
            ),
            const SizedBox(height: 18),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving
                        ? null
                        : () => _addWallet(finishAfter: false),
                    child: const Text('Tambah Lagi'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _saving
                        ? null
                        : () {
                            if (_nameCtrl.text.trim().isNotEmpty) {
                              _addWallet(finishAfter: true);
                            } else if (wallets.isNotEmpty) {
                              ref
                                  .read(settingsProvider.notifier)
                                  .setOnboardingCompleted(true);
                            } else {
                              _addWallet(finishAfter: true);
                            }
                          },
                    child: Text(
                      wallets.isNotEmpty && _nameCtrl.text.trim().isEmpty
                          ? 'Mulai Pakai Sakuin'
                          : 'Simpan & Mulai',
                    ),
                  ),
                ),
              ],
            ),

            if (wallets.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text(
                'Dompet ditambahkan (${wallets.length})',
                style: tt.titleMedium,
              ),
              const SizedBox(height: 8),
              for (final wb in wallets)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    child: ListTile(
                      leading: CategoryIconBadge(
                        iconKey: wb.wallet.icon,
                        colorValue: wb.wallet.color,
                      ),
                      title: Text(wb.wallet.name),
                      subtitle: Text(walletTypeLabel(wb.wallet.type)),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
