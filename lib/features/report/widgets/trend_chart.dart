import 'package:flutter/material.dart';
import 'package:sakuin/core/constants/app_colors.dart';
import 'package:sakuin/core/db/app_database.dart';
import 'package:sakuin/core/utils/currency_formatter.dart';
import 'package:sakuin/core/utils/date_utils.dart';

/// Grafik tren pengeluaran & pemasukan (`CustomPainter` + `RepaintBoundary`).
class PeriodTrendChart extends StatelessWidget {
  const PeriodTrendChart({super.key, required this.points});

  final List<DailyTrendPoint> points;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    if (points.isEmpty) {
      return SizedBox(
        height: 150,
        child: Center(
          child: Text(
            'Belum ada data tren di periode ini',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
      );
    }

    var maxVal = 1;
    for (final p in points) {
      if (p.income > maxVal) maxVal = p.income;
      if (p.expense > maxVal) maxVal = p.expense;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Puncak: ${CurrencyFormatter.formatCompact(maxVal)}',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            Row(
              children: [
                _LegendDot(color: AppColors.income(context), label: 'Masuk'),
                const SizedBox(width: 12),
                _LegendDot(color: AppColors.expense(context), label: 'Keluar'),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 160,
          width: double.infinity,
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _TrendBarPainter(
                points: points,
                maxVal: maxVal,
                incomeColor: AppColors.income(context),
                expenseColor: AppColors.expense(context),
                gridColor: cs.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              AppDateUtils.formatDayMonth(
                AppDateUtils.fromDayKey(points.first.dayKey),
              ),
              style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            if (points.length > 2)
              Text(
                AppDateUtils.formatDayMonth(
                  AppDateUtils.fromDayKey(points[points.length ~/ 2].dayKey),
                ),
                style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            Text(
              AppDateUtils.formatDayMonth(
                AppDateUtils.fromDayKey(points.last.dayKey),
              ),
              style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

class _TrendBarPainter extends CustomPainter {
  _TrendBarPainter({
    required this.points,
    required this.maxVal,
    required this.incomeColor,
    required this.expenseColor,
    required this.gridColor,
  });

  final List<DailyTrendPoint> points;
  final int maxVal;
  final Color incomeColor;
  final Color expenseColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;

    // 3 garis grid horizontal tipis
    for (var i = 0; i <= 2; i++) {
      final y = (size.height - 6) * (i / 2) + 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final slotWidth = size.width / points.length;
    final barWidth = (slotWidth * 0.36).clamp(3.0, 14.0);
    final usableHeight = size.height - 10;

    final incPaint = Paint()..color = incomeColor;
    final expPaint = Paint()..color = expenseColor;

    for (var i = 0; i < points.length; i++) {
      final pt = points[i];
      final cx = i * slotWidth + slotWidth / 2;
      if (pt.income > 0) {
        final h = (pt.income / maxVal) * usableHeight;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(cx - barWidth - 1, size.height - 3 - h, barWidth, h),
            const Radius.circular(3),
          ),
          incPaint,
        );
      }
      if (pt.expense > 0) {
        final h = (pt.expense / maxVal) * usableHeight;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(cx + 1, size.height - 3 - h, barWidth, h),
            const Radius.circular(3),
          ),
          expPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TrendBarPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.maxVal != maxVal;
}
