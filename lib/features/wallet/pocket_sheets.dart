import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sakuin/core/constants/app_colors.dart';
import 'package:sakuin/core/constants/app_icons.dart';
import 'package:sakuin/core/db/app_database.dart';
import 'package:sakuin/core/services/settings_service.dart';
import 'package:sakuin/core/utils/amount_parser.dart';
import 'package:sakuin/core/utils/currency_formatter.dart';
import 'package:sakuin/core/utils/haptics.dart';
import 'package:sakuin/features/wallet/wallet_providers.dart';

class _PocketPreset {
  const _PocketPreset(this.name, this.icon, this.color);
  final String name;
  final String icon;
  final int color;
}

const _pocketPresets = [
  _PocketPreset('Uang Harian', 'food', 0xFFEA580C),
  _PocketPreset('Tabungan', 'savings', 0xFF15803D),
  _PocketPreset('Dana Darurat', 'safe', 0xFF0F766E),
  _PocketPreset('Tagihan', 'bills', 0xFFD97706),
  _PocketPreset('Belanja', 'shopping', 0xFFDB2777),
  _PocketPreset('Transport', 'transport', 0xFF0284C7),
  _PocketPreset('Liburan', 'travel', 0xFF7C3AED),
  _PocketPreset('Investasi', 'investment', 0xFF1D4ED8),
];

Future<int?> showPocketFormSheet(
  BuildContext context, {
  required int walletId,
  required int unallocatedBalance,
  PocketWithBalance? existing,
}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _PocketFormSheet(
      walletId: walletId,
      unallocatedBalance: unallocatedBalance,
      existing: existing,
    ),
  );
}

class _PocketFormSheet extends ConsumerStatefulWidget {
  const _PocketFormSheet({
    required this.walletId,
    required this.unallocatedBalance,
    this.existing,
  });

  final int walletId;
  final int unallocatedBalance;
  final PocketWithBalance? existing;

  @override
  ConsumerState<_PocketFormSheet> createState() => _PocketFormSheetState();
}

class _PocketFormSheetState extends ConsumerState<_PocketFormSheet> {
  final _nameCtrl = TextEditingController();
  final _allocCtrl = TextEditingController();
  final _targetCtrl = TextEditingController();

