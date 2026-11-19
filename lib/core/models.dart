import 'dart:typed_data';

/// Telemetry series available on an [Activity] or [Trackpoint].
enum Channel {
  gps,
  elevation,
  distance,
  heartRate,
  cadence,
  power,
  temperature,
}

/// Supported Export File formats.
enum ExportFormat {
  fit('fit', 'FIT'),
  gpx('gpx', 'GPX 1.1'),
  tcx('tcx', 'TCX 2.0');

  const ExportFormat(this.extension, this.displayName);

  final String extension;
  final String displayName;
}

/// Canonical sport classification mapped across GPX/TCX/FIT.
enum SportType {
  running('running', 'Running', 'Running'),
  cycling('cycling', 'Biking', 'Cycling'),
  walking('walking', 'Walking', 'Walking'),
  hiking('hiking', 'Hiking', 'Hiking'),
  swimming('swimming', 'Swimming', 'Swimming'),
  other('other', 'Other', 'Other');

  const SportType(this.gpxName, this.tcxName, this.displayName);

  final String gpxName;
  final String tcxName;
  final String displayName;

  static SportType fromGpxType(String? raw) {
    if (raw == null || raw.trim().isEmpty) return SportType.other;
    final normalized = raw.trim().toLowerCase();
    for (final sport in SportType.values) {
      if (sport.gpxName == normalized ||
          sport.tcxName.toLowerCase() == normalized ||
          sport.displayName.toLowerCase() == normalized) {
        return sport;
      }
    }
    if (normalized.contains('run')) return SportType.running;
    if (normalized.contains('cycl') || normalized.contains('bik')) {
      return SportType.cycling;
    }
    if (normalized.contains('walk')) return SportType.walking;
    if (normalized.contains('hik')) return SportType.hiking;
    if (normalized.contains('swim')) return SportType.swimming;
    return SportType.other;
  }

  static SportType fromTcxSport(String? raw) => fromGpxType(raw);
}

/// Severity of a defensive-parsing or export [Diagnostic].
enum DiagnosticSeverity {
  info,
  warning,
}

/// Machine-identifiable diagnostic code for UI banners and tests.
enum DiagnosticCode {
  duplicateTimestampsNormalized,
  outOfOrderTrackpointsSorted,
  zeroHeartRateDropped,
  unsupportedExtensionsDropped,
  missingFirstPointDistanceNormalized,
}

/// Non-fatal notice surfaced to the user after parsing or exporting.
class Diagnostic {
  const Diagnostic({
    required this.code,
    required this.severity,
    required this.message,
    this.count = 1,
  });

  final DiagnosticCode code;
  final DiagnosticSeverity severity;
  final String message;
  final int count;
}

/// A single timestamped sample along an [Activity]'s timeline.
class Trackpoint {
  const Trackpoint({
    required this.timestamp,
    this.latitude,
    this.longitude,
    this.elevationMeters,
    this.cumulativeDistanceMeters,
    this.heartRateBpm,
    this.cadenceRpm,
    this.powerWatts,
    this.temperatureCelsius,
  });

  final DateTime timestamp;
  final double? latitude;
  final double? longitude;
  final double? elevationMeters;
  final double? cumulativeDistanceMeters;
  final int? heartRateBpm;
  final int? cadenceRpm;
  final int? powerWatts;
  final int? temperatureCelsius;
}

/// A contiguous time-bounded interval within an [Activity].
class Lap {
  const Lap({
    required this.startTime,
    required this.endTime,
    this.distanceMeters,
    this.avgHeartRateBpm,
    this.maxHeartRateBpm,
    this.avgCadenceRpm,
    this.maxCadenceRpm,
    this.calories,
  });

  final DateTime startTime;
  final DateTime endTime;
  final double? distanceMeters;
  final int? avgHeartRateBpm;
  final int? maxHeartRateBpm;
  final int? avgCadenceRpm;
  final int? maxCadenceRpm;
  final int? calories;

  Duration get duration => endTime.isAfter(startTime)
      ? endTime.difference(startTime)
      : Duration.zero;
}

/// Format-independent representation of a single workout.
class Activity {
  const Activity({
    required this.title,
    required this.description,
    required this.sportType,
    required this.trackpoints,
    required this.laps,
    required this.availableChannels,
    this.calories,
    this.deviceInfo,
  });

  final String title;
  final String description;
  final SportType sportType;
  final List<Trackpoint> trackpoints;
  final List<Lap> laps;
  final Set<Channel> availableChannels;
  final int? calories;
  final String? deviceInfo;

