import 'dart:math' as math;

import 'models.dart';
import 'summary_calculator.dart';

/// Pure-Dart multi-file Sequential Stitching engine.
class SequentialStitcher {
  const SequentialStitcher._();

  static StitchResult stitch(
    List<StitchSource> sources, [
    StitchConfiguration config = const StitchConfiguration(),
  ]) {
    if (sources.length < 2) {
      throw ArgumentError.value(
        sources,
        'sources',
        'At least two StitchSources are required for Sequential Stitching.',
      );
    }

    final indexed = sources.asMap().entries.toList()
      ..sort((a, b) {
        final startA = _startTimeOf(a.value.activity);
        final startB = _startTimeOf(b.value.activity);
        final cmp = startA.compareTo(startB);
        return cmp != 0 ? cmp : a.key.compareTo(b.key);
      });
    final ordered = [for (final entry in indexed) entry.value];

    final stitchedPoints = <Trackpoint>[];
    final stitchedLaps = <Lap>[];
    final availableChannels = <Channel>{};
    final partInfos = <StitchedPartInfo>[];
    final diagnostics = <Diagnostic>[
      for (final s in ordered) ...s.diagnostics,
    ];
    final deviceNames = <String>[];

    var totalCalories = 0;
    var hasCalories = false;
    var runningDistanceOffset = 0.0;
    DateTime? prevOriginalEnd;
    DateTime? prevOutputEnd;
    Activity? primaryActivity;

    for (final source in ordered) {
      final rawPoints = source.activity.trackpoints;
      if (rawPoints.isEmpty) {
        final fallbackTime = prevOutputEnd ?? DateTime.now().toUtc();
        partInfos.add(
          StitchedPartInfo(
            id: source.id,
            fileName: source.fileName,
            effectiveStartTime: fallbackTime,
            effectiveEndTime: fallbackTime,
            originalTrackpointCount: 0,
            keptTrackpointCount: 0,
            trimmedHeadCount: 0,
            distanceMeters: 0.0,
            channels: const {},
          ),
        );
        continue;
      }

      final originalStart = rawPoints.first.timestamp;
      final originalEnd = rawPoints.last.timestamp;

      var keptPoints = rawPoints;
      var trimmedHeadCount = 0;
      if (prevOriginalEnd != null) {
        final overlapsRange = originalStart.isBefore(prevOriginalEnd);
        keptPoints = rawPoints
            .where((pt) => pt.timestamp.isAfter(prevOriginalEnd!))
            .toList();
        trimmedHeadCount = rawPoints.length - keptPoints.length;

        if (overlapsRange && trimmedHeadCount > 0) {
          final message = keptPoints.isEmpty
              ? '${source.fileName} overlaps completely with earlier parts; trimmed all $trimmedHeadCount trackpoints (earlier file wins).'
              : 'Overlapping timestamps detected: trimmed $trimmedHeadCount trackpoint${trimmedHeadCount == 1 ? '' : 's'} from the start of ${source.fileName} (earlier file wins).';
          diagnostics.add(
            Diagnostic(
              code: DiagnosticCode.stitchOverlapTrimmed,
              severity: DiagnosticSeverity.warning,
              message: message,
              count: trimmedHeadCount,
            ),
          );
        }
      }

      if (prevOriginalEnd == null || originalEnd.isAfter(prevOriginalEnd)) {
        prevOriginalEnd = originalEnd;
      }

      if (keptPoints.isEmpty) {
        partInfos.add(
          StitchedPartInfo(
            id: source.id,
            fileName: source.fileName,
            effectiveStartTime: originalStart,
            effectiveEndTime: originalEnd,
            originalTrackpointCount: rawPoints.length,
            keptTrackpointCount: 0,
            trimmedHeadCount: trimmedHeadCount,
            distanceMeters: 0.0,
            channels: const {},
          ),
        );
        continue;
      }

      primaryActivity ??= source.activity;

      var shift = Duration.zero;
      if (config.removeGap && prevOutputEnd != null) {
        final desiredStart = prevOutputEnd.add(const Duration(seconds: 1));
        if (keptPoints.first.timestamp.isAfter(desiredStart)) {
          shift = keptPoints.first.timestamp.difference(desiredStart);
        }
      }

      final partBuild = _buildPartTrackpoints(
        keptPoints: keptPoints,
        distanceOffset: runningDistanceOffset,
        timeShift: shift,
        trimmedHead: trimmedHeadCount > 0,
      );

      stitchedPoints.addAll(partBuild.points);
      availableChannels.addAll(partBuild.channels);
      runningDistanceOffset += partBuild.distanceMeters;
      prevOutputEnd = partBuild.points.last.timestamp;

      final partLaps = _buildPartLaps(
        sourceActivity: source.activity,
        rawStart: keptPoints.first.timestamp,
        rawEnd: keptPoints.last.timestamp,
        partPoints: partBuild.points,
        timeShift: shift,
      );
      stitchedLaps.addAll(partLaps);

      if (source.activity.calories != null) {
        totalCalories += source.activity.calories!;
        hasCalories = true;
      }

      final dev = source.activity.deviceInfo?.trim();
      if (dev != null && dev.isNotEmpty && !deviceNames.contains(dev)) {
        deviceNames.add(dev);
      }

      partInfos.add(
        StitchedPartInfo(
          id: source.id,
          fileName: source.fileName,
          effectiveStartTime: partBuild.points.first.timestamp,
          effectiveEndTime: partBuild.points.last.timestamp,
          originalTrackpointCount: rawPoints.length,
          keptTrackpointCount: partBuild.points.length,
          trimmedHeadCount: trimmedHeadCount,
          distanceMeters: partBuild.distanceMeters,
          channels: Set.unmodifiable(partBuild.channels),
        ),
      );
    }

    final base = primaryActivity ?? ordered.first.activity;
    final stitchedActivity = Activity(
      title: base.title,
      description: base.description,
      sportType: base.sportType,
      trackpoints: stitchedPoints,
      laps: stitchedLaps,
      availableChannels: Set.unmodifiable(availableChannels),
      calories: hasCalories ? totalCalories : null,
      deviceInfo: deviceNames.isEmpty ? null : deviceNames.join(' + '),
    );

    return StitchResult(
      activity: stitchedActivity,
      summary: SummaryCalculator.compute(stitchedActivity),
      diagnostics: diagnostics,
      parts: List.unmodifiable(partInfos),
    );
  }

