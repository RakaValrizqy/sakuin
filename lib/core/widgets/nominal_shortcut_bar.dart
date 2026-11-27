import 'package:flutter/material.dart';
import 'package:sakuin/core/utils/amount_parser.dart';
import 'package:sakuin/core/utils/currency_formatter.dart';
import 'package:sakuin/core/utils/haptics.dart';

/// Bar tombol cepat (ribu, juta, +10 rb, +50 rb, +100 rb, Hapus) yang dipasang
/// bersama keyboard numpad bawaan HP agar input nominal tetap super cepat.
class NominalShortcutBar extends StatelessWidget {
  const NominalShortcutBar({
    super.key,
    required this.controller,
    this.onChanged,
    this.hapticsEnabled = true,
  });

  final TextEditingController controller;
  final VoidCallback? onChanged;
  final bool hapticsEnabled;

  static const int _maxValue = 999999999999; // 12 digit

  void _setAmount(int value) {
    final safe = value.clamp(0, _maxValue);
    final formatted = safe == 0
        ? ''
        : CurrencyFormatter.format(safe, withSymbol: false);
    controller.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
    onChanged?.call();
  }

  void _multiply(int factor) {
    AppHaptics.selection(hapticsEnabled);
    final current = AmountParser.parse(controller.text) ?? 0;
    final next = current == 0 ? factor : current * factor;
    _setAmount(next);
  }

  void _add(int delta) {
    AppHaptics.selection(hapticsEnabled);
    final current = AmountParser.parse(controller.text) ?? 0;
    _setAmount(current + delta);
  }

  void _clear() {
    AppHaptics.selection(hapticsEnabled);
    _setAmount(0);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    Widget pill(String label, VoidCallback onTap, {bool accent = false}) {
      return ActionChip(
        visualDensity: VisualDensity.compact,
        backgroundColor: accent
            ? cs.primaryContainer.withValues(alpha: 0.65)
            : null,
        label: Text(
          label,
          style: tt.labelMedium?.copyWith(
            fontWeight: accent ? FontWeight.w700 : FontWeight.w600,
            color: accent ? cs.onPrimaryContainer : null,
          ),
        ),
        onPressed: onTap,
      );
    }

    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          pill('rb (×1.000)', () => _multiply(1000), accent: true),
          const SizedBox(width: 6),
          pill('jt (×1 jt)', () => _multiply(1000000), accent: true),
          const SizedBox(width: 6),
          pill('+10 rb', () => _add(10000)),
          const SizedBox(width: 6),
          pill('+50 rb', () => _add(50000)),
          const SizedBox(width: 6),
          pill('+100 rb', () => _add(100000)),
          const SizedBox(width: 6),
          pill('Hapus', _clear),
        ],
      ),
    );
  }
}
