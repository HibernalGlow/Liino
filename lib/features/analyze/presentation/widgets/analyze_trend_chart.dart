import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:looper_player/core/theme/app_fonts.dart';
import 'package:looper_player/features/analyze/domain/analyze_models.dart';
import 'package:looper_player/features/analyze/presentation/widgets/analyze_common.dart';
import 'package:looper_player/core/utils/l10n.dart';

/// Last-30-days listening trend — a hand-painted animated bar chart built
/// from the play-event log, headed by the window's total and daily average.
/// Bars grow in from the baseline on first build; the busiest day and today
/// are drawn at full strength.
class AnalyzeTrendChart extends StatelessWidget {
  final List<DailyCount> dailyCounts;
  final Color accent;

  const AnalyzeTrendChart({
    super.key,
    required this.dailyCounts,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final total = dailyCounts.fold<int>(0, (sum, d) => sum + d.plays);
    final average = dailyCounts.isEmpty ? 0.0 : total / dailyCounts.length;
    final locale = analyzeLocale(context);
    final dateFormat = DateFormat.MMMd(locale);
    final dateStyle = AppFonts.jostStyle(
      color: Colors.white.withValues(alpha: 0.4),
      fontSize: 11,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnalyzeSectionHeader(
          title: context.l10n.listeningTrend,
          subtitle: context.l10n.last30Days,
        ),
        AnalyzeCard(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.playsCount(total),
                style: AppFonts.jostStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
              Text(
                context.l10n.analyzeAvgPerDay(
                  NumberFormat.decimalPatternDigits(
                    locale: locale,
                    decimalDigits: 1,
                  ).format(average),
                ),
                style: AppFonts.jostStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 110,
                width: double.infinity,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeOutCubic,
                  builder: (context, progress, _) => CustomPaint(
                    painter: _TrendPainter(
                      counts: dailyCounts,
                      progress: progress,
                      color: accent,
                      averageFraction: _averageFraction(average),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (dailyCounts.isNotEmpty)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      dateFormat.format(dailyCounts.first.date),
                      style: dateStyle,
                    ),
                    Text(
                      dateFormat.format(
                        dailyCounts[dailyCounts.length ~/ 2].date,
                      ),
                      style: dateStyle,
                    ),
                    Text(
                      dateFormat.format(dailyCounts.last.date),
                      style: dateStyle,
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  double _averageFraction(double average) {
    final maxCount = dailyCounts.fold<int>(
      0,
      (a, d) => d.plays > a ? d.plays : a,
    );
    return maxCount == 0 ? 0 : average / maxCount;
  }
}

class _TrendPainter extends CustomPainter {
  final List<DailyCount> counts;
  final double progress;
  final Color color;
  final double averageFraction;

  _TrendPainter({
    required this.counts,
    required this.progress,
    required this.color,
    required this.averageFraction,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (counts.isEmpty) return;
    var maxCount = 0;
    var peakIndex = -1;
    for (var i = 0; i < counts.length; i++) {
      if (counts[i].plays >= maxCount && counts[i].plays > 0) {
        maxCount = counts[i].plays;
        peakIndex = i;
      }
    }
    final safeMax = maxCount == 0 ? 1 : maxCount;
    final barWidth = size.width / counts.length;
    // The window always ends today (see AnalyzeSnapshot._computeDailyCounts).
    final todayIndex = counts.length - 1;

    final paint = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < counts.length; i++) {
      final count = counts[i];
      final left = i * barWidth + barWidth * 0.2;
      final right = (i + 1) * barWidth - barWidth * 0.2;

      if (count.plays == 0) {
        paint.color = Colors.white.withValues(alpha: 0.06);
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTRB(left, size.height - 3, right, size.height),
            topLeft: const Radius.circular(2),
            topRight: const Radius.circular(2),
          ),
          paint,
        );
        continue;
      }

      final barHeight = (size.height - 4) * (count.plays / safeMax) * progress;
      final strong = i == peakIndex || i == todayIndex;
      paint.color = color.withValues(alpha: strong ? 1.0 : 0.5);
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTRB(left, size.height - barHeight, right, size.height),
          topLeft: const Radius.circular(3),
          topRight: const Radius.circular(3),
        ),
        paint,
      );
    }

    // Dashed daily-average guide.
    if (averageFraction > 0) {
      final y = size.height - (size.height - 4) * averageFraction * progress;
      final dash = Paint()
        ..color = Colors.white.withValues(alpha: 0.28)
        ..strokeWidth = 1;
      for (var x = 0.0; x < size.width; x += 7) {
        canvas.drawLine(Offset(x, y), Offset(x + 3.5, y), dash);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.counts != counts ||
      oldDelegate.color != color ||
      oldDelegate.averageFraction != averageFraction;
}