  static DateTime _startTimeOf(Activity activity) {
    if (activity.trackpoints.isNotEmpty) {
      return activity.trackpoints.first.timestamp;
    }
    if (activity.laps.isNotEmpty) {
      return activity.laps.first.startTime;
    }
    return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  static _PartTrackpointsBuild _buildPartTrackpoints({
    required List<Trackpoint> keptPoints,
    required double distanceOffset,
    required Duration timeShift,
    required bool trimmedHead,
  }) {
    final hasRecordedDistance =
        keptPoints.any((p) => p.cumulativeDistanceMeters != null);
    final hasGps =
        keptPoints.any((p) => p.latitude != null && p.longitude != null);
    final synthesizeFromGps = !hasRecordedDistance && hasGps;

    double? recordedBase;
    if (hasRecordedDistance && trimmedHead) {
      for (final pt in keptPoints) {
        if (pt.cumulativeDistanceMeters != null) {
          recordedBase = pt.cumulativeDistanceMeters;
          break;
        }
      }
    }
    final baseDistance = recordedBase ?? 0.0;

    final result = <Trackpoint>[];
    final channels = <Channel>{};
    var localDistance = 0.0;
    Trackpoint? prevGps;

    for (final pt in keptPoints) {
      var stepHaversine = 0.0;
      if (pt.latitude != null && pt.longitude != null) {
        if (prevGps != null) {
          stepHaversine = SummaryCalculator.haversineMeters(
            prevGps.latitude!,
            prevGps.longitude!,
            pt.latitude!,
            pt.longitude!,
          );
        }
        prevGps = pt;
      }

      double? stitchedDist;
      if (hasRecordedDistance) {
        if (pt.cumulativeDistanceMeters != null) {
          localDistance = math.max(
            localDistance,
            pt.cumulativeDistanceMeters! - baseDistance,
          );
        } else {
          localDistance += stepHaversine;
        }
        stitchedDist = distanceOffset + localDistance;
      } else if (synthesizeFromGps) {
        localDistance += stepHaversine;
        stitchedDist = distanceOffset + localDistance;
      }

      if (pt.latitude != null && pt.longitude != null) {
        channels.add(Channel.gps);
      }
      if (pt.elevationMeters != null) channels.add(Channel.elevation);
      if (stitchedDist != null) channels.add(Channel.distance);
      if (pt.heartRateBpm != null) channels.add(Channel.heartRate);
      if (pt.cadenceRpm != null) channels.add(Channel.cadence);
      if (pt.powerWatts != null) channels.add(Channel.power);
      if (pt.temperatureCelsius != null) channels.add(Channel.temperature);

      result.add(
        Trackpoint(
          timestamp: pt.timestamp.subtract(timeShift),
          latitude: pt.latitude,
          longitude: pt.longitude,
          elevationMeters: pt.elevationMeters,
          cumulativeDistanceMeters: stitchedDist,
          heartRateBpm: pt.heartRateBpm,
          cadenceRpm: pt.cadenceRpm,
          powerWatts: pt.powerWatts,
          temperatureCelsius: pt.temperatureCelsius,
        ),
      );
    }

    return _PartTrackpointsBuild(
      points: result,
      channels: channels,
      distanceMeters: localDistance,
    );
  }

  static List<Lap> _buildPartLaps({
    required Activity sourceActivity,
    required DateTime rawStart,
    required DateTime rawEnd,
    required List<Trackpoint> partPoints,
    required Duration timeShift,
  }) {
    if (partPoints.isEmpty) return const [];

    final sourceLaps = sourceActivity.laps;
    final built = <Lap>[];

    if (sourceLaps.isNotEmpty) {
      for (final lap in sourceLaps) {
        if (lap.endTime.isBefore(rawStart) || lap.startTime.isAfter(rawEnd)) {
          continue;
        }
        final clippedRawStart =
            lap.startTime.isBefore(rawStart) ? rawStart : lap.startTime;
        final clippedRawEnd =
            lap.endTime.isAfter(rawEnd) ? rawEnd : lap.endTime;
        final shiftedStart = clippedRawStart.subtract(timeShift);
        final shiftedEnd = clippedRawEnd.subtract(timeShift);

        final inLap = partPoints
            .where(
              (pt) =>
                  !pt.timestamp.isBefore(shiftedStart) &&
                  !pt.timestamp.isAfter(shiftedEnd),
            )
            .toList();
        if (inLap.isEmpty) continue;

        built.add(
          _summarizeLap(
            startTime: shiftedStart,
            endTime: shiftedEnd,
            points: inLap,
            calories: lap.calories,
          ),
        );
      }
    }

    if (built.isEmpty) {
      built.add(
        _summarizeLap(
          startTime: partPoints.first.timestamp,
          endTime: partPoints.last.timestamp,
          points: partPoints,
          calories: sourceActivity.calories,
        ),
      );
    }

    return built;
  }

  static Lap _summarizeLap({
    required DateTime startTime,
    required DateTime endTime,
    required List<Trackpoint> points,
    int? calories,
  }) {
    var hrSum = 0;
    var hrCount = 0;
    var hrMax = 0;
    var cadSum = 0;
    var cadCount = 0;
    var cadMax = 0;
    double? firstDist;
    double? lastDist;
    var gpsDist = 0.0;
    Trackpoint? prevGps;

    for (final pt in points) {
      final hr = pt.heartRateBpm;
      if (hr != null && hr > 0) {
        hrSum += hr;
        hrCount++;
        if (hr > hrMax) hrMax = hr;
      }
      final cad = pt.cadenceRpm;
      if (cad != null && cad > 0) {
        cadSum += cad;
        cadCount++;
        if (cad > cadMax) cadMax = cad;
      }
      if (pt.cumulativeDistanceMeters != null) {
        firstDist ??= pt.cumulativeDistanceMeters;
        lastDist = pt.cumulativeDistanceMeters;
      }
      if (pt.latitude != null && pt.longitude != null) {
        if (prevGps != null) {
          gpsDist += SummaryCalculator.haversineMeters(
            prevGps.latitude!,
            prevGps.longitude!,
            pt.latitude!,
            pt.longitude!,
          );
        }
        prevGps = pt;
      }
    }

    final double? distanceMeters;
    if (firstDist != null && lastDist != null) {
      distanceMeters = math.max(0.0, lastDist - firstDist);
    } else if (gpsDist > 0) {
      distanceMeters = gpsDist;
    } else {
      distanceMeters = null;
    }

    return Lap(
      startTime: startTime,
      endTime: endTime,
      distanceMeters: distanceMeters,
      avgHeartRateBpm: hrCount > 0 ? (hrSum / hrCount).round() : null,
      maxHeartRateBpm: hrCount > 0 ? hrMax : null,
      avgCadenceRpm: cadCount > 0 ? (cadSum / cadCount).round() : null,
      maxCadenceRpm: cadCount > 0 ? cadMax : null,
      calories: calories,
    );
  }
}

class _PartTrackpointsBuild {
  const _PartTrackpointsBuild({
    required this.points,
    required this.channels,
    required this.distanceMeters,
  });

  final List<Trackpoint> points;
  final Set<Channel> channels;
  final double distanceMeters;
}
