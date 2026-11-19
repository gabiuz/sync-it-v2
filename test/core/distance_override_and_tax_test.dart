import 'package:flutter_test/flutter_test.dart';
import 'package:sync_it/core/core_engine.dart';

void main() {
  group('CoreEngine Distance Diagnostics & Override Seam', () {
    test('analyzeDistance computes GPS vs recorded distance, Strava Tax, and floor-truncation milestone warning', () {
      final t0 = DateTime.utc(2026, 11, 19, 6, 0, 0);
      final t1 = DateTime.utc(2026, 11, 19, 6, 50, 0);

      // Two GPS points ~9900 m apart, while watch recorded 9998.0 m (9.998 km).
      final activity = Activity(
        title: 'Morning 10K',
        description: '',
        sportType: SportType.running,
        trackpoints: [
          Trackpoint(
            timestamp: t0,
            latitude: 14.600000,
            longitude: 120.984000,
            cumulativeDistanceMeters: 0.0,
          ),
          Trackpoint(
            timestamp: t1,
            latitude: 14.689000,
            longitude: 120.984000,
            cumulativeDistanceMeters: 9998.0,
          ),
        ],
        laps: [
          Lap(startTime: t0, endTime: t1, distanceMeters: 9998.0),
        ],
        availableChannels: const {Channel.gps, Channel.distance},
      );

      final diag = CoreEngine.analyzeDistance(activity, isImperial: false);
      expect(diag.recordedDistanceMeters, closeTo(9998.0, 0.01));
      expect(diag.gpsDistanceMeters, closeTo(9896.3, 5.0));
      expect(diag.effectiveDistanceMeters, closeTo(9998.0, 0.01));
      expect(
        diag.stravaTaxMeters,
        closeTo(9998.0 - diag.gpsDistanceMeters, 0.01),
      );
      expect(diag.predictedStravaDisplayValue, 9.99);
      expect(diag.dropsMilestone, isTrue);
      expect(diag.nudgeTargetDisplayValue, 10.00);
      expect(diag.nudgeTargetMeters, closeTo(10000.0, 0.01));

      // Applying the nudge target as override clears the milestone-drop warning
      // and avoids false floor-truncation at exact 10.00 km.
      final nudgedDiag = CoreEngine.analyzeDistance(
        activity,
        isImperial: false,
        distanceOverrideMeters: diag.nudgeTargetMeters,
      );
      expect(nudgedDiag.effectiveDistanceMeters, closeTo(10000.0, 0.01));
      expect(nudgedDiag.predictedStravaDisplayValue, 10.00);
      expect(nudgedDiag.dropsMilestone, isFalse);
      expect(nudgedDiag.nudgeTargetMeters, isNull);
    });

    test('applyDistanceOverride scales trackpoints proportionally, recomputes laps, never mutates source, and round-trips through FIT and TCX', () {
      final t0 = DateTime.utc(2026, 11, 19, 6, 0, 0);
      final t1 = DateTime.utc(2026, 11, 19, 6, 15, 0);
      final t2 = DateTime.utc(2026, 11, 19, 6, 30, 0);
      final t3 = DateTime.utc(2026, 11, 19, 6, 45, 0);

      final source = Activity(
        title: 'Two Lap Run',
        description: 'Tempo',
        sportType: SportType.running,
        trackpoints: [
          Trackpoint(
            timestamp: t0,
            latitude: 14.600000,
            longitude: 120.984000,
            cumulativeDistanceMeters: 0.0,
          ),
          Trackpoint(
            timestamp: t1,
            latitude: 14.622500,
            longitude: 120.984000,
            cumulativeDistanceMeters: 2500.0,
          ),
          Trackpoint(
            timestamp: t2,
            latitude: 14.645000,
            longitude: 120.984000,
            cumulativeDistanceMeters: 5000.0,
          ),
          Trackpoint(
            timestamp: t3,
            latitude: 14.689900,
            longitude: 120.984000,
            cumulativeDistanceMeters: 9990.0,
          ),
        ],
        laps: [
          Lap(startTime: t0, endTime: t2, distanceMeters: 5000.0),
          Lap(startTime: t2, endTime: t3, distanceMeters: 4990.0),
        ],
        availableChannels: const {Channel.gps, Channel.distance},
      );

      // Zero silent mutations: applyDistanceOverride returns a new Activity.
      final scaled = CoreEngine.applyDistanceOverride(source, 10000.0);
      expect(source.trackpoints.last.cumulativeDistanceMeters, 9990.0);
      expect(source.laps[0].distanceMeters, 5000.0);
      expect(source.laps[1].distanceMeters, 4990.0);

      // Proportional scaling: 5000 / 9990 * 10000 ≈ 5005.005
      expect(scaled.trackpoints[0].cumulativeDistanceMeters, 0.0);
      expect(
        scaled.trackpoints[1].cumulativeDistanceMeters,
        closeTo(2500.0 / 9990.0 * 10000.0, 0.01),
      );
      expect(
        scaled.trackpoints[2].cumulativeDistanceMeters,
        closeTo(5000.0 / 9990.0 * 10000.0, 0.01),
      );
      expect(scaled.trackpoints[3].cumulativeDistanceMeters, closeTo(10000.0, 0.001));

      final lapSum =
          scaled.laps.fold<double>(0.0, (sum, l) => sum + (l.distanceMeters ?? 0.0));
      expect(lapSum, closeTo(10000.0, 0.01));

      // FIT round-trip consistency
      final fitExport = CoreEngine.exportFit(
        source,
        const ActivityEdit(distanceOverrideMeters: 10000.0),
      );
      final fitParsed = CoreEngine.parseFit(fitExport.bytes);
      expect(
        fitParsed.activity.trackpoints.last.cumulativeDistanceMeters,
        closeTo(10000.0, 0.02),
      );
      final fitLapSum = fitParsed.activity.laps
          .fold<double>(0.0, (sum, l) => sum + (l.distanceMeters ?? 0.0));
      expect(fitLapSum, closeTo(10000.0, 0.02));

      // TCX round-trip consistency
      final tcxExport = CoreEngine.exportTcx(
        source,
        const ActivityEdit(distanceOverrideMeters: 10000.0),
      );
      final tcxParsed = CoreEngine.parseTcx(tcxExport.bytes);
      expect(
        tcxParsed.activity.trackpoints.last.cumulativeDistanceMeters,
        closeTo(10000.0, 0.02),
      );
      final tcxLapSum = tcxParsed.activity.laps
          .fold<double>(0.0, (sum, l) => sum + (l.distanceMeters ?? 0.0));
      expect(tcxLapSum, closeTo(10000.0, 0.02));
    });
  });
}
