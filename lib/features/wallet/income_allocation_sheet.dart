import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sakuin/core/constants/app_icons.dart';
import 'package:sakuin/core/db/app_database.dart';
import 'package:sakuin/core/services/settings_service.dart';
import 'package:sakuin/core/utils/currency_formatter.dart';
import 'package:sakuin/core/utils/haptics.dart';
import 'package:sakuin/core/utils/income_allocation_calculator.dart';
import 'package:sakuin/features/wallet/wallet_providers.dart';

/// Tampilkan bottom sheet pembagian pemasukan ke berbagai pos budget berdasarkan persentase,
/// lengkap dengan porsi otomatis "Belum Dialokasikan" (Saldo Bebas) untuk sisa persentase.
/// Mengembalikan `true` jika pengguna menerapkan alokasi, `false` jika dilewati.
Future<bool?> showIncomePercentageAllocationSheet(
  BuildContext context, {
  required int walletId,
  required String walletName,
  required int incomeAmount,
  required List<PocketWithBalance> pockets,
  String? incomeTitle,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.92,
      child: _IncomePercentageAllocationSheet(
        walletId: walletId,
        walletName: walletName,
        incomeAmount: incomeAmount,
        pockets: pockets,
        incomeTitle: incomeTitle,
      ),
    ),
  );
}

class _IncomePercentageAllocationSheet extends ConsumerStatefulWidget {
  const _IncomePercentageAllocationSheet({
    required this.walletId,
    required this.walletName,
    required this.incomeAmount,
    required this.pockets,
    this.incomeTitle,
  });

  final int walletId;
  final String walletName;
  final int incomeAmount;
  final List<PocketWithBalance> pockets;
  final String? incomeTitle;

  @override
  ConsumerState<_IncomePercentageAllocationSheet> createState() =>
      _IncomePercentageAllocationSheetState();
}

