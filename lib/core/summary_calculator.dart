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

    final recordedDistance = _resolveRecordedDistance(
      points,
      activity.laps,
    );
    final effectiveDistance = recordedDistance ?? gpsDistance;

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
    }

    final recordedDistance = _resolveRecordedDistance(points, activity.laps);

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

    final scaledPoints = _scalePointsByBaseDistances(
      points,
      baseDistances: baseDistances,
      startDistanceMeters: 0.0,
      targetEndMeters: safeTarget,
    );

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

  /// Proportionally distributes [spanMeters] across [points] starting from
  /// [startDistanceMeters], using 2D Haversine segments (falling back to
  /// elapsed time or sample index when GPS distance is zero). When [spanMeters]
  /// is `null`, the 2D Haversine span is used directly.
  static List<Trackpoint> distributeDistanceRange(
    List<Trackpoint> points, {
    double? spanMeters,
    double startDistanceMeters = 0.0,
    Trackpoint? precedingPoint,
  }) {
    if (points.isEmpty) return points;
    final baseDistances = List<double>.filled(points.length, 0.0);
    var cumulative = 0.0;
    Trackpoint? prevGps = (precedingPoint != null &&
            precedingPoint.latitude != null &&
            precedingPoint.longitude != null)
        ? precedingPoint
        : null;

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
      baseDistances[i] = cumulative;
    }

    final safeSpan = math.max(0.0, spanMeters ?? baseDistances.last);
    return _scalePointsByBaseDistances(
      points,
      baseDistances: baseDistances,
      startDistanceMeters: startDistanceMeters,
      targetEndMeters: startDistanceMeters + safeSpan,
      precedingPoint: precedingPoint,
    );
  }

  static double? _resolveRecordedDistance(
    List<Trackpoint> points,
    List<Lap> laps,
  ) {
    double? recordedDistance;
    for (final pt in points) {
      if (pt.cumulativeDistanceMeters != null) {
        recordedDistance = pt.cumulativeDistanceMeters;
      }
    }
    if (recordedDistance != null) return recordedDistance;

    if (laps.isNotEmpty) {
      var lapSum = 0.0;
      var hasLapDist = false;
      for (final lap in laps) {
        if (lap.distanceMeters != null) {
          lapSum += lap.distanceMeters!;
          hasLapDist = true;
        }
      }
      if (hasLapDist) return lapSum;
    }
    return null;
  }

  static List<Trackpoint> _scalePointsByBaseDistances(
    List<Trackpoint> points, {
    required List<double> baseDistances,
    required double startDistanceMeters,
    required double targetEndMeters,
    Trackpoint? precedingPoint,
  }) {
    final baseTotal = baseDistances.last;
    final span = math.max(0.0, targetEndMeters - startDistanceMeters);
    final originTime = precedingPoint?.timestamp ?? points.first.timestamp;
    final totalDurationMs =
        points.last.timestamp.difference(originTime).inMilliseconds;

    final scaledPoints = <Trackpoint>[];
    for (var i = 0; i < points.length; i++) {
      final pt = points[i];
      final double scaledDist;
      if (i == points.length - 1) {
        scaledDist = startDistanceMeters + span;
      } else if (baseTotal > 0) {
        scaledDist = startDistanceMeters + baseDistances[i] * (span / baseTotal);
      } else if (totalDurationMs > 0) {
        final elapsedMs =
            math.max(0, pt.timestamp.difference(originTime).inMilliseconds);
        scaledDist = startDistanceMeters + span * (elapsedMs / totalDurationMs);
      } else if (precedingPoint != null) {
        scaledDist = startDistanceMeters + span * ((i + 1) / points.length);
      } else if (points.length > 1) {
        scaledDist = startDistanceMeters + span * (i / (points.length - 1));
      } else {
        scaledDist = startDistanceMeters + span;
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
    return scaledPoints;
  }

  /// Applies metadata edits, Distance Override, and Channel stripping to
  /// [activity] without mutating the input.
  static Activity applyEdits(Activity activity, ActivityEdit edit) {
    final baseActivity = edit.distanceOverrideMeters != null
        ? applyDistanceOverride(activity, edit.distanceOverrideMeters)
        : activity;

    final stripped = edit.strippedChannels;
    final stripGps = stripped.contains(StrippableChannel.gps);
    final stripEle = stripped.contains(StrippableChannel.elevation);
    final stripHr = stripped.contains(StrippableChannel.heartRate);
    final stripCad = stripped.contains(StrippableChannel.cadence);
    final stripPower = stripped.contains(StrippableChannel.power);
    final stripTemp = stripped.contains(StrippableChannel.temperature);
    final stripCalories = stripped.contains(StrippableChannel.calories);
    final stripLaps = stripped.contains(StrippableChannel.laps);
    final stripDeviceInfo = stripped.contains(StrippableChannel.deviceInfo);

    var points = baseActivity.trackpoints;
    if (stripGps && points.isNotEmpty) {
      points = _ensureCumulativeDistancesBeforeGpsStrip(points);
    }

    final strippedPoints = <Trackpoint>[];
    final channels = <Channel>{};
    for (final pt in points) {
      final lat = stripGps ? null : pt.latitude;
      final lon = stripGps ? null : pt.longitude;
      final ele = stripEle ? null : pt.elevationMeters;
      final dist = pt.cumulativeDistanceMeters;
      final hr = stripHr ? null : pt.heartRateBpm;
      final cad = stripCad ? null : pt.cadenceRpm;
      final pwr = stripPower ? null : pt.powerWatts;
      final temp = stripTemp ? null : pt.temperatureCelsius;

      if (lat != null && lon != null) channels.add(Channel.gps);
      if (ele != null) channels.add(Channel.elevation);
      if (dist != null) channels.add(Channel.distance);
      if (hr != null) channels.add(Channel.heartRate);
      if (cad != null) channels.add(Channel.cadence);
      if (pwr != null) channels.add(Channel.power);
      if (temp != null) channels.add(Channel.temperature);

      strippedPoints.add(
        Trackpoint(
          timestamp: pt.timestamp,
          latitude: lat,
          longitude: lon,
          elevationMeters: ele,
          cumulativeDistanceMeters: dist,
          heartRateBpm: hr,
          cadenceRpm: cad,
          powerWatts: pwr,
          temperatureCelsius: temp,
        ),
      );
    }

    final effectiveCalories = stripCalories ? null : baseActivity.calories;
    final effectiveDeviceInfo =
        stripDeviceInfo ? null : baseActivity.deviceInfo;

    final List<Lap> effectiveLaps;
    if (stripLaps && strippedPoints.isNotEmpty) {
      effectiveLaps = [
        _buildCollapsedLap(
          strippedPoints,
          calories: effectiveCalories,
          stripHr: stripHr,
          stripCad: stripCad,
        ),
      ];
    } else {
      effectiveLaps = baseActivity.laps
          .map(
            (lap) => Lap(
              startTime: lap.startTime,
              endTime: lap.endTime,
              distanceMeters: lap.distanceMeters,
              avgHeartRateBpm: stripHr ? null : lap.avgHeartRateBpm,
              maxHeartRateBpm: stripHr ? null : lap.maxHeartRateBpm,
              avgCadenceRpm: stripCad ? null : lap.avgCadenceRpm,
              maxCadenceRpm: stripCad ? null : lap.maxCadenceRpm,
              calories: stripCalories ? null : lap.calories,
            ),
          )
          .toList();
    }

    return Activity(
      title: edit.title ?? baseActivity.title,
      description: edit.description ?? baseActivity.description,
      sportType: edit.sportType ?? baseActivity.sportType,
      trackpoints: strippedPoints,
      laps: effectiveLaps,
      availableChannels: channels,
      calories: effectiveCalories,
      deviceInfo: effectiveDeviceInfo,
    );
  }

  static List<Trackpoint> _ensureCumulativeDistancesBeforeGpsStrip(
    List<Trackpoint> points,
  ) {
    if (points.every((p) => p.cumulativeDistanceMeters != null)) {
      return points;
    }
    final result = <Trackpoint>[];
    var cumulative = 0.0;
    Trackpoint? prevGps;
    for (final pt in points) {
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
      final dist = pt.cumulativeDistanceMeters ?? cumulative;
      result.add(
        Trackpoint(
          timestamp: pt.timestamp,
          latitude: pt.latitude,
          longitude: pt.longitude,
          elevationMeters: pt.elevationMeters,
          cumulativeDistanceMeters: dist,
          heartRateBpm: pt.heartRateBpm,
          cadenceRpm: pt.cadenceRpm,
          powerWatts: pt.powerWatts,
          temperatureCelsius: pt.temperatureCelsius,
        ),
      );
    }
    return result;
  }

  static Lap _buildCollapsedLap(
    List<Trackpoint> points, {
    required int? calories,
    required bool stripHr,
    required bool stripCad,
  }) {
    var hrSum = 0;
    var hrCount = 0;
    var hrMax = 0;
    var cadSum = 0;
    var cadCount = 0;
    var cadMax = 0;

    for (final pt in points) {
      if (!stripHr && pt.heartRateBpm != null && pt.heartRateBpm! > 0) {
        hrSum += pt.heartRateBpm!;
        hrCount++;
        if (pt.heartRateBpm! > hrMax) hrMax = pt.heartRateBpm!;
      }
      if (!stripCad && pt.cadenceRpm != null && pt.cadenceRpm! > 0) {
        cadSum += pt.cadenceRpm!;
        cadCount++;
        if (pt.cadenceRpm! > cadMax) cadMax = pt.cadenceRpm!;
      }
    }

    double? distanceMeters;
    final firstDist = points.first.cumulativeDistanceMeters;
    final lastDist = points.last.cumulativeDistanceMeters;
    if (lastDist != null) {
      distanceMeters = math.max(0.0, lastDist - (firstDist ?? 0.0));
    }

    return Lap(
      startTime: points.first.timestamp,
      endTime: points.last.timestamp,
      distanceMeters: distanceMeters,
      avgHeartRateBpm: hrCount > 0 ? (hrSum / hrCount).round() : null,
      maxHeartRateBpm: hrCount > 0 ? hrMax : null,
      avgCadenceRpm: cadCount > 0 ? (cadSum / cadCount).round() : null,
      maxCadenceRpm: cadCount > 0 ? cadMax : null,
      calories: calories,
    );
  }

  /// Evaluates format-specific lossy-export and blocking warnings for
  /// [activity] with [edit] applied under [format].
  static List<ExportWarning> analyzeExportWarnings(
    Activity activity,
    ActivityEdit edit,
    ExportFormat format,
  ) {
    final warnings = <ExportWarning>[];
    final stripped = edit.strippedChannels;
    final effectiveTitle = (edit.title ?? activity.title).trim();
    final effectiveDesc = (edit.description ?? activity.description).trim();
    final effectiveSport = edit.sportType ?? activity.sportType;

    final hasGps =
        activity.availableChannels.contains(Channel.gps) &&
        !stripped.contains(StrippableChannel.gps);
    final hasDistance =
        edit.distanceOverrideMeters != null ||
        activity.availableChannels.contains(Channel.distance);
    final hasLaps =
        activity.laps.length > 1 && !stripped.contains(StrippableChannel.laps);
    final hasCalories =
        activity.calories != null &&
        !stripped.contains(StrippableChannel.calories);
    final hasPower =
        activity.availableChannels.contains(Channel.power) &&
        !stripped.contains(StrippableChannel.power);
    final hasTemperature =
        activity.availableChannels.contains(Channel.temperature) &&
        !stripped.contains(StrippableChannel.temperature);

    switch (format) {
      case ExportFormat.fit:
        if (effectiveTitle.isNotEmpty || effectiveDesc.isNotEmpty) {
          warnings.add(
            const ExportWarning(
              code: ExportWarningCode.stravaIgnoresManualUploadTitle,
              message:
                  'Strava ignores activity titles and descriptions in FIT files on manual web upload. Use the Strava Upload Helper below to copy & paste them.',
            ),
          );
        }
        break;

      case ExportFormat.tcx:
        if (effectiveTitle.isNotEmpty || effectiveDesc.isNotEmpty) {
          warnings.add(
            const ExportWarning(
              code: ExportWarningCode.stravaIgnoresManualUploadTitle,
              message:
                  'Strava ignores activity titles and descriptions in TCX files on manual web upload. Use the Strava Upload Helper below to copy & paste them.',
            ),
          );
        }
        if (effectiveSport != SportType.running &&
            effectiveSport != SportType.cycling) {
          warnings.add(
            ExportWarning(
              code: ExportWarningCode.tcxNarrowsSportCategory,
              message:
                  'TCX 2.0 narrows sport categories to Running, Biking, or Other—"${effectiveSport.displayName}" may be imported as Other.',
            ),
          );
        }
        if (hasTemperature) {
          warnings.add(
            const ExportWarning(
              code: ExportWarningCode.tcxDropsTemperature,
              message:
                  'TCX 2.0 does not support Temperature; temperature data will be dropped unless you export as FIT.',
            ),
          );
        }
        break;

      case ExportFormat.gpx:
        if (!hasGps) {
          warnings.add(
            const ExportWarning(
              code: ExportWarningCode.gpxRequiresGps,
              message:
                  'GPX 1.1 requires GPS coordinates on every trackpoint. Choose FIT or TCX for a mapless Export File, or re-enable GPS Position.',
              isBlocking: true,
            ),
          );
        }
        if (hasDistance) {
          warnings.add(
            ExportWarning(
              code: ExportWarningCode.gpxDropsCumulativeDistance,
              message: edit.distanceOverrideMeters != null
                  ? 'GPX 1.1 cannot carry cumulative distance. Your Distance Override will be dropped on GPX export—choose FIT or TCX to preserve it.'
                  : 'GPX 1.1 drops cumulative distance; target platforms recalculate distance from raw GPS points (Strava Tax).',
            ),
          );
        }
        if (hasLaps || hasCalories) {
          warnings.add(
            const ExportWarning(
              code: ExportWarningCode.gpxDropsLapsAndCalories,
              message:
                  'GPX 1.1 does not carry structured Laps or Calories; choose FIT or TCX to preserve them.',
            ),
          );
        }
        if (hasPower || hasTemperature) {
          warnings.add(
            const ExportWarning(
              code: ExportWarningCode.gpxDropsPowerAndTemperature,
              message:
                  'GPX 1.1 drops Power and Temperature channels; choose FIT to preserve all sensor channels.',
            ),
          );
        }
        break;
    }

    return warnings;
  }
}
