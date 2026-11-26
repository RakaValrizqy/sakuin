import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sakuin/core/constants/app_colors.dart';
import 'package:sakuin/core/constants/app_icons.dart';
import 'package:sakuin/core/db/app_database.dart';
import 'package:sakuin/core/services/settings_service.dart';
import 'package:sakuin/core/utils/amount_parser.dart';
import 'package:sakuin/core/utils/currency_formatter.dart';
import 'package:sakuin/core/utils/haptics.dart';
import 'package:sakuin/core/utils/thousands_input_formatter.dart';
import 'package:sakuin/core/widgets/category_icon.dart';
import 'package:sakuin/features/wallet/wallet_providers.dart';

class PocketPreset {
  const PocketPreset(this.name, this.icon, this.color);
  final String name;
  final String icon;
  final int color;
}

const pocketPresets = [
  PocketPreset('Uang Harian', 'food', 0xFFEA580C),
  PocketPreset('Tabungan', 'savings', 0xFF15803D),
  PocketPreset('Dana Darurat', 'safe', 0xFF0F766E),
  PocketPreset('Tagihan', 'bills', 0xFFD97706),
  PocketPreset('Belanja', 'shopping', 0xFFDB2777),
  PocketPreset('Transport', 'transport', 0xFF0284C7),
  PocketPreset('Liburan', 'travel', 0xFF7C3AED),
  PocketPreset('Investasi', 'investment', 0xFF1D4ED8),
];

Future<int?> showPocketFormSheet(
  BuildContext context, {
  required int walletId,
  required int unallocatedBalance,
  PocketWithBalance? existing,
  PocketPreset? initialPreset,
}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _PocketFormSheet(
      walletId: walletId,
      unallocatedBalance: unallocatedBalance,
      existing: existing,
      initialPreset: initialPreset,
    ),
  );
}

class _PocketFormSheet extends ConsumerStatefulWidget {
  const _PocketFormSheet({
    required this.walletId,
    required this.unallocatedBalance,
    this.existing,
    this.initialPreset,
  });