class _IncomePercentageAllocationSheetState
    extends ConsumerState<_IncomePercentageAllocationSheet> {
  final Map<int, int> _percents = {};
  final Map<int, TextEditingController> _pctCtrls = {};
  bool _rememberTemplate = true;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    for (final p in widget.pockets) {
      _percents[p.pocket.id] = 0;
      _pctCtrls[p.pocket.id] = TextEditingController(text: '0');
    }
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final saved = await IncomeAllocationCalculator.loadSavedPercentages(
      widget.walletId,
    );
    if (!mounted) return;
    if (saved.isNotEmpty) {
      var used = 0;
      for (final p in widget.pockets) {
        final id = p.pocket.id;
        final val = (saved[id] ?? 0).clamp(0, 100 - used);
        _percents[id] = val;
        _pctCtrls[id]!.text = '$val';
        used += val;
      }
    }
    setState(() => _loading = false);
  }

  @override
  void dispose() {
    for (final c in _pctCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  List<int> get _pocketIds => widget.pockets.map((p) => p.pocket.id).toList();

  IncomeAllocationResult get _calc => IncomeAllocationCalculator.calculate(
    incomeAmount: widget.incomeAmount,
    pocketIds: _pocketIds,
    rawPercentByPocketId: _percents,
  );

  int _maxAllowedFor(int pocketId) {
    var others = 0;
    for (final entry in _percents.entries) {
      if (entry.key != pocketId) others += entry.value;
    }
    return (100 - others).clamp(0, 100);
  }

  void _setPercent(
    int pocketId,
    int requested, {
    bool updateController = true,
  }) {
    final maxAllowed = _maxAllowedFor(pocketId);
    final clamped = requested.clamp(0, maxAllowed);
    setState(() {
      _percents[pocketId] = clamped;
      if (updateController) {
        _pctCtrls[pocketId]!.text = '$clamped';
        _pctCtrls[pocketId]!.selection = TextSelection.collapsed(
          offset: _pctCtrls[pocketId]!.text.length,
        );
      }
    });
  }

  void _splitEqually() {
    if (widget.pockets.isEmpty) return;
    AppHaptics.selection(ref.read(settingsProvider).hapticsEnabled);
    final count = widget.pockets.length;
    final base = 100 ~/ count;
    final rem = 100 % count;
    setState(() {
      for (var i = 0; i < count; i++) {
        final id = widget.pockets[i].pocket.id;
        final val = base + (i < rem ? 1 : 0);
        _percents[id] = val;
        _pctCtrls[id]!.text = '$val';
      }
    });
  }

  void _resetAll() {
    AppHaptics.selection(ref.read(settingsProvider).hapticsEnabled);
    setState(() {
      for (final p in widget.pockets) {
        _percents[p.pocket.id] = 0;
        _pctCtrls[p.pocket.id]!.text = '0';
      }
    });
  }

  Future<void> _apply() async {
    if (_saving) return;
    final res = _calc;
    setState(() => _saving = true);

    if (_rememberTemplate) {
      await IncomeAllocationCalculator.savePercentages(
        widget.walletId,
        res.percentByPocketId,
      );
    }

    final noteLabel =
        (widget.incomeTitle != null && widget.incomeTitle!.trim().isNotEmpty)
        ? 'Bagi pemasukan: ${widget.incomeTitle!.trim()}'
        : 'Bagi otomatis dari pemasukan';

    if (res.allocatedTotal > 0) {
      await ref
          .read(walletActionsProvider)
          .allocateIncomeToPockets(
            walletId: widget.walletId,
            amountByPocketId: res.amountByPocketId,
            note: noteLabel,
          );
    }

    AppHaptics.medium(ref.read(settingsProvider).hapticsEnabled);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final calc = _calc;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Lewati',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.of(context).pop(false),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Bagi Pemasukan (%)', style: tt.titleLarge),
                            Text(
                              '${widget.walletName} • ${CurrencyFormatter.format(widget.incomeAmount)}',
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
                      TextButton(onPressed: _resetAll, child: const Text('0%')),
                    ],
                  ),
                ),

                // Bar Proporsi Visual Live (Pos Budget + Belum Dialokasikan)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Dialokasikan: ${calc.allocatedPercent}%',
                                style: tt.labelLarge?.copyWith(
                                  color: cs.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                'Belum Dialokasikan: ${calc.unallocatedPercent}%',
                                style: tt.labelMedium?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(
                              height: 12,
                              child: Row(
                                children: [
                                  for (final p in widget.pockets)
                                    if ((calc.percentByPocketId[p.pocket.id] ??
                                            0) >
                                        0)
                                      Expanded(
                                        flex:
                                            calc.percentByPocketId[p
                                                .pocket
                                                .id] ??
                                            0,
                                        child: Container(
                                          color: Color(p.pocket.color),
                                        ),
                                      ),
                                  if (calc.unallocatedPercent > 0)
                                    Expanded(
                                      flex: calc.unallocatedPercent,
                                      child: Container(
                                        color: cs.surfaceContainerHighest,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Daftar Pos Budget + Kartu "Belum Dialokasikan"
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                    children: [
                      for (final p in widget.pockets) ...[
                        _buildPocketRowCard(context, p, calc),
                        const SizedBox(height: 10),
                      ],

                      // Kategori Khusus: Belum Dialokasikan (Unallocated / Saldo Bebas)
                      Card(
                        color: cs.surfaceContainerLow,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                          side: BorderSide(color: cs.outlineVariant),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 18,
                                    backgroundColor: cs.surfaceContainerHighest,
                                    child: Icon(
                                      Icons.inbox_outlined,
                                      size: 20,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Belum Dialokasikan (Saldo Bebas)',
                                          style: tt.titleSmall?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        Text(
                                          'Otomatis menampung sisa persentase yang belum ditentukan posnya',
                                          style: tt.bodySmall?.copyWith(
                                            color: cs.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        '${calc.unallocatedPercent}%',
                                        style: tt.titleMedium?.copyWith(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      Text(
                                        '+${CurrencyFormatter.format(calc.unallocatedAmount)}',
                                        style: tt.labelMedium?.copyWith(
                                          color: cs.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'Ingat persentase ini untuk ${widget.walletName}',
                        ),
                        subtitle: const Text(
                          'Otomatis terisi saat ada pemasukan berikutnya di saku ini',
                        ),
                        value: _rememberTemplate,
                        onChanged: (v) => setState(() => _rememberTemplate = v),
                      ),
                    ],
                  ),
                ),

                // Sticky Bottom Bar
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
                    child: Row(
                      children: [
                        OutlinedButton(
                          onPressed: _saving
                              ? null
                              : () => Navigator.of(context).pop(false),
                          child: const Text('Lewati'),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _saving ? null : _apply,
                            icon: _saving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.pie_chart_rounded, size: 18),
                            label: Text(
                              calc.allocatedTotal > 0
                                  ? 'Terapkan (${calc.allocatedPercent}% ke Pos)'
                                  : 'Simpan ke Belum Dialokasikan',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildPocketRowCard(
    BuildContext context,
    PocketWithBalance pocketItem,
    IncomeAllocationResult calc,
  ) {
    final id = pocketItem.pocket.id;
    final pct = _percents[id] ?? 0;
    final maxAllowed = _maxAllowedFor(id);
    final amt = calc.amountByPocketId[id] ?? 0;
    final color = Color(pocketItem.pocket.color);
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: color.withValues(alpha: 0.16),
                  child: Icon(
                    AppIcons.fromKey(pocketItem.pocket.icon),
                    size: 20,
                    color: color,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pocketItem.pocket.name,
                        style: tt.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Saldo: ${CurrencyFormatter.format(pocketItem.balance)} → ${CurrencyFormatter.format(pocketItem.balance + amt)}',
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 72,
                  child: TextField(
                    controller: _pctCtrls[id],
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(3),
                    ],
                    decoration: const InputDecoration(
                      suffixText: '%',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                    ),
                    onChanged: (raw) {
                      final parsed = int.tryParse(raw) ?? 0;
                      _setPercent(
                        id,
                        parsed,
                        updateController: parsed > maxAllowed,
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: color,
                      thumbColor: color,
                      overlayColor: color.withValues(alpha: 0.16),
                    ),
                    child: Slider(
                      value: pct.toDouble(),
                      min: 0,
                      max: 100,
                      divisions: 100,
                      onChanged: (v) {
                        _setPercent(id, v.round());
                      },
                    ),
                  ),
                ),
                SizedBox(
                  width: 96,
                  child: Text(
                    '+${CurrencyFormatter.formatCompact(amt)}',
                    textAlign: TextAlign.end,
                    style: tt.labelLarge?.copyWith(
                      color: amt > 0 ? color : cs.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final preset in const [10, 20, 30, 50])
                  ActionChip(
                    visualDensity: VisualDensity.compact,
                    label: Text('$preset%', style: tt.labelSmall),
                    onPressed: () {
                      AppHaptics.selection(
                        ref.read(settingsProvider).hapticsEnabled,
                      );
                      _setPercent(id, preset);
                    },
                  ),
                if (calc.unallocatedPercent > 0)
                  ActionChip(
                    visualDensity: VisualDensity.compact,
                    label: Text(
                      'Isi sisa (${pct + calc.unallocatedPercent}%)',
                      style: tt.labelSmall,
                    ),
                    onPressed: () {
                      AppHaptics.selection(
                        ref.read(settingsProvider).hapticsEnabled,
                      );
                      _setPercent(id, pct + calc.unallocatedPercent);
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
