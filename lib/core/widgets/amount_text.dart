import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sakuin/core/constants/app_colors.dart';
import 'package:sakuin/core/services/settings_service.dart';
import 'package:sakuin/core/utils/currency_formatter.dart';

class AmountText extends ConsumerWidget {
  const AmountText({
    super.key,
    required this.amount,
    this.type,
    this.style,
    this.signed = false,
    this.compact = false,
    this.respectHideBalance = true,
    this.maxLines = 1,
  });

  final int amount;

  /// 'expense' | 'income' | 'transfer' | null (default text color)
  final String? type;
  final TextStyle? style;
  final bool signed;
  final bool compact;
  final bool respectHideBalance;
  final int maxLines;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hidden =
        respectHideBalance &&
        ref.watch(settingsProvider.select((s) => s.hideBalances));

    Color? color;
    if (type == 'expense') {
      color = AppColors.expense(context);
    } else if (type == 'income') {
      color = AppColors.income(context);
    } else if (type == 'transfer') {
      color = AppColors.transfer(context);
    }

    String text;
    if (hidden) {
      text = CurrencyFormatter.masked;
    } else if (compact) {
      text = CurrencyFormatter.formatCompact(amount);
    } else if (signed) {
      if (type == 'expense') {
        text = '-${CurrencyFormatter.format(amount.abs())}';
      } else if (type == 'income') {
        text = '+${CurrencyFormatter.format(amount.abs())}';
      } else {
        text = CurrencyFormatter.formatSigned(amount);
      }
    } else {
      text = CurrencyFormatter.format(amount);
    }

    final baseStyle = style ?? Theme.of(context).textTheme.titleMedium;
    return Text(
      text,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: baseStyle?.copyWith(
        color: color ?? baseStyle.color,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}