  late String _icon;
  late int _color;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl.text = e?.pocket.name ?? '';
    _icon = e?.pocket.icon ?? 'savings';
    _color = e?.pocket.color ?? AppColors.pickerPalette.first;
    if (e != null) {
      _allocCtrl.text = CurrencyFormatter.format(e.balance, withSymbol: false);
      if (e.pocket.targetAmount != null && e.pocket.targetAmount! > 0) {
        _targetCtrl.text = CurrencyFormatter.format(
          e.pocket.targetAmount!,
          withSymbol: false,
        );
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _allocCtrl.dispose();
    _targetCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty || _saving) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Masukkan nama pos / budget')),
      );
      return;
    }

    final allocRaw = _allocCtrl.text.trim();
    final allocVal = allocRaw.isEmpty ? 0 : (AmountParser.parse(allocRaw) ?? 0);
    final targetRaw = _targetCtrl.text.trim();
    final targetVal = targetRaw.isEmpty ? null : AmountParser.parse(targetRaw);

    setState(() => _saving = true);
    final id = await ref
        .read(walletActionsProvider)
        .savePocket(
          id: widget.existing?.pocket.id,
          walletId: widget.walletId,
          name: name,
          icon: _icon,
          color: _color,
          targetAmount: targetVal != null && targetVal > 0 ? targetVal : null,
          manualAllocationBalance: allocVal,
        );
    AppHaptics.medium(ref.read(settingsProvider).hapticsEnabled);
    if (mounted) Navigator.of(context).pop(id);
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final isEdit = widget.existing != null;
    final maxRecommended =
        widget.unallocatedBalance + (widget.existing?.balance ?? 0);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isEdit ? 'Edit Pos Budget' : 'Buat Pos Budget di Saku',
              style: tt.headlineSmall,
            ),
            const SizedBox(height: 6),
            Text(
              'Bagi saldo saku ini ke pos terpisah tanpa mengubah total saldo saku.',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            if (!isEdit) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in _pocketPresets)
                    ActionChip(
                      avatar: Icon(
                        AppIcons.fromKey(p.icon),
                        size: 16,
                        color: Color(p.color),
                      ),
                      label: Text(p.name),
                      onPressed: () {
                        AppHaptics.selection(
                          ref.read(settingsProvider).hapticsEnabled,
                        );
                        setState(() {
                          _nameCtrl.text = p.name;
                          _icon = p.icon;
                          _color = p.color;
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: 14),
            ],
            TextField(
              controller: _nameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nama pos budget',
                hintText: 'Contoh: Uang Harian, Tabungan, Dana Darurat',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _allocCtrl,
              decoration: InputDecoration(
                labelText: isEdit
                    ? 'Saldo alokasi saat ini'
                    : 'Alokasi saldo awal (opsional)',
                prefixText: 'Rp ',
                hintText: '0 (mendukung 200k, 300k, 1,5jt)',
                helperText:
                    'Saldo bebas tersedia di saku: ${CurrencyFormatter.format(widget.unallocatedBalance)}',
              ),
            ),
            if (maxRecommended > 0) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ActionChip(
                    label: Text(
                      'Pakai semua (${CurrencyFormatter.formatCompact(maxRecommended)})',
                    ),
                    onPressed: () {
                      _allocCtrl.text = CurrencyFormatter.format(
                        maxRecommended,
                        withSymbol: false,
                      );
                    },
                  ),
                  if (maxRecommended >= 2)
                    ActionChip(
                      label: Text(
                        '50% (${CurrencyFormatter.formatCompact(maxRecommended ~/ 2)})',
                      ),
                      onPressed: () {
                        _allocCtrl.text = CurrencyFormatter.format(
                          maxRecommended ~/ 2,
                          withSymbol: false,
                        );
                      },
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _targetCtrl,
              decoration: const InputDecoration(
                labelText: 'Target pos (opsional)',
                prefixText: 'Rp ',
                hintText: 'Contoh: 5jt untuk target tabungan',
              ),
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
                      width: 36,
                      height: 36,
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
                              size: 18,
                            )
                          : null,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Text('Ikon', style: tt.labelMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final key in const [
                  'savings',
                  'food',
                  'safe',
                  'bills',
                  'shopping',
                  'transport',
                  'travel',
                  'investment',
                  'home',
                  'health',
                  'education',
                  'gift',
                  'entertainment',
                  'wallet',
                ])
                  InkWell(
                    onTap: () => setState(() => _icon = key),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: _icon == key
                            ? Color(_color).withValues(alpha: 0.2)
                            : cs.surfaceContainerHighest.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(12),
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
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(isEdit ? 'Simpan Perubahan' : 'Buat Pos Budget'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sheet untuk alokasi manual (Saldo Bebas <-> Pos) atau transfer antar Pos di dalam saku yang sama.
Future<bool?> showPocketAllocateSheet(
  BuildContext context, {
  required int walletId,
  required String walletName,
  required int unallocatedBalance,
  required List<PocketWithBalance> pockets,
  int? initialFromPocketId,
  int? initialToPocketId,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _PocketAllocateSheet(
      walletId: walletId,
      walletName: walletName,
      unallocatedBalance: unallocatedBalance,
      pockets: pockets,
      initialFromPocketId: initialFromPocketId,
      initialToPocketId: initialToPocketId,
    ),
  );
}

class _PocketAllocateSheet extends ConsumerStatefulWidget {
  const _PocketAllocateSheet({
    required this.walletId,
    required this.walletName,
    required this.unallocatedBalance,
    required this.pockets,
    this.initialFromPocketId,
    this.initialToPocketId,
  });

  final int walletId;
  final String walletName;
  final int unallocatedBalance;
  final List<PocketWithBalance> pockets;
  final int? initialFromPocketId;
  final int? initialToPocketId;

  @override
  ConsumerState<_PocketAllocateSheet> createState() =>
      _PocketAllocateSheetState();
}

class _PocketAllocateSheetState extends ConsumerState<_PocketAllocateSheet> {
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  // null = Saldo Bebas (belum dialokasikan)
  int? _fromPocketId;
  int? _toPocketId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _fromPocketId = widget.initialFromPocketId;
    if (widget.initialToPocketId != null) {
      _toPocketId = widget.initialToPocketId;
    } else if (_fromPocketId == null && widget.pockets.isNotEmpty) {
      _toPocketId = widget.pockets.first.pocket.id;
    } else {
      // Pilih pos lain atau Saldo Bebas
      final other = widget.pockets
          .where((p) => p.pocket.id != _fromPocketId)
          .firstOrNull;
      _toPocketId = other?.pocket.id;
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  int get _fromBalance {
    if (_fromPocketId == null) return widget.unallocatedBalance;
    return widget.pockets
            .where((p) => p.pocket.id == _fromPocketId)
            .firstOrNull
            ?.balance ??
        0;
  }

  Future<void> _save() async {
    final amount = AmountParser.parse(_amountCtrl.text) ?? 0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Masukkan nominal lebih dari Rp 0')),
      );
      return;
    }
    if (_fromPocketId == _toPocketId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Asal dan tujuan budget harus berbeda')),
      );
      return;
    }
    setState(() => _saving = true);
    await ref
        .read(walletActionsProvider)
        .allocateOrMovePocket(
          walletId: widget.walletId,
          fromPocketId: _fromPocketId,
          toPocketId: _toPocketId,
          amount: amount,
          note: _noteCtrl.text.trim(),
        );
    AppHaptics.medium(ref.read(settingsProvider).hapticsEnabled);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    List<DropdownMenuItem<int?>> buildOptions() => [
      DropdownMenuItem<int?>(
        value: null,
        child: Text(
          'Saldo Bebas (${CurrencyFormatter.format(widget.unallocatedBalance)})',
        ),
      ),
      for (final p in widget.pockets)
        DropdownMenuItem<int?>(
          value: p.pocket.id,
          child: Text(
            '${p.pocket.name} (${CurrencyFormatter.format(p.balance)})',
          ),
        ),
    ];

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Alokasi / Pindah Budget', style: tt.headlineSmall),
            const SizedBox(height: 4),
            Text(
              'Di dalam saku ${widget.walletName} (total saldo saku tidak berubah).',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int?>(
              initialValue: _fromPocketId,
              decoration: const InputDecoration(labelText: 'Dari'),
              items: buildOptions(),
              onChanged: (v) => setState(() => _fromPocketId = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int?>(
              initialValue: _toPocketId,
              decoration: const InputDecoration(labelText: 'Ke'),
              items: buildOptions(),
              onChanged: (v) => setState(() => _toPocketId = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountCtrl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Nominal',
                prefixText: 'Rp ',
                hintText: 'Contoh: 200k atau 300k',
                helperText:
                    'Tersedia di sumber: ${CurrencyFormatter.format(_fromBalance)}',
              ),
            ),
            if (_fromBalance > 0) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ActionChip(
                    label: Text(
                      'Semua (${CurrencyFormatter.formatCompact(_fromBalance)})',
                    ),
                    onPressed: () {
                      _amountCtrl.text = CurrencyFormatter.format(
                        _fromBalance,
                        withSymbol: false,
                      );
                    },
                  ),
                  if (_fromBalance >= 2)
                    ActionChip(
                      label: const Text('50%'),
                      onPressed: () {
                        _amountCtrl.text = CurrencyFormatter.format(
                          _fromBalance ~/ 2,
                          withSymbol: false,
                        );
                      },
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _noteCtrl,
              decoration: const InputDecoration(
                labelText: 'Catatan (opsional)',
                hintText: 'Contoh: Sisihkan untuk tabungan bulanan',
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.swap_horiz_rounded),
                label: const Text('Simpan Alokasi'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
