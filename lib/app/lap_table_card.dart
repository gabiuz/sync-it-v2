import 'package:flutter/material.dart';

import '../core/core_engine.dart';
import 'activity_formatters.dart';

/// Structured Lap breakdown table showing per-Lap distance, duration, pace,
/// and average heart rate.
class LapTableCard extends StatelessWidget {
  const LapTableCard({
    super.key,
    required this.laps,
    this.unitSystem = UnitSystem.metric,
  });

  final List<Lap> laps;
  final UnitSystem unitSystem;

  @override
  Widget build(BuildContext context) {
    if (laps.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final headerStyle = theme.textTheme.labelMedium?.copyWith(
      color: colors.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );

    return Card(
      key: const Key('lap-breakdown-table'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Lap Breakdown',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 10),
            Table(
              columnWidths: const {
                0: FlexColumnWidth(1.0),
                1: FlexColumnWidth(1.6),
                2: FlexColumnWidth(1.5),
                3: FlexColumnWidth(1.7),
                4: FlexColumnWidth(1.5),
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                TableRow(
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: colors.outlineVariant),
                    ),
                  ),
                  children: [
                    _headerCell('Lap', headerStyle),
                    _headerCell('Distance', headerStyle, alignRight: true),
                    _headerCell('Duration', headerStyle, alignRight: true),
                    _headerCell('Pace', headerStyle, alignRight: true),
                    _headerCell('Avg HR', headerStyle, alignRight: true),
                  ],
                ),
                for (var i = 0; i < laps.length; i++)
                  _buildLapRow(context, i + 1, laps[i], colors),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerCell(
    String text,
    TextStyle? style, {
    bool alignRight = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(
        text,
        style: style,
        textAlign: alignRight ? TextAlign.right : TextAlign.left,
      ),
    );
  }

  TableRow _buildLapRow(
    BuildContext context,
    int index,
    Lap lap,
    ColorScheme colors,
  ) {
    final dist = lap.distanceMeters;
    final distText =
        dist != null ? formatDistance(dist, units: unitSystem) : '—';
    final durText = formatDuration(lap.duration);
    final paceText = (dist != null && dist > 0 && lap.duration.inSeconds > 0)
        ? formatPace(
            lap.duration.inMilliseconds / 1000.0 / (dist / 1000.0),
            units: unitSystem,
          )
        : '—';
    final hrText =
        lap.avgHeartRateBpm != null ? '${lap.avgHeartRateBpm} bpm' : '—';

    final cellStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w500,
        );

    return TableRow(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: colors.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text('Lap $index', style: cellStyle),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(distText, style: cellStyle, textAlign: TextAlign.right),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(durText, style: cellStyle, textAlign: TextAlign.right),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(paceText, style: cellStyle, textAlign: TextAlign.right),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(hrText, style: cellStyle, textAlign: TextAlign.right),
        ),
      ],
    );
  }
}
