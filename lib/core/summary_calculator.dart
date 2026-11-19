import 'dart:math' as math;

import 'models.dart';

/// Computes canonical [ActivitySummary] metrics from an [Activity].
class SummaryCalculator {
  const SummaryCalculator._();

  static const double _earthRadiusMeters = 6371000.0;

  static ActivitySummary compute(Activity activity) {
    final points = activity.trackpoints;
    if (points.isEmpty) {
      final now = DateTime.now().toUtc();
      return ActivitySummary(
        trackpointCount: 0,
        startTime: now,
        endTime: now,
        duration: Duration.zero,
        gpsDistanceMeters: 0,
        elevationGainMeters: 0,
      );
    }

    final startTime = points.first.timestamp;
    final endTime = points.last.timestamp;
    final duration = endTime.isAfter(startTime)
        ? endTime.difference(startTime)
        : Duration.zero;

    var gpsDistance = 0.0;
    var elevationGain = 0.0;
    var hrSum = 0;
    var hrCount = 0;
    var hrMax = 0;

    Trackpoint? prevGps;
    double? prevEle;

    for (final pt in points) {
      if (pt.latitude != null && pt.longitude != null) {
        if (prevGps != null) {
          gpsDistance += haversineMeters(
            prevGps.latitude!,
            prevGps.longitude!,
            pt.latitude!,
            pt.longitude!,
          );
        }
        prevGps = pt;
      }

      if (pt.elevationMeters != null) {
        if (prevEle != null && pt.elevationMeters! > prevEle) {
          elevationGain += pt.elevationMeters! - prevEle;
        }
        prevEle = pt.elevationMeters!;
      }

      final hr = pt.heartRateBpm;
      if (hr != null && hr > 0) {
        hrSum += hr;
        hrCount++;
        if (hr > hrMax) hrMax = hr;
      }
    }

    final avgPace = (gpsDistance > 0 && duration.inMilliseconds > 0)
        ? (duration.inMilliseconds / 1000.0) / (gpsDistance / 1000.0)
        : null;

    return ActivitySummary(
      trackpointCount: points.length,
      startTime: startTime,
      endTime: endTime,
      duration: duration,
      gpsDistanceMeters: gpsDistance,
      elevationGainMeters: elevationGain,
      avgHeartRateBpm: hrCount > 0 ? (hrSum / hrCount).round() : null,
      maxHeartRateBpm: hrCount > 0 ? hrMax : null,
      avgPaceSecondsPerKm: avgPace,
    );
  }

  static double haversineMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final rLat1 = _toRadians(lat1);
    final rLat2 = _toRadians(lat2);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(rLat1) *
            math.cos(rLat2) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return _earthRadiusMeters * c;
  }

  static double _toRadians(double degrees) => degrees * (math.pi / 180.0);
}
