import 'package:flutter/material.dart';

import 'activity_formatters.dart';

/// Shows the minimal Settings bottom sheet for display units and app theme.
Future<void> showSettingsSheet(
  BuildContext context, {
  required UnitSystem initialUnitSystem,
  required ThemeMode initialThemeMode,
  required ValueChanged<UnitSystem> onUnitSystemChanged,
  required ValueChanged<ThemeMode> onThemeModeChanged,
}) {
  var unitSystem = initialUnitSystem;
  var themeMode = initialThemeMode;

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (context, setSheetState) {
          final textTheme = Theme.of(context).textTheme;
          final colors = Theme.of(context).colorScheme;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Settings', style: textTheme.titleLarge),
                  const SizedBox(height: 16),
                  Text('Display Units', style: textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    unitSystem == UnitSystem.metric
                        ? 'km, m, min/km'
                        : 'mi, ft, min/mi',
                    style: textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<UnitSystem>(
                    key: const Key('settings-units-selector'),
                    segments: const [
                      ButtonSegment<UnitSystem>(
                        value: UnitSystem.metric,
                        label: Text('Metric'),
                      ),
                      ButtonSegment<UnitSystem>(
                        value: UnitSystem.imperial,
                        label: Text('Imperial'),
                      ),
                    ],
                    selected: {unitSystem},
                    onSelectionChanged: (selection) {
                      if (selection.isEmpty) return;
                      final next = selection.first;
                      setSheetState(() => unitSystem = next);
                      onUnitSystemChanged(next);
                    },
                  ),
                  const SizedBox(height: 20),
                  Text('Theme', style: textTheme.titleSmall),
                  const SizedBox(height: 8),
                  SegmentedButton<ThemeMode>(
                    key: const Key('settings-theme-selector'),
                    segments: const [
                      ButtonSegment<ThemeMode>(
                        value: ThemeMode.system,
                        label: Text('System'),
                      ),
                      ButtonSegment<ThemeMode>(
                        value: ThemeMode.light,
                        label: Text('Light'),
                      ),
                      ButtonSegment<ThemeMode>(
                        value: ThemeMode.dark,
                        label: Text('Dark'),
                      ),
                    ],
                    selected: {themeMode},
                    onSelectionChanged: (selection) {
                      if (selection.isEmpty) return;
                      final next = selection.first;
                      setSheetState(() => themeMode = next);
                      onThemeModeChanged(next);
                    },
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
