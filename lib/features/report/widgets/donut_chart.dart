import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sakuin/core/db/app_database.dart';
import 'package:sakuin/core/utils/currency_formatter.dart';

/// Grafik Donut kustom ringan (`CustomPainter` + `RepaintBoundary`)
/// dengan dukungan ketuk pada potongan untuk drill-down kategori.
class CategoryDonutChart extends StatelessWidget {
  const CategoryDonutChart({
    super.key,
    required this.items,
    required this.total,
    required this.centerLabel,
    this.selectedCategoryId,
    this.onSliceTap,
  });

  final List<CategoryAggregate> items;
  final int total;
  final String centerLabel;
  final int? selectedCategoryId;
  final ValueChanged<CategoryAggregate>? onSliceTap;

  void _handleTap(Offset localPosition, Size size) {
    if (onSliceTap == null || items.isEmpty || total <= 0) return;
    final center = Offset(size.width / 2, size.height / 2);
    final dx = localPosition.dx - center.dx;
    final dy = localPosition.dy - center.dy;
    final distance = math.sqrt(dx * dx + dy * dy);
    final outerRadius = math.min(size.width, size.height) / 2 - 8;
    final innerRadius = outerRadius * 0.56;
    if (distance < innerRadius || distance > outerRadius) return;

    var angle = math.atan2(dy, dx) + math.pi / 2;
    if (angle < 0) angle += math.pi * 2;

    var current = 0.0;
    for (final item in items) {
      final sweep = (item.total / total) * math.pi * 2;
      if (angle >= current && angle <= current + sweep) {
        onSliceTap!(item);
        return;
      }
      current += sweep;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return SizedBox(
      height: 210,
      width: 210,
      child: LayoutBuilder(
        builder: (ctx, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          return GestureDetector(
            onTapUp: (details) => _handleTap(details.localPosition, size),
            child: Stack(
              alignment: Alignment.center,
              children: [
                RepaintBoundary(
                  child: CustomPaint(
                    size: size,
                    painter: _DonutPainter(
                      items: items,
                      total: total,
                      selectedCategoryId: selectedCategoryId,
                      emptyColor: cs.surfaceContainerHighest,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        centerLabel,
                        style: tt.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          CurrencyFormatter.formatCompact(total),
                          style: tt.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.items,
    required this.total,
    required this.selectedCategoryId,
    required this.emptyColor,
  });

  final List<CategoryAggregate> items;
  final int total;
  final int? selectedCategoryId;
  final Color emptyColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 14;
    const strokeWidth = 28.0;

    if (items.isEmpty || total <= 0) {
      final paint = Paint()
        ..color = emptyColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth;
      canvas.drawCircle(center, radius, paint);
      return;
    }

    var startAngle = -math.pi / 2;
    final gap = items.length > 1 ? 0.025 : 0.0;

    for (final item in items) {
      final sweep = (item.total / total) * math.pi * 2;
      final isSelected =
          selectedCategoryId != null && item.categoryId == selectedCategoryId;
      final paint = Paint()
        ..color = Color(item.color)
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSelected ? strokeWidth + 6 : strokeWidth
        ..strokeCap = StrokeCap.butt;

      final rect = Rect.fromCircle(center: center, radius: radius);
      final drawSweep = math.max(0.01, sweep - gap);
      canvas.drawArc(rect, startAngle + gap / 2, drawSweep, false, paint);
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.items != items ||
      oldDelegate.total != total ||
      oldDelegate.selectedCategoryId != selectedCategoryId;
}
