import 'package:flutter/material.dart';
import 'package:sakuin/core/constants/app_icons.dart';

class CategoryIconBadge extends StatelessWidget {
  const CategoryIconBadge({
    super.key,
    required this.iconKey,
    required this.colorValue,
    this.size = 44,
    this.iconSize = 22,
  });

  final String iconKey;
  final int colorValue;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final color = Color(colorValue);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.22 : 0.14),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      alignment: Alignment.center,
      child: Icon(AppIcons.fromKey(iconKey), color: color, size: iconSize),
    );
  }
}
