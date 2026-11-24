import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/core_engine.dart';
import 'activity_formatters.dart';
import 'gpx_lab_theme.dart';

/// Displays interactive Channel charts for Heart Rate, Elevation, and Pace,
/// and cleanly marks unavailable Channels.
class ChannelChartsSection extends StatelessWidget {
  const ChannelChartsSection({
    super.key,
    required this.geometry,
    this.unitSystem = UnitSystem.metric,
  });

  final ActivityDisplayGeometry geometry;
  final UnitSystem unitSystem;

  @override
  Widget build(BuildContext context) {
    final brandColors = GpxLabBrandColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ChannelChartOrEmpty(
          chartKey: const Key('chart-heart-rate'),
          unavailableKey: const Key('chart-heart-rate-unavailable'),
          title: 'Heart Rate',
          icon: Icons.favorite_outline,
          accentColor: brandColors.heartRate,
          samples: geometry.heartRateSeries,
          unitSystem: unitSystem,
          formatValue: (v) => '${v.round()} bpm',
        ),
        const SizedBox(height: 12),
        _ChannelChartOrEmpty(
          chartKey: const Key('chart-elevation'),
          unavailableKey: const Key('chart-elevation-unavailable'),
          title: 'Elevation',
          icon: Icons.terrain_outlined,
          accentColor: brandColors.elevation,
          samples: geometry.elevationSeries,
          unitSystem: unitSystem,
          formatValue: (v) => formatElevation(v, units: unitSystem),
        ),
        const SizedBox(height: 12),
        _ChannelChartOrEmpty(
          chartKey: const Key('chart-pace'),
          unavailableKey: const Key('chart-pace-unavailable'),
          title: 'Pace',
          icon: Icons.speed_outlined,
          accentColor: brandColors.pace,
          samples: geometry.paceSeries,
          unitSystem: unitSystem,
          invertY: true,
          formatValue: (v) => formatPace(v, units: unitSystem),
        ),
      ],
    );
  }
}

class _ChannelChartOrEmpty extends StatelessWidget {
  const _ChannelChartOrEmpty({
    required this.chartKey,
    required this.unavailableKey,
    required this.title,
    required this.icon,
    required this.accentColor,
    required this.samples,
    required this.unitSystem,
    required this.formatValue,
    this.invertY = false,
  });

  final Key chartKey;
  final Key unavailableKey;
  final String title;
  final IconData icon;
  final Color accentColor;
  final List<ChartSample> samples;
  final UnitSystem unitSystem;
  final String Function(double value) formatValue;
  final bool invertY;

  @override
  Widget build(BuildContext context) {
    if (samples.isEmpty) {
      final colors = Theme.of(context).colorScheme;
      return Card(
        key: unavailableKey,
        child: ListTile(
          dense: true,
          leading: Icon(icon, color: colors.onSurfaceVariant),
          title: Text(title),
          trailing: Text(
            'Unavailable',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
          ),
        ),
      );
    }

    return _InteractiveChannelChartCard(
      key: chartKey,
      title: title,
      icon: icon,
      accentColor: accentColor,
      samples: samples,
      unitSystem: unitSystem,
      formatValue: formatValue,
      invertY: invertY,
    );
  }
}

class _InteractiveChannelChartCard extends StatefulWidget {
  const _InteractiveChannelChartCard({
    super.key,
    required this.title,
    required this.icon,
    required this.accentColor,
    required this.samples,
    required this.unitSystem,
    required this.formatValue,
    required this.invertY,
  });

  final String title;
  final IconData icon;
  final Color accentColor;
  final List<ChartSample> samples;
  final UnitSystem unitSystem;
  final String Function(double value) formatValue;
  final bool invertY;

  @override
  State<_InteractiveChannelChartCard> createState() =>
      _InteractiveChannelChartCardState();
}

