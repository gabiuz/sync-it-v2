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

    final effectiveDistance = gpsDistance > 0
        ? gpsDistance
        : (points.last.cumulativeDistanceMeters ?? 0.0);

    final avgPace = (effectiveDistance > 0 && duration.inMilliseconds > 0)
        ? (duration.inMilliseconds / 1000.0) / (effectiveDistance / 1000.0)
        : null;

    return ActivitySummary(
      trackpointCount: points.length,
      startTime: startTime,
      endTime: endTime,
      duration: duration,
      gpsDistanceMeters: effectiveDistance,
      elevationGainMeters: elevationGain,
      avgHeartRateBpm: hrCount > 0 ? (hrSum / hrCount).round() : null,
      maxHeartRateBpm: hrCount > 0 ? hrMax : null,
      avgPaceSecondsPerKm: avgPace,
      calories: activity.calories,
      deviceInfo: activity.deviceInfo,
      lapCount: activity.laps.isEmpty ? 1 : activity.laps.length,
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

  static const double metersPerMile = 1609.344;
  static const double metersPerKm = 1000.0;
  static const double _milestoneProximityTolerance = 0.02;

  /// Computes 2D Haversine GPS distance, recorded cumulative distance,
  /// Strava Tax, and floor-truncation milestone diagnostics.
  static DistanceDiagnostics analyzeDistance(
    Activity activity, {
    required bool isImperial,
    double? distanceOverrideMeters,
  }) {
    final points = activity.trackpoints;
    var gpsDistance = 0.0;
    Trackpoint? prevGps;
    double? recordedDistance;

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
      if (pt.cumulativeDistanceMeters != null) {
        recordedDistance = pt.cumulativeDistanceMeters;
      }
    }

    if (recordedDistance == null &&
        activity.availableChannels.contains(Channel.distance) &&
        activity.laps.isNotEmpty) {
      var lapSum = 0.0;
      var hasLapDist = false;
      for (final lap in activity.laps) {
        if (lap.distanceMeters != null) {
          lapSum += lap.distanceMeters!;
          hasLapDist = true;
        }
      }
      if (hasLapDist) recordedDistance = lapSum;
    }

    final effectiveDistance =
        distanceOverrideMeters ?? recordedDistance ?? gpsDistance;
    final stravaTax = (gpsDistance > 0 && (recordedDistance != null || distanceOverrideMeters != null))
        ? effectiveDistance - gpsDistance
        : null;

    final unitMeters = isImperial ? metersPerMile : metersPerKm;
    final valueInUnit = effectiveDistance / unitMeters;
    final predictedFloored = ((valueInUnit * 100.0) + 1e-9).floor() / 100.0;

    // Check if floor truncation drops a half-unit or whole-unit milestone
    // (e.g., 9.998 km -> 9.99 km instead of 10.00 km, or 4.995 -> 4.99 instead of 5.00).
    var dropsMilestone = false;
    double? nudgeDisplay;
    double? nudgeMeters;

    if (valueInUnit > 0) {
      final nextMilestone = ((valueInUnit * 2.0) - 1e-9).ceil() / 2.0;
      if (nextMilestone > predictedFloored &&
          (nextMilestone - valueInUnit) <= _milestoneProximityTolerance) {
        dropsMilestone = true;
        nudgeDisplay = double.parse(nextMilestone.toStringAsFixed(2));
        nudgeMeters = nudgeDisplay * unitMeters;
      }
    }

    return DistanceDiagnostics(
      gpsDistanceMeters: gpsDistance,
      recordedDistanceMeters: recordedDistance,
      effectiveDistanceMeters: effectiveDistance,
      stravaTaxMeters: stravaTax,
      predictedStravaDisplayValue: predictedFloored,
      isImperial: isImperial,
      dropsMilestone: dropsMilestone,
      nudgeTargetMeters: nudgeMeters,
      nudgeTargetDisplayValue: nudgeDisplay,
    );
  }

  /// Returns a new [Activity] with cumulative distances proportionally scaled to
  /// [targetDistanceMeters] and all [Lap] distances recomputed, without mutating
  /// the input [activity]. If [targetDistanceMeters] is `null`, returns [activity].
  static Activity applyDistanceOverride(
    Activity activity,
    double? targetDistanceMeters,
  ) {
    if (targetDistanceMeters == null) return activity;
    final points = activity.trackpoints;
    if (points.isEmpty) return activity;

    final safeTarget = math.max(0.0, targetDistanceMeters);
    final baseDistances = List<double>.filled(points.length, 0.0);
    var cumulative = 0.0;
    Trackpoint? prevGps;

    for (var i = 0; i < points.length; i++) {
      final pt = points[i];
      if (pt.latitude != null && pt.longitude != null) {
        if (prevGps != null) {
          cumulative += haversineMeters(
            prevGps.latitude!,
            prevGps.longitude!,
            pt.latitude!,
            pt.longitude!,
          );
        }
        prevGps = pt;
      }
      if (pt.cumulativeDistanceMeters != null) {
        cumulative = math.max(cumulative, pt.cumulativeDistanceMeters!);
      }
      baseDistances[i] =
          pt.cumulativeDistanceMeters ?? cumulative;
    }

    final baseTotal = baseDistances.last;
    final totalDurationMs =
        points.last.timestamp.difference(points.first.timestamp).inMilliseconds;

    final scaledPoints = <Trackpoint>[];
    for (var i = 0; i < points.length; i++) {
      final pt = points[i];
      double scaledDist;
      if (i == points.length - 1) {
        scaledDist = safeTarget;
      } else if (baseTotal > 0) {
        scaledDist = baseDistances[i] * (safeTarget / baseTotal);
      } else if (totalDurationMs > 0) {
        final elapsedMs =
            pt.timestamp.difference(points.first.timestamp).inMilliseconds;
        scaledDist = safeTarget * (elapsedMs / totalDurationMs);
      } else if (points.length > 1) {
        scaledDist = safeTarget * (i / (points.length - 1));
      } else {
        scaledDist = safeTarget;
      }

      scaledPoints.add(
        Trackpoint(
          timestamp: pt.timestamp,
          latitude: pt.latitude,
          longitude: pt.longitude,
          elevationMeters: pt.elevationMeters,
          cumulativeDistanceMeters: scaledDist,
          heartRateBpm: pt.heartRateBpm,
          cadenceRpm: pt.cadenceRpm,
          powerWatts: pt.powerWatts,
          temperatureCelsius: pt.temperatureCelsius,
        ),
      );
    }

    final scaledLaps = <Lap>[];
    if (activity.laps.isNotEmpty) {
      var prevLapEndDist = 0.0;
      for (var i = 0; i < activity.laps.length; i++) {
        final lap = activity.laps[i];
        Trackpoint? lastInLap;
        for (final pt in scaledPoints) {
          final afterStart = i == 0
              ? !pt.timestamp.isBefore(lap.startTime)
              : pt.timestamp.isAfter(lap.startTime);
          if (afterStart && !pt.timestamp.isAfter(lap.endTime)) {
            lastInLap = pt;
          }
        }
        final endDist = lastInLap?.cumulativeDistanceMeters ?? prevLapEndDist;
        final lapDist = math.max(0.0, endDist - prevLapEndDist);
        prevLapEndDist = endDist;
        scaledLaps.add(
          Lap(
            startTime: lap.startTime,
            endTime: lap.endTime,
            distanceMeters: lapDist,
            avgHeartRateBpm: lap.avgHeartRateBpm,
            maxHeartRateBpm: lap.maxHeartRateBpm,
            avgCadenceRpm: lap.avgCadenceRpm,
            maxCadenceRpm: lap.maxCadenceRpm,
            calories: lap.calories,
          ),
        );
      }
    }

    return activity.copyWith(
      trackpoints: scaledPoints,
      laps: scaledLaps,
      availableChannels: {
        ...activity.availableChannels,
        Channel.distance,
      },
    );
  }
}
