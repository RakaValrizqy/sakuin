import 'package:flutter/material.dart';
import 'package:sakuin/core/utils/haptics.dart';

/// Keypad kustom besar untuk input nominal cepat (tanpa keyboard sistem).
/// Mendukung tombol cepat `000`, `k`, `jt`, serta operator kalkulator `+ − × ÷ =`.
class CustomAmountKeypad extends StatelessWidget {
  const CustomAmountKeypad({
    super.key,
    required this.onInput,
    required this.onBackspace,
    required this.onClear,
    required this.onEvaluate,
    required this.hapticsEnabled,
    this.showEvaluate = false,
  });

  final ValueChanged<String> onInput;
  final VoidCallback onBackspace;
  final VoidCallback onClear;
  final VoidCallback onEvaluate;
  final bool hapticsEnabled;
  final bool showEvaluate;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget keyBtn(
      String label, {
      VoidCallback? onTap,
      VoidCallback? onLongPress,
      Color? bg,
      Color? fg,
      IconData? icon,
      double fontSize = 20,
    }) {
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Material(
            color: bg ?? cs.surfaceContainerHighest.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                AppHaptics.selection(hapticsEnabled);
                onTap?.call();
              },
              onLongPress: onLongPress,
              child: SizedBox(
                height: 50,
                child: Center(
                  child: icon != null
                      ? Icon(icon, color: fg ?? cs.onSurface, size: 22)
                      : Text(
                          label,
                          style: TextStyle(
                            fontSize: fontSize,
                            fontWeight: FontWeight.w600,
                            color: fg ?? cs.onSurface,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final opBg = cs.secondaryContainer.withValues(alpha: 0.7);
    final opFg = cs.onSecondaryContainer;
    final quickBg = cs.primaryContainer.withValues(alpha: 0.65);
    final quickFg = cs.onPrimaryContainer;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Baris pintasan singkatan & hapus semua
        Row(
          children: [
            keyBtn(
              'C',
              onTap: onClear,
              bg: cs.errorContainer.withValues(alpha: 0.65),
              fg: cs.onErrorContainer,
              fontSize: 17,
            ),
            keyBtn(
              'rb (k)',
              onTap: () => onInput('k'),
              bg: quickBg,
              fg: quickFg,
              fontSize: 15,
            ),
            keyBtn(
              'jt',
              onTap: () => onInput('jt'),
              bg: quickBg,
              fg: quickFg,
              fontSize: 16,
            ),
            keyBtn(
              '÷',
              onTap: () => onInput('÷'),
              bg: opBg,
              fg: opFg,
              fontSize: 22,
            ),
          ],
        ),
        Row(
          children: [
            keyBtn('7', onTap: () => onInput('7')),
            keyBtn('8', onTap: () => onInput('8')),
            keyBtn('9', onTap: () => onInput('9')),
            keyBtn(
              '×',
              onTap: () => onInput('×'),
              bg: opBg,
              fg: opFg,
              fontSize: 22,
            ),
          ],
        ),
        Row(
          children: [
            keyBtn('4', onTap: () => onInput('4')),
            keyBtn('5', onTap: () => onInput('5')),
            keyBtn('6', onTap: () => onInput('6')),
            keyBtn(
              '−',
              onTap: () => onInput('−'),
              bg: opBg,
              fg: opFg,
              fontSize: 22,
            ),
          ],
        ),
        Row(
          children: [
            keyBtn('1', onTap: () => onInput('1')),
            keyBtn('2', onTap: () => onInput('2')),
            keyBtn('3', onTap: () => onInput('3')),
            keyBtn(
              '+',
              onTap: () => onInput('+'),
              bg: opBg,
              fg: opFg,
              fontSize: 22,
            ),
          ],
        ),
        Row(
          children: [
            keyBtn(',', onTap: () => onInput(',')),
            keyBtn('0', onTap: () => onInput('0')),
            keyBtn('000', onTap: () => onInput('000'), fontSize: 17),
            if (showEvaluate)
              keyBtn(
                '=',
                onTap: onEvaluate,
                bg: cs.primary,
                fg: cs.onPrimary,
                fontSize: 22,
              )
            else
              keyBtn(
                '',
                icon: Icons.backspace_outlined,
                onTap: onBackspace,
                onLongPress: onClear,
                bg: cs.surfaceContainerHigh,
              ),
          ],
        ),
      ],
    );
  }
}
