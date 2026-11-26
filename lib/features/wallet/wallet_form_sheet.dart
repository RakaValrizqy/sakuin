import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sakuin/core/constants/app_colors.dart';
import 'package:sakuin/core/constants/app_icons.dart';
import 'package:sakuin/core/constants/default_categories.dart';
import 'package:sakuin/core/db/app_database.dart';
import 'package:sakuin/core/services/settings_service.dart';
import 'package:sakuin/core/utils/amount_parser.dart';
import 'package:sakuin/core/utils/currency_formatter.dart';
import 'package:sakuin/core/utils/haptics.dart';
import 'package:sakuin/core/utils/thousands_input_formatter.dart';
import 'package:sakuin/features/wallet/wallet_providers.dart';

Future<int?> showWalletFormSheet(BuildContext context, {Wallet? existing}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => WalletFormSheet(existing: existing),
  );
}

class WalletFormSheet extends ConsumerStatefulWidget {
  const WalletFormSheet({super.key, this.existing});

  final Wallet? existing;

  @override
  ConsumerState<WalletFormSheet> createState() => _WalletFormSheetState();
}

class _WalletFormSheetState extends ConsumerState<WalletFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _balanceCtrl;

  late String _type;
  late String _icon;
  late int _color;
  late bool _includeInTotal;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final w = widget.existing;
    _nameCtrl = TextEditingController(text: w?.name ?? '');
    _balanceCtrl = TextEditingController(
      text: w != null && w.initialBalance != 0
          ? CurrencyFormatter.format(w.initialBalance, withSymbol: false)
          : '',
    );
    _type = w?.type ?? 'cash';
    _icon = w?.icon ?? 'cash';
    _color = w?.color ?? AppColors.pickerPalette.first;
    _includeInTotal = w?.includeInTotal ?? true;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _balanceCtrl.dispose();
    super.dispose();
  }

  void _applyPreset(WalletPreset preset) {
    final haptics = ref.read(settingsProvider).hapticsEnabled;
    AppHaptics.selection(haptics);
    setState(() {
      _nameCtrl.text = preset.name;
      _type = preset.type;
      _icon = preset.icon;
      _color = preset.color;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _saving) return;
    setState(() => _saving = true);

    final rawBalance = _balanceCtrl.text.trim();
    final parsedBalance = rawBalance.isEmpty
        ? 0
        : (AmountParser.parse(rawBalance) ?? 0);

    final id = await ref
        .read(walletActionsProvider)
        .saveWallet(
          id: widget.existing?.id,
          name: _nameCtrl.text.trim(),
          type: _type,
          icon: _icon,
          color: _color,
          initialBalance: parsedBalance,
          includeInTotal: _includeInTotal,
        );

    final haptics = ref.read(settingsProvider).hapticsEnabled;
    AppHaptics.light(haptics);

    if (mounted) Navigator.of(context).pop(id);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isEdit = widget.existing != null;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isEdit ? 'Edit Saku / Dompet' : 'Tambah Saku / Dompet',
                style: tt.headlineSmall,
              ),
              const SizedBox(height: 12),

              if (!isEdit) ...[
                Text(
                  'Pintasan cepat',
                  style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
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
                        onPressed: () => _applyPreset(preset),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
              ],

              TextFormField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nama dompet',
                  hintText: 'Contoh: Tunai, BCA, GoPay',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Nama wajib diisi' : null,
              ),
              const SizedBox(height: 14),

              Text('Jenis dompet', style: tt.labelMedium),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'cash', label: Text('Tunai')),
                  ButtonSegment(value: 'bank', label: Text('Bank')),
                  ButtonSegment(value: 'ewallet', label: Text('E-Wallet')),
                  ButtonSegment(value: 'other', label: Text('Lainnya')),
                ],
                selected: {_type},
                onSelectionChanged: (set) {
                  setState(() {
                    _type = set.first;
                    if (_type == 'cash') _icon = 'cash';
                    if (_type == 'bank') _icon = 'bank';
                    if (_type == 'ewallet') _icon = 'ewallet';
                    if (_type == 'other') _icon = 'wallet';
                  });
                },
              ),
              const SizedBox(height: 14),

              TextFormField(
                controller: _balanceCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [ThousandsSeparatorInputFormatter()],
                decoration: const InputDecoration(
                  labelText: 'Saldo awal (opsional)',
                  prefixText: 'Rp ',
                  hintText: '0',
                ),
              ),
              const SizedBox(height: 14),

              Text('Ikon', style: tt.labelMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final key in AppIcons.walletIconKeys)
                    InkWell(
                      onTap: () => setState(() => _icon = key),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: _icon == key
                              ? Color(_color).withValues(alpha: 0.2)
                              : cs.surfaceContainerHighest.withValues(
                                  alpha: 0.4,
                                ),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _icon == key
                                ? Color(_color)
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: Icon(
                          AppIcons.fromKey(key),
                          color: _icon == key
                              ? Color(_color)
                              : cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),

              Text('Warna', style: tt.labelMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final c in AppColors.pickerPalette)
                    InkWell(
                      onTap: () => setState(() => _color = c),
                      borderRadius: BorderRadius.circular(24),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Color(c),
                          shape: BoxShape.circle,
                          border: _color == c
                              ? Border.all(color: cs.onSurface, width: 3)
                              : null,
                        ),
                        child: _color == c
                            ? const Icon(
                                Icons.check_rounded,
                                color: Colors.white,
                                size: 20,
                              )
                            : null,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),

              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Ikut hitung total saldo'),
                subtitle: const Text(
                  'Nonaktifkan jika saku ini tidak ingin masuk total saldo di Beranda',
                ),
                value: _includeInTotal,
                onChanged: (v) => setState(() => _includeInTotal = v),
              ),
              const SizedBox(height: 16),

              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(isEdit ? 'Simpan Perubahan' : 'Buat Dompet'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