  final int walletId;
  final int unallocatedBalance;
  final PocketWithBalance? existing;
  final PocketPreset? initialPreset;

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
    final preset = widget.initialPreset;
    _nameCtrl.text = e?.pocket.name ?? preset?.name ?? '';
    _icon = e?.pocket.icon ?? preset?.icon ?? 'savings';
    _color = e?.pocket.color ?? preset?.color ?? AppColors.pickerPalette.first;
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
                  for (final p in pocketPresets)
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
              keyboardType: TextInputType.number,
              inputFormatters: [ThousandsSeparatorInputFormatter()],
              decoration: InputDecoration(
                labelText: isEdit
                    ? 'Saldo alokasi saat ini'
                    : 'Alokasi saldo awal (opsional)',
                prefixText: 'Rp ',
                hintText: '200.000',
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
              keyboardType: TextInputType.number,
              inputFormatters: [ThousandsSeparatorInputFormatter()],
              decoration: const InputDecoration(
                labelText: 'Target pos (opsional)',
                prefixText: 'Rp ',
                hintText: '5.000.000',
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

/// Layar interaktif untuk mengatur alokasi SEMUA pos budget di dalam 1 saku sekaligus
/// dengan slider live, numpad bertitik ribuan, tombol cepat (+50rb/+100rb/Isi Sisa/0),
/// dan bar proporsi real-time.
Future<bool?> showBulkAllocateSheet(
  BuildContext context, {
  required int walletId,
  required String walletName,
  required int totalWalletBalance,
  required List<PocketWithBalance> pockets,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.92,
      child: _BulkAllocateSheet(
        walletId: walletId,
        walletName: walletName,
        totalWalletBalance: totalWalletBalance,
        pockets: pockets,
      ),
    ),
  );
}

class _BulkAllocateSheet extends ConsumerStatefulWidget {
  const _BulkAllocateSheet({
    required this.walletId,
    required this.walletName,
    required this.totalWalletBalance,
    required this.pockets,
  });

  final int walletId;
  final String walletName;
  final int totalWalletBalance;
  final List<PocketWithBalance> pockets;

  @override
  ConsumerState<_BulkAllocateSheet> createState() => _BulkAllocateSheetState();
}

class _BulkAllocateSheetState extends ConsumerState<_BulkAllocateSheet> {
  final Map<int, TextEditingController> _controllers = {};
  final Map<int, int> _amounts = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    for (final p in widget.pockets) {
      final val = p.balance;
      _amounts[p.pocket.id] = val;
      _controllers[p.pocket.id] = TextEditingController(
        text: val > 0 ? CurrencyFormatter.format(val, withSymbol: false) : '',
      );
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  int get _totalAllocated {
    var sum = 0;
    for (final v in _amounts.values) {
      sum += v;
    }
    return sum;
  }

  int get _remaining => widget.totalWalletBalance - _totalAllocated;

  void _setAmount(int pocketId, int value) {
    final clamped = value < 0 ? 0 : value;
    setState(() {
      _amounts[pocketId] = clamped;
      final formatted = clamped > 0
          ? CurrencyFormatter.format(clamped, withSymbol: false)
          : '';
      final ctrl = _controllers[pocketId]!;
      ctrl.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    });
  }

  void _splitEqually() {
    if (widget.pockets.isEmpty || widget.totalWalletBalance <= 0) return;
    AppHaptics.selection(ref.read(settingsProvider).hapticsEnabled);
    final base = widget.totalWalletBalance ~/ widget.pockets.length;
    final rem = widget.totalWalletBalance - (base * widget.pockets.length);
    for (var i = 0; i < widget.pockets.length; i++) {
      _setAmount(widget.pockets[i].pocket.id, base + (i == 0 ? rem : 0));
    }
  }

  Future<void> _saveAll() async {
    if (_saving) return;
    if (_remaining < 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Alokasi Melebihi Saldo Saku'),
          content: Text(
            'Total alokasi (${CurrencyFormatter.format(_totalAllocated)}) melebihi saldo ${widget.walletName} (${CurrencyFormatter.format(widget.totalWalletBalance)}). Tetap simpan?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Perbaiki'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Tetap Simpan'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _saving = true);
    await ref
        .read(walletActionsProvider)
        .saveBulkPocketAllocations(
          walletId: widget.walletId,
          targetBalanceByPocketId: _amounts,
        );
    AppHaptics.medium(ref.read(settingsProvider).hapticsEnabled);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final haptics = ref.watch(settingsProvider.select((s) => s.hapticsEnabled));
    final rem = _remaining;
    final remColor = rem < 0
        ? AppColors.expense(context)
        : (rem == 0 ? AppColors.income(context) : cs.primary);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Tutup',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Atur Alokasi Budget', style: tt.titleLarge),
                      Text(
                        'Saku ${widget.walletName}',
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _splitEqually,
                  child: const Text('Bagi rata'),
                ),
              ],
            ),
          ),

          // Ringkasan Saldo + Live Stacked Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Card(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Total Saldo Saku',
                              style: tt.labelSmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              CurrencyFormatter.format(
                                widget.totalWalletBalance,
                              ),
                              style: tt.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              rem < 0
                                  ? 'Melebihi saldo'
                                  : (rem == 0
                                        ? 'Semua teralokasi'
                                        : 'Saldo Bebas (Sisa)'),
                              style: tt.labelSmall?.copyWith(color: remColor),
                            ),
                            Text(
                              rem == 0
                                  ? 'Rp 0 (100%)'
                                  : CurrencyFormatter.format(rem.abs()),
                              style: tt.titleMedium?.copyWith(
                                color: remColor,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (widget.totalWalletBalance > 0) ...[
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: SizedBox(
                          height: 10,
                          child: Row(
                            children: [
                              for (final p in widget.pockets)
                                if ((_amounts[p.pocket.id] ?? 0) > 0)
                                  Expanded(
                                    flex: _amounts[p.pocket.id]!,
                                    child: Container(
                                      color: Color(p.pocket.color),
                                    ),
                                  ),
                              if (rem > 0)
                                Expanded(
                                  flex: rem,
                                  child: Container(
                                    color: cs.outlineVariant.withValues(
                                      alpha: 0.45,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

          // Daftar Slider & Input Per Pos
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              itemCount: widget.pockets.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, idx) {
                final pb = widget.pockets[idx];
                final id = pb.pocket.id;
                final current = _amounts[id] ?? 0;
                final maxForSlider = (current + (rem > 0 ? rem : 0)).clamp(
                  0,
                  widget.totalWalletBalance > 0
                      ? widget.totalWalletBalance
                      : (current > 0 ? current : 1),
                );
                final pct = widget.totalWalletBalance > 0
                    ? ((current / widget.totalWalletBalance) * 100).round()
                    : 0;

                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CategoryIconBadge(
                              iconKey: pb.pocket.icon,
                              colorValue: pb.pocket.color,
                              size: 36,
                              iconSize: 18,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                pb.pocket.name,
                                style: tt.titleMedium,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Color(pb.pocket.color)
                                    .withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '$pct%',
                                style: tt.labelMedium?.copyWith(
                                  color: Color(pb.pocket.color),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _controllers[id],
                          keyboardType: TextInputType.number,
                          inputFormatters: [ThousandsSeparatorInputFormatter()],
                          onChanged: (txt) {
                            final parsed = AmountParser.parse(txt) ?? 0;
                            setState(() => _amounts[id] = parsed);
                          },
                          decoration: const InputDecoration(
                            prefixText: 'Rp ',
                            hintText: '0',
                            isDense: true,
                          ),
                        ),
                        if (maxForSlider > 0) ...[
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: Color(pb.pocket.color),
                              thumbColor: Color(pb.pocket.color),
                            ),
                            child: Slider(
                              value: current.clamp(0, maxForSlider).toDouble(),
                              min: 0,
                              max: maxForSlider.toDouble(),
                              onChanged: (val) {
                                // Bulatkan rapi ke kelipatan Rp 5.000 (atau 1.000 jika kecil)
                                final step = maxForSlider >= 100000
                                    ? 5000
                                    : 1000;
                                final snapped = (val / step).round() * step;
                                _setAmount(id, snapped.clamp(0, maxForSlider));
                              },
                            ),
                          ),
                        ] else
                          const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            ActionChip(
                              visualDensity: VisualDensity.compact,
                              label: const Text('+50 rb'),
                              onPressed: () {
                                AppHaptics.selection(haptics);
                                _setAmount(id, current + 50000);
                              },
                            ),
                            ActionChip(
                              visualDensity: VisualDensity.compact,
                              label: const Text('+100 rb'),
                              onPressed: () {
                                AppHaptics.selection(haptics);
                                _setAmount(id, current + 100000);
                              },
                            ),
                            if (rem > 0)
                              ActionChip(
                                visualDensity: VisualDensity.compact,
                                label: Text(
                                  'Isi sisa (${CurrencyFormatter.formatCompact(rem)})',
                                ),
                                onPressed: () {
                                  AppHaptics.selection(haptics);
                                  _setAmount(id, current + rem);
                                },
                              ),
                            if (current > 0)
                              ActionChip(
                                visualDensity: VisualDensity.compact,
                                label: const Text('0'),
                                onPressed: () {
                                  AppHaptics.selection(haptics);
                                  _setAmount(id, 0);
                                },
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Sticky Simpan Semua Button
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                border: Border(
                  top: BorderSide(
                    color: cs.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
              ),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _saveAll,
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Simpan Semua Alokasi'),
                ),
              ),
            ),
          ),
        ],
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
            Text('Pindah Budget di Saku', style: tt.headlineSmall),
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
              keyboardType: TextInputType.number,
              inputFormatters: [ThousandsSeparatorInputFormatter()],
              decoration: InputDecoration(
                labelText: 'Nominal',
                prefixText: 'Rp ',
                hintText: '200.000',
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
