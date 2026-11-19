import 'models.dart';
import 'summary_calculator.dart';

/// Builds downsampled [ActivityDisplayGeometry] from a canonical [Activity].
class DisplayGeometryBuilder {
  const DisplayGeometryBuilder._();

  static const int defaultMaxPoints = 1000;
  static const double _minPaceSecondsPerKm = 60.0;
  static const double _maxPaceSecondsPerKm = 1800.0;

  static ActivityDisplayGeometry build(
    Activity activity, {
    int maxPoints = defaultMaxPoints,
  }) {
    final points = activity.trackpoints;
    if (points.isEmpty) {
      return const ActivityDisplayGeometry(
        routePoints: [],
        heartRateSeries: [],
        elevationSeries: [],
        paceSeries: [],
        sourceTrackpointCount: 0,
      );
    }

    final limit = maxPoints < 2 ? 2 : maxPoints;
    final startTime = points.first.timestamp;

    final rawRoute = <GeoPoint>[];
    final rawHr = <ChartSample>[];
    final rawEle = <ChartSample>[];
    final rawPace = <ChartSample>[];

    var accumulatedDistance = 0.0;
    Trackpoint? prevGps;
    Trackpoint? prevPacePt;
    double? prevPaceDist;

    for (final pt in points) {
      final elapsedSeconds =
          pt.timestamp.difference(startTime).inMilliseconds / 1000.0;

      if (pt.latitude != null && pt.longitude != null) {
        rawRoute.add(
          GeoPoint(latitude: pt.latitude!, longitude: pt.longitude!),
        );
        if (prevGps != null) {
          accumulatedDistance += SummaryCalculator.haversineMeters(
            prevGps.latitude!,
            prevGps.longitude!,
            pt.latitude!,
            pt.longitude!,
          );
        }
        prevGps = pt;
      }

      final dist = pt.cumulativeDistanceMeters ?? accumulatedDistance;

      final hr = pt.heartRateBpm;
      if (hr != null && hr > 0) {
        rawHr.add(
          ChartSample(
            elapsedSeconds: elapsedSeconds,
            distanceMeters: dist,
            value: hr.toDouble(),
          ),
        );
      }

      if (pt.elevationMeters != null) {
        rawEle.add(
          ChartSample(
            elapsedSeconds: elapsedSeconds,
            distanceMeters: dist,
            value: pt.elevationMeters!,
          ),
        );
      }

      if (prevPacePt != null && prevPaceDist != null) {
        final dtSec =
            pt.timestamp.difference(prevPacePt.timestamp).inMilliseconds /
                1000.0;
        final ddMeters = dist - prevPaceDist;
        if (dtSec >= 1.0 && ddMeters >= 0.5) {
          final paceSecPerKm = dtSec / (ddMeters / 1000.0);
          if (paceSecPerKm >= _minPaceSecondsPerKm &&
              paceSecPerKm <= _maxPaceSecondsPerKm) {
            rawPace.add(
              ChartSample(
                elapsedSeconds: elapsedSeconds,
                distanceMeters: dist,
                value: paceSecPerKm,
              ),
            );
            prevPacePt = pt;
            prevPaceDist = dist;
          }
        }
      } else {
        prevPacePt = pt;
        prevPaceDist = dist;
      }
    }

    return ActivityDisplayGeometry(
      routePoints: _downsample(rawRoute, limit),
      heartRateSeries: _downsample(rawHr, limit),
      elevationSeries: _downsample(rawEle, limit),
      paceSeries: _downsample(rawPace, limit),
      sourceTrackpointCount: points.length,
    );
  }

  /// Uniformly downsamples [items] to at most [maxPoints], always preserving
  /// the first and last element.
  static List<T> _downsample<T>(List<T> items, int maxPoints) {
    if (items.length <= maxPoints) {
      return List<T>.unmodifiable(items);
    }

    final result = <T>[];
    final lastIndex = items.length - 1;
    final step = lastIndex / (maxPoints - 1);

    for (var i = 0; i < maxPoints; i++) {
      final index = (i * step).round().clamp(0, lastIndex);
      result.add(items[index]);
    }
    return List<T>.unmodifiable(result);
  }
}