class _InteractiveChannelChartCardState
    extends State<_InteractiveChannelChartCard> {
  int? _scrubIndex;

  void _updateScrub(double localX, double width) {
    if (widget.samples.isEmpty || width <= 0) return;
    final ratio = (localX / width).clamp(0.0, 1.0);
    final idx = (ratio * (widget.samples.length - 1)).round();
    setState(() => _scrubIndex = idx);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final samples = widget.samples;

    var minVal = samples.first.value;
    var maxVal = samples.first.value;
    var sum = 0.0;
    for (final s in samples) {
      if (s.value < minVal) minVal = s.value;
      if (s.value > maxVal) maxVal = s.value;
      sum += s.value;
    }
    final avgVal = sum / samples.length;

    final activeSample =
        _scrubIndex != null ? samples[_scrubIndex!] : null;

    final subtitle = activeSample != null
        ? '${widget.formatValue(activeSample.value)} • ${formatDistance(activeSample.distanceMeters, units: widget.unitSystem)}'
        : 'Avg ${widget.formatValue(avgVal)} • Max ${widget.formatValue(widget.invertY ? minVal : maxVal)}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(widget.icon, size: 18, color: widget.accentColor),
                const SizedBox(width: 8),
                Text(
                  widget.title,
                  style: theme.textTheme.titleSmall,
                ),
                const Spacer(),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 120,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (d) =>
                        _updateScrub(d.localPosition.dx, constraints.maxWidth),
                    onHorizontalDragStart: (d) =>
                        _updateScrub(d.localPosition.dx, constraints.maxWidth),
                    onHorizontalDragUpdate: (d) =>
                        _updateScrub(d.localPosition.dx, constraints.maxWidth),
                    onHorizontalDragEnd: (_) =>
                        setState(() => _scrubIndex = null),
                    child: CustomPaint(
                      size: Size(constraints.maxWidth, 120),
                      painter: _ChannelLinePainter(
                        samples: samples,
                        minVal: minVal,
                        maxVal: maxVal,
                        lineColor: widget.accentColor,
                        haloColor: GpxLabBrandColors.of(context).markerHalo,
                        gridColor:
                            colors.outlineVariant.withValues(alpha: 0.45),
                        scrubIndex: _scrubIndex,
                        invertY: widget.invertY,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Min ${widget.formatValue(minVal)}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                Text(
                  'Max ${widget.formatValue(maxVal)}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ChannelLinePainter extends CustomPainter {
  const _ChannelLinePainter({
    required this.samples,
    required this.minVal,
    required this.maxVal,
    required this.lineColor,
    required this.haloColor,
    required this.gridColor,
    required this.scrubIndex,
    required this.invertY,
  });

  final List<ChartSample> samples;
  final double minVal;
  final double maxVal;
  final Color lineColor;
  final Color haloColor;
  final Color gridColor;
  final int? scrubIndex;
  final bool invertY;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1.0;

    for (var i = 0; i <= 2; i++) {
      final y = size.height * (i / 2);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (samples.isEmpty) return;

    final span = (maxVal - minVal).abs();
    final safeSpan = span < 1e-6 ? 1.0 : span;
    const padY = 8.0;
    final drawH = math.max(1.0, size.height - padY * 2);

    double yFor(double value) {
      final norm = ((value - minVal) / safeSpan).clamp(0.0, 1.0);
      final directed = invertY ? norm : (1.0 - norm);
      return padY + directed * drawH;
    }

    final offsets = <Offset>[];
    final count = samples.length;
    for (var i = 0; i < count; i++) {
      final x = count == 1 ? size.width / 2 : (i / (count - 1)) * size.width;
      offsets.add(Offset(x, yFor(samples[i].value)));
    }

    if (offsets.length > 1) {
      final fillPath = Path()
        ..moveTo(offsets.first.dx, size.height)
        ..lineTo(offsets.first.dx, offsets.first.dy);
      final linePath = Path()..moveTo(offsets.first.dx, offsets.first.dy);

      for (var i = 1; i < offsets.length; i++) {
        fillPath.lineTo(offsets[i].dx, offsets[i].dy);
        linePath.lineTo(offsets[i].dx, offsets[i].dy);
      }

      fillPath
        ..lineTo(offsets.last.dx, size.height)
        ..close();

      final fillPaint = Paint()
        ..color = lineColor.withValues(alpha: 0.16)
        ..style = PaintingStyle.fill;
      canvas.drawPath(fillPath, fillPaint);

      final linePaint = Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(linePath, linePaint);
    } else {
      canvas.drawCircle(offsets.first, 4, Paint()..color = lineColor);
    }

    if (scrubIndex != null && scrubIndex! < offsets.length) {
      final pt = offsets[scrubIndex!];
      final cursorPaint = Paint()
        ..color = lineColor.withValues(alpha: 0.6)
        ..strokeWidth = 1.5;
      canvas.drawLine(
        Offset(pt.dx, 0),
        Offset(pt.dx, size.height),
        cursorPaint,
      );
      canvas.drawCircle(pt, 5, Paint()..color = haloColor);
      canvas.drawCircle(pt, 3.5, Paint()..color = lineColor);
    }
  }

  @override
  bool shouldRepaint(covariant _ChannelLinePainter oldDelegate) {
    return oldDelegate.samples != samples ||
        oldDelegate.scrubIndex != scrubIndex ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.haloColor != haloColor;
  }
}
