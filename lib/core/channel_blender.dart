import 'dart:math' as math;

import 'models.dart';
import 'summary_calculator.dart';

/// Pure-Dart multi-file Channel Blending engine.
class ChannelBlender {
  const ChannelBlender._();

  static const int alignmentToleranceMs = 5000;

  static BlendConfiguration defaultConfiguration(
    List<BlendSource> sources, {
    String? baseSourceId,
  }) {
    if (sources.isEmpty) {
      throw ArgumentError.value(
        sources,
        'sources',
        'At least one BlendSource is required.',
      );
    }

    final base = baseSourceId == null
        ? sources.first
        : sources.firstWhere(
            (s) => s.id == baseSourceId,
            orElse: () => sources.first,
          );

    final channelSources = <Channel, String?>{};
    for (final channel in Channel.values) {
      if (base.activity.availableChannels.contains(channel)) {
        channelSources[channel] = base.id;
      } else {
        String? fallbackId;
        for (final s in sources) {
          if (s.activity.availableChannels.contains(channel)) {
            fallbackId = s.id;
            break;
          }
        }
        channelSources[channel] = fallbackId;
      }
    }

    return BlendConfiguration(
      baseSourceId: base.id,
      channelSources: Map.unmodifiable(channelSources),
      lapsSourceId: base.id,
      caloriesSourceId: base.id,
      sportTypeSourceId: base.id,
      deviceInfoSourceId: base.id,
    );
  }

  static ParseResult blend(
    List<BlendSource> sources,
    BlendConfiguration config,
  ) {
    if (sources.isEmpty) {
      throw ArgumentError.value(
        sources,
        'sources',
        'At least one BlendSource is required.',
      );
    }

    final byId = <String, BlendSource>{
      for (final s in sources) s.id: s,
    };
    final base = byId[config.baseSourceId] ?? sources.first;

    BlendSource? resolveChannelSource(Channel channel) {
      if (config.channelSources.containsKey(channel)) {
        final id = config.channelSources[channel];
        return id == null ? null : byId[id];
      }
      return base;
    }

    final gpsSource = resolveChannelSource(Channel.gps);
    final eleSource = resolveChannelSource(Channel.elevation);
    final distSource = resolveChannelSource(Channel.distance);
    final hrSource = resolveChannelSource(Channel.heartRate);
    final cadSource = resolveChannelSource(Channel.cadence);
    final pwrSource = resolveChannelSource(Channel.power);
    final tempSource = resolveChannelSource(Channel.temperature);

    final gpsSamples = (gpsSource != null && gpsSource.id != base.id)
        ? _extractSamples(
            gpsSource.activity.trackpoints,
            (pt) => (pt.latitude != null && pt.longitude != null)
                ? _LatLon(pt.latitude!, pt.longitude!)
                : null,
          )
        : const <_TimedSample<_LatLon>>[];

    final eleSamples = (eleSource != null && eleSource.id != base.id)
        ? _extractSamples(
            eleSource.activity.trackpoints,
            (pt) => pt.elevationMeters,
          )
        : const <_TimedSample<double>>[];

    final distSamples = (distSource != null && distSource.id != base.id)
        ? _extractSamples(
            distSource.activity.trackpoints,
            (pt) => pt.cumulativeDistanceMeters,
          )
        : const <_TimedSample<double>>[];

    final hrSamples = (hrSource != null && hrSource.id != base.id)
        ? _extractSamples(
            hrSource.activity.trackpoints,
            (pt) => pt.heartRateBpm,
          )
        : const <_TimedSample<int>>[];

    final cadSamples = (cadSource != null && cadSource.id != base.id)
        ? _extractSamples(
            cadSource.activity.trackpoints,
            (pt) => pt.cadenceRpm,
          )
        : const <_TimedSample<int>>[];

    final pwrSamples = (pwrSource != null && pwrSource.id != base.id)
        ? _extractSamples(
            pwrSource.activity.trackpoints,
            (pt) => pt.powerWatts,
          )
        : const <_TimedSample<int>>[];

    final tempSamples = (tempSource != null && tempSource.id != base.id)
        ? _extractSamples(
            tempSource.activity.trackpoints,
            (pt) => pt.temperatureCelsius,
          )
        : const <_TimedSample<int>>[];

    final blendedPoints = <Trackpoint>[];
    final availableChannels = <Channel>{};

    for (final basePt in base.activity.trackpoints) {
      final ms = basePt.timestamp.millisecondsSinceEpoch;

      final _LatLon? gps;
      if (gpsSource == null) {
        gps = null;
      } else if (gpsSource.id == base.id) {
        gps = (basePt.latitude != null && basePt.longitude != null)
            ? _LatLon(basePt.latitude!, basePt.longitude!)
            : null;
      } else {
        gps = _sampleAt(gpsSamples, ms, _lerpLatLon);
      }

      final double? ele;
      if (eleSource == null) {
        ele = null;
      } else if (eleSource.id == base.id) {
        ele = basePt.elevationMeters;
      } else {
        ele = _sampleAt(eleSamples, ms, _lerpDouble);
      }

      final double? dist;
      if (distSource == null) {
        dist = null;
      } else if (distSource.id == base.id) {
        dist = basePt.cumulativeDistanceMeters;
      } else {
        dist = _sampleAt(distSamples, ms, _lerpDouble);
      }

      final int? hr;
      if (hrSource == null) {
        hr = null;
      } else if (hrSource.id == base.id) {
        hr = basePt.heartRateBpm;
      } else {
        hr = _sampleAt(hrSamples, ms, _lerpInt);
      }

      final int? cad;
      if (cadSource == null) {
        cad = null;
      } else if (cadSource.id == base.id) {
        cad = basePt.cadenceRpm;
      } else {
        cad = _sampleAt(cadSamples, ms, _lerpInt);
      }

      final int? pwr;
      if (pwrSource == null) {
        pwr = null;
      } else if (pwrSource.id == base.id) {
        pwr = basePt.powerWatts;
      } else {
        pwr = _sampleAt(pwrSamples, ms, _lerpInt);
      }

      final int? temp;
      if (tempSource == null) {
        temp = null;
      } else if (tempSource.id == base.id) {
        temp = basePt.temperatureCelsius;
      } else {
        temp = _sampleAt(tempSamples, ms, _lerpInt);
      }

      if (gps != null) availableChannels.add(Channel.gps);
      if (ele != null) availableChannels.add(Channel.elevation);
      if (dist != null) availableChannels.add(Channel.distance);
      if (hr != null) availableChannels.add(Channel.heartRate);
      if (cad != null) availableChannels.add(Channel.cadence);
      if (pwr != null) availableChannels.add(Channel.power);
      if (temp != null) availableChannels.add(Channel.temperature);

      blendedPoints.add(
        Trackpoint(
          timestamp: basePt.timestamp,
          latitude: gps?.lat,
          longitude: gps?.lon,
          elevationMeters: ele,
          cumulativeDistanceMeters: dist,
          heartRateBpm: hr,
          cadenceRpm: cad,
          powerWatts: pwr,
          temperatureCelsius: temp,
        ),
      );
    }

    final sportSource = byId[config.sportTypeSourceId] ?? base;
    final caloriesSource = byId[config.caloriesSourceId] ?? base;
    final deviceSource = byId[config.deviceInfoSourceId] ?? base;
    final lapsSource = byId[config.lapsSourceId] ?? base;

    final recomputedLaps = _recomputeLaps(
      lapsSource.activity.laps,
      blendedPoints,
    );

    final blendedActivity = Activity(
      title: base.activity.title,
      description: base.activity.description,
      sportType: sportSource.activity.sportType,
      trackpoints: blendedPoints,
      laps: recomputedLaps,
      availableChannels: availableChannels,
      calories: caloriesSource.activity.calories,
      deviceInfo: deviceSource.activity.deviceInfo,
    );

    final summary = SummaryCalculator.compute(blendedActivity);
    final diagnostics = <Diagnostic>[
      for (final s in sources) ...s.diagnostics,
    ];

    return ParseResult(
      activity: blendedActivity,
      summary: summary,
      diagnostics: diagnostics,
    );
  }