  Activity copyWith({
    String? title,
    String? description,
    SportType? sportType,
    List<Trackpoint>? trackpoints,
    List<Lap>? laps,
    Set<Channel>? availableChannels,
    int? calories,
    String? deviceInfo,
  }) {
    return Activity(
      title: title ?? this.title,
      description: description ?? this.description,
      sportType: sportType ?? this.sportType,
      trackpoints: trackpoints ?? this.trackpoints,
      laps: laps ?? this.laps,
      availableChannels: availableChannels ?? this.availableChannels,
      calories: calories ?? this.calories,
      deviceInfo: deviceInfo ?? this.deviceInfo,
    );
  }
}

/// Computed summary statistics for an [Activity].
class ActivitySummary {
  const ActivitySummary({
    required this.trackpointCount,
    required this.startTime,
    required this.endTime,
    required this.duration,
    required this.gpsDistanceMeters,
    required this.elevationGainMeters,
    this.avgHeartRateBpm,
    this.maxHeartRateBpm,
    this.avgPaceSecondsPerKm,
    this.calories,
    this.deviceInfo,
    this.lapCount = 1,
  });

  final int trackpointCount;
  final DateTime startTime;
  final DateTime endTime;
  final Duration duration;
  final double gpsDistanceMeters;
  final double elevationGainMeters;
  final int? avgHeartRateBpm;
  final int? maxHeartRateBpm;
  final double? avgPaceSecondsPerKm;
  final int? calories;
  final String? deviceInfo;
  final int lapCount;
}

/// Strava Tax and floor-truncation diagnostics for an [Activity].
class DistanceDiagnostics {
  const DistanceDiagnostics({
    required this.gpsDistanceMeters,
    required this.recordedDistanceMeters,
    required this.effectiveDistanceMeters,
    required this.stravaTaxMeters,
    required this.predictedStravaDisplayValue,
    required this.isImperial,
    required this.dropsMilestone,
    this.nudgeTargetMeters,
    this.nudgeTargetDisplayValue,
  });

  final double gpsDistanceMeters;
  final double? recordedDistanceMeters;
  final double effectiveDistanceMeters;
  final double? stravaTaxMeters;
  final double predictedStravaDisplayValue;
  final bool isImperial;
  final bool dropsMilestone;
  final double? nudgeTargetMeters;
  final double? nudgeTargetDisplayValue;
}

/// User edits applied when producing an Export File.
class ActivityEdit {
  const ActivityEdit({
    this.title,
    this.description,
    this.sportType,
    this.distanceOverrideMeters,
  });

  final String? title;
  final String? description;
  final SportType? sportType;
  final double? distanceOverrideMeters;
}

/// Result returned by parsing a Source File.
class ParseResult {
  const ParseResult({
    required this.activity,
    required this.summary,
    required this.diagnostics,
  });

  final Activity activity;
  final ActivitySummary summary;
  final List<Diagnostic> diagnostics;
}

/// Result returned by serializing an Export File.
class ExportResult {
  const ExportResult({
    required this.bytes,
    required this.activity,
    required this.summary,
    required this.diagnostics,
  });

  final Uint8List bytes;
  final Activity activity;
  final ActivitySummary summary;
  final List<Diagnostic> diagnostics;
}

/// Actionable error thrown when a Source File cannot be parsed.
class ActivityParseException implements Exception {
  const ActivityParseException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A 2D geographic coordinate for map display.
class GeoPoint {
  const GeoPoint({
    required this.latitude,
    required this.longitude,
  });

  final double latitude;
  final double longitude;
}

/// A single downsampled sample for a Channel chart.
class ChartSample {
  const ChartSample({
    required this.elapsedSeconds,
    required this.distanceMeters,
    required this.value,
  });

  final double elapsedSeconds;
  final double distanceMeters;
  final double value;
}

/// Downsampled display geometry for smooth map and chart rendering.
class ActivityDisplayGeometry {
  const ActivityDisplayGeometry({
    required this.routePoints,
    required this.heartRateSeries,
    required this.elevationSeries,
    required this.paceSeries,
    required this.sourceTrackpointCount,
  });

  final List<GeoPoint> routePoints;
  final List<ChartSample> heartRateSeries;
  final List<ChartSample> elevationSeries;
  final List<ChartSample> paceSeries;
  final int sourceTrackpointCount;
}
