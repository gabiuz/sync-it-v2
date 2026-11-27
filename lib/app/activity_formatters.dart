/// Display unit system for distances, elevations, and paces.
enum UnitSystem {
  metric,
  imperial,
}

const double _metersPerMile = 1609.344;
const double _feetPerMeter = 3.28084;

/// Shared display formatters for Activity metrics in the UI layer.
String formatDuration(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}

/// Formats distance in meters as `X.XX km` or `X.XX mi`.
String formatDistance(
  double meters, {
  UnitSystem units = UnitSystem.metric,
}) {
  if (units == UnitSystem.imperial) {
    return '${(meters / _metersPerMile).toStringAsFixed(2)} mi';
  }
  return '${(meters / 1000.0).toStringAsFixed(2)} km';
}

/// Formats distance in meters with 3 decimal places (`X.XXX km` or `X.XXX mi`)
/// so fractional Strava Tax differences remain visible.
String formatPreciseDistance(
  double meters, {
  UnitSystem units = UnitSystem.metric,
}) {
  if (units == UnitSystem.imperial) {
    return '${(meters / _metersPerMile).toStringAsFixed(3)} mi';
  }
  return '${(meters / 1000.0).toStringAsFixed(3)} km';
}

/// Returns the unit suffix (`km` or `mi`) for [units].
String distanceUnitLabel(UnitSystem units) =>
    units == UnitSystem.imperial ? 'mi' : 'km';

/// Converts [meters] into a numeric string in [units] for form inputs.
String formatDistanceInput(
  double meters, {
  UnitSystem units = UnitSystem.metric,
}) {
  final value =
      units == UnitSystem.imperial ? meters / _metersPerMile : meters / 1000.0;
  return value.toStringAsFixed(2);
}

/// Parses a user-entered distance in [units] into meters, or `null` if empty
/// or not a positive finite number.
double? parseDistanceOverrideMeters(
  String raw, {
  required UnitSystem units,
}) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final parsed = double.tryParse(trimmed);
  if (parsed == null || !parsed.isFinite || parsed <= 0) return null;
  return units == UnitSystem.imperial ? parsed * _metersPerMile : parsed * 1000.0;
}

/// Formats elevation in meters as `X m` or `X ft`.
String formatElevation(
  double meters, {
  UnitSystem units = UnitSystem.metric,
}) {
  if (units == UnitSystem.imperial) {
    return '${(meters * _feetPerMeter).round()} ft';
  }
  return '${meters.toStringAsFixed(0)} m';
}

/// Formats pace in seconds per kilometer as `M:SS /km` or `M:SS /mi`.
String formatPace(
  double secondsPerKm, {
  UnitSystem units = UnitSystem.metric,
}) {
  final scaled =
      units == UnitSystem.imperial ? secondsPerKm * 1.609344 : secondsPerKm;
  final totalSeconds = scaled.round();
  final mins = totalSeconds ~/ 60;
  final secs = (totalSeconds % 60).toString().padLeft(2, '0');
  final suffix = units == UnitSystem.imperial ? '/mi' : '/km';
  return '$mins:$secs $suffix';
}

/// Builds a clean, filesystem-safe default Export File name from [startTime]
/// and [title], e.g. `2026-11-19_evening_jog.fit`.
String buildSmartExportFileName({
  required DateTime startTime,
  required String title,
  required String extension,
}) {
  final utc = startTime.toUtc();
  final yyyy = utc.year.toString().padLeft(4, '0');
  final mm = utc.month.toString().padLeft(2, '0');
  final dd = utc.day.toString().padLeft(2, '0');
  final slug = title
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  final base = slug.isEmpty ? 'activity' : slug;
  return '$yyyy-$mm-${dd}_$base.$extension';
}

/// Sanitizes a user-edited Export File name and ensures it ends with
/// `.[extension]`, falling back to [fallback] if the stem is empty.
String sanitizeExportFileName(
  String raw, {
  required String extension,
  required String fallback,
}) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return fallback;

  final withoutExt = trimmed.replaceFirst(
    RegExp(r'\.(fit|gpx|tcx|kml)$', caseSensitive: false),
    '',
  );
  final safeStem = withoutExt
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '')
      .trim();
  if (safeStem.isEmpty) return fallback;
  return '$safeStem.$extension';
}