  static List<_TimedSample<T>> _extractSamples<T>(
    List<Trackpoint> trackpoints,
    T? Function(Trackpoint pt) selector,
  ) {
    final samples = <_TimedSample<T>>[];
    for (final pt in trackpoints) {
      final value = selector(pt);
      if (value != null) {
        samples.add(_TimedSample(pt.timestamp.millisecondsSinceEpoch, value));
      }
    }
    return samples;
  }

  static T? _sampleAt<T>(
    List<_TimedSample<T>> samples,
    int targetMs,
    T Function(T a, T b, double t) lerp,
  ) {
    if (samples.isEmpty) return null;

    var low = 0;
    var high = samples.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (samples[mid].ms < targetMs) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }

    if (low < samples.length && samples[low].ms == targetMs) {
      return samples[low].value;
    }

    final prev = low > 0 ? samples[low - 1] : null;
    final next = low < samples.length ? samples[low] : null;
    final prevWithin =
        prev != null && (targetMs - prev.ms) <= alignmentToleranceMs;
    final nextWithin =
        next != null && (next.ms - targetMs) <= alignmentToleranceMs;

    if (prevWithin && nextWithin) {
      final span = next.ms - prev.ms;
      final t = span == 0 ? 0.0 : (targetMs - prev.ms) / span;
      return lerp(prev.value, next.value, t);
    }
    if (prevWithin) return prev.value;
    if (nextWithin) return next.value;
    return null;
  }

  static double _lerpDouble(double a, double b, double t) => a + (b - a) * t;

  static int _lerpInt(int a, int b, double t) => (a + (b - a) * t).round();

  static _LatLon _lerpLatLon(_LatLon a, _LatLon b, double t) =>
      _LatLon(a.lat + (b.lat - a.lat) * t, a.lon + (b.lon - a.lon) * t);

  static List<Lap> _recomputeLaps(
    List<Lap> sourceLaps,
    List<Trackpoint> blendedPoints,
  ) {
    if (sourceLaps.isEmpty) return const [];
    final result = <Lap>[];
    for (final lap in sourceLaps) {
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
      var pointCount = 0;

      for (final pt in blendedPoints) {
        if (pt.timestamp.isBefore(lap.startTime) ||
            pt.timestamp.isAfter(lap.endTime)) {
          continue;
        }
        pointCount++;
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
      } else if (pointCount == 0) {
        distanceMeters = lap.distanceMeters;
      } else {
        distanceMeters = null;
      }

      result.add(
        Lap(
          startTime: lap.startTime,
          endTime: lap.endTime,
          distanceMeters: distanceMeters,
          avgHeartRateBpm: hrCount > 0 ? (hrSum / hrCount).round() : null,
          maxHeartRateBpm: hrCount > 0 ? hrMax : null,
          avgCadenceRpm: cadCount > 0 ? (cadSum / cadCount).round() : null,
          maxCadenceRpm: cadCount > 0 ? cadMax : null,
          calories: lap.calories,
        ),
      );
    }
    return result;
  }
}

class _TimedSample<T> {
  const _TimedSample(this.ms, this.value);

  final int ms;
  final T value;
}

class _LatLon {
  const _LatLon(this.lat, this.lon);

  final double lat;
  final double lon;
}
