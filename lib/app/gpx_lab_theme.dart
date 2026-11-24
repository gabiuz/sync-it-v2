import 'package:flutter/material.dart';

/// Harmonized semantic accents for route maps and **Channel** charts across
/// light and dark cool-slate surfaces.
@immutable
class GpxLabBrandColors extends ThemeExtension<GpxLabBrandColors> {
  const GpxLabBrandColors({
    required this.routeLine,
    required this.routeStart,
    required this.routeEnd,
    required this.heartRate,
    required this.elevation,
    required this.pace,
    required this.markerHalo,
  });

  final Color routeLine;
  final Color routeStart;
  final Color routeEnd;
  final Color heartRate;
  final Color elevation;
  final Color pace;
  final Color markerHalo;

  static const GpxLabBrandColors light = GpxLabBrandColors(
    routeLine: Color(0xFF1D63ED),
    routeStart: Color(0xFF10B981),
    routeEnd: Color(0xFFE11D48),
    heartRate: Color(0xFFE5484D),
    elevation: Color(0xFF0D9488),
    pace: Color(0xFF0284C7),
    markerHalo: Color(0xFFFFFFFF),
  );

  static const GpxLabBrandColors dark = GpxLabBrandColors(
    routeLine: Color(0xFF38BDF8),
    routeStart: Color(0xFF34D399),
    routeEnd: Color(0xFFFB7185),
    heartRate: Color(0xFFFF6B6B),
    elevation: Color(0xFF2DD4BF),
    pace: Color(0xFF60A5FA),
    markerHalo: Color(0xFFF8FAFC),
  );

  static GpxLabBrandColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<GpxLabBrandColors>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

  @override
  GpxLabBrandColors copyWith({
    Color? routeLine,
    Color? routeStart,
    Color? routeEnd,
    Color? heartRate,
    Color? elevation,
    Color? pace,
    Color? markerHalo,
  }) {
    return GpxLabBrandColors(
      routeLine: routeLine ?? this.routeLine,
      routeStart: routeStart ?? this.routeStart,
      routeEnd: routeEnd ?? this.routeEnd,
      heartRate: heartRate ?? this.heartRate,
      elevation: elevation ?? this.elevation,
      pace: pace ?? this.pace,
      markerHalo: markerHalo ?? this.markerHalo,
    );
  }

  @override
  GpxLabBrandColors lerp(
    covariant ThemeExtension<GpxLabBrandColors>? other,
    double t,
  ) {
    if (other is! GpxLabBrandColors) return this;
    return GpxLabBrandColors(
      routeLine: Color.lerp(routeLine, other.routeLine, t)!,
      routeStart: Color.lerp(routeStart, other.routeStart, t)!,
      routeEnd: Color.lerp(routeEnd, other.routeEnd, t)!,
      heartRate: Color.lerp(heartRate, other.heartRate, t)!,
      elevation: Color.lerp(elevation, other.elevation, t)!,
      pace: Color.lerp(pace, other.pace, t)!,
      markerHalo: Color.lerp(markerHalo, other.markerHalo, t)!,
    );
  }
}

/// Centralized branding and athletic cobalt-blue Material 3 theme definitions
/// for **GPX Lab**.
///
/// When the custom brand mark, character/persona, or refined hex arrives,
/// update [seedColor] (and [GpxLabBrandColors]) in this single module.
abstract final class GpxLabTheme {
  static const String appName = 'GPX Lab';
  static const String appTagline =
      'Offline activity file workbench. Inspect, edit, and export clean FIT, TCX, or GPX files before uploading.';
  static const String osmUserAgentPackage = 'com.gabiuz.gpxlab';

  /// Athletic cobalt-blue brand seed (`#1D63ED`).
  static const Color seedColor = Color(0xFF1D63ED);

  static ThemeData light({Color seedColor = GpxLabTheme.seedColor}) {
    final baseScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.light,
    );
    final isDefaultSeed = seedColor == GpxLabTheme.seedColor;
    final colorScheme = baseScheme.copyWith(
      primary: isDefaultSeed ? GpxLabTheme.seedColor : baseScheme.primary,
      onPrimary: isDefaultSeed ? const Color(0xFFFFFFFF) : baseScheme.onPrimary,
      surface: const Color(0xFFF8FAFC),
      onSurface: const Color(0xFF0F172A),
      onSurfaceVariant: const Color(0xFF475569),
      surfaceContainerLowest: const Color(0xFFFFFFFF),
      surfaceContainerLow: const Color(0xFFF1F5F9),
      surfaceContainer: const Color(0xFFEAF0F6),
      surfaceContainerHigh: const Color(0xFFE2E8F0),
      surfaceContainerHighest: const Color(0xFFD8E1EB),
      outline: const Color(0xFF64748B),
      outlineVariant: const Color(0xFFCBD5E1),
    );
    return _buildTheme(
      brightness: Brightness.light,
      seedColor: seedColor,
      colorScheme: colorScheme,
      defaultBrandColors: GpxLabBrandColors.light,
    );
  }

  static ThemeData dark({Color seedColor = GpxLabTheme.seedColor}) {
    final baseScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.dark,
    );
    final colorScheme = baseScheme.copyWith(
      surface: const Color(0xFF0B1120),
      onSurface: const Color(0xFFF1F5F9),
      onSurfaceVariant: const Color(0xFF94A3B8),
      surfaceContainerLowest: const Color(0xFF070B14),
      surfaceContainerLow: const Color(0xFF111827),
      surfaceContainer: const Color(0xFF162032),
      surfaceContainerHigh: const Color(0xFF1E293B),
      surfaceContainerHighest: const Color(0xFF283548),
      outline: const Color(0xFF64748B),
      outlineVariant: const Color(0xFF334155),
    );
    return _buildTheme(
      brightness: Brightness.dark,
      seedColor: seedColor,
      colorScheme: colorScheme,
      defaultBrandColors: GpxLabBrandColors.dark,
    );
  }

  static ThemeData _buildTheme({
    required Brightness brightness,
    required Color seedColor,
    required ColorScheme colorScheme,
    required GpxLabBrandColors defaultBrandColors,
  }) {
    final brandColors = seedColor == GpxLabTheme.seedColor
        ? defaultBrandColors
        : defaultBrandColors.copyWith(routeLine: colorScheme.primary);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      extensions: <ThemeExtension<dynamic>>[brandColors],
    );
  }
}
