import 'package:flutter_test/flutter_test.dart';
import 'package:gpx_lab/core/core_engine.dart';

Activity _buildSyntheticActivity({
  required int trackpointCount,
  bool withGps = true,
  bool withHeartRate = true,
  bool withElevation = true,
}) {
  final start = DateTime.utc(2026, 11, 19, 6, 0, 0);
  final points = List<Trackpoint>.generate(trackpointCount, (i) {
    final t = start.add(Duration(seconds: i));
    return Trackpoint(
      timestamp: t,
      latitude: withGps ? 14.5500 + (i * 0.00005) : null,
      longitude: withGps ? 121.0200 + (i * 0.00003) : null,
      elevationMeters: withElevation ? 10.0 + (i % 50) * 0.5 : null,
      cumulativeDistanceMeters: i * 3.0,
      heartRateBpm: withHeartRate ? 130 + (i % 40) : null,
    );
  });

  return Activity(
    title: 'Endurance Test Run',
    description: '',
    sportType: SportType.running,
    trackpoints: points,
    laps: [
      Lap(
        startTime: start,
        endTime: start.add(Duration(seconds: trackpointCount - 1)),
        distanceMeters: (trackpointCount - 1) * 3.0,
        avgHeartRateBpm: 150,
      ),
    ],
    availableChannels: {
      if (withGps) Channel.gps,
      if (withElevation) Channel.elevation,
      Channel.distance,
      if (withHeartRate) Channel.heartRate,
    },
  );
}

void main() {
  group('CoreEngine Display Geometry Seam', () {
    test('preserves all points for small activities and computes pace series', () {
      final activity = _buildSyntheticActivity(trackpointCount: 120);

      final geometry = CoreEngine.buildDisplayGeometry(activity);

      expect(geometry.sourceTrackpointCount, 120);
      expect(geometry.routePoints.length, 120);
      expect(geometry.heartRateSeries.length, 120);
      expect(geometry.elevationSeries.length, 120);
      expect(geometry.paceSeries, isNotEmpty);
      expect(geometry.routePoints.first.latitude, closeTo(14.5500, 1e-6));
      expect(
        geometry.routePoints.last.latitude,
        closeTo(14.5500 + 119 * 0.00005, 1e-6),
      );
    });

    test(
      'downsamples 16,000 trackpoints for display while preserving 100% canonical trackpoints in Export File',
      () async {
        final activity = _buildSyntheticActivity(trackpointCount: 16000);

        final geometry = await CoreEngine.buildDisplayGeometryInIsolate(
          activity,
          maxPoints: 1000,
        );

        expect(geometry.sourceTrackpointCount, 16000);
        expect(geometry.routePoints.length, lessThanOrEqualTo(1000));
        expect(geometry.routePoints.length, greaterThan(500));
        expect(geometry.heartRateSeries.length, lessThanOrEqualTo(1000));
        expect(geometry.elevationSeries.length, lessThanOrEqualTo(1000));
        expect(geometry.paceSeries.length, lessThanOrEqualTo(1000));

        // First and last GPS points preserved.
        expect(geometry.routePoints.first.latitude, closeTo(14.5500, 1e-6));
        expect(
          geometry.routePoints.last.latitude,
          closeTo(14.5500 + 15999 * 0.00005, 1e-6),
        );

        // Canonical Activity and Export File retain 100% of trackpoints.
        expect(activity.trackpoints.length, 16000);
        final exported = CoreEngine.exportFit(
          activity,
          const ActivityEdit(title: 'Endurance Test Run'),
        );
        final reparsed = CoreEngine.parseFit(exported.bytes);
        expect(reparsed.activity.trackpoints.length, 16000);
      },
    );

    test('returns empty routePoints for indoor activity without GPS', () {
      final activity = _buildSyntheticActivity(
        trackpointCount: 60,
        withGps: false,
        withElevation: false,
      );

      final geometry = CoreEngine.buildDisplayGeometry(activity);

      expect(geometry.routePoints, isEmpty);
      expect(geometry.elevationSeries, isEmpty);
      expect(geometry.heartRateSeries.length, 60);
    });
  });
}
