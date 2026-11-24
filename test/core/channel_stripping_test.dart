import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gpx_lab/core/core_engine.dart';

void main() {
  group('CoreEngine Channel Stripping Seam', () {
    final t0 = DateTime.utc(2026, 11, 20, 6, 0, 0);
    final t1 = DateTime.utc(2026, 11, 20, 6, 5, 0);
    final t2 = DateTime.utc(2026, 11, 20, 6, 10, 0);

    Activity buildRichActivity() {
      return Activity(
        title: 'Morning Tempo',
        description: 'Fast finish',
        sportType: SportType.running,
        calories: 420,
        deviceInfo: 'Garmin Forerunner 965',
        availableChannels: const {
          Channel.gps,
          Channel.elevation,
          Channel.distance,
          Channel.heartRate,
          Channel.cadence,
          Channel.power,
          Channel.temperature,
        },
        trackpoints: [
          Trackpoint(
            timestamp: t0,
            latitude: 14.600000,
            longitude: 120.984000,
            elevationMeters: 10.0,
            cumulativeDistanceMeters: 0.0,
            heartRateBpm: 140,
            cadenceRpm: 170,
            powerWatts: 250,
            temperatureCelsius: 24,
          ),
          Trackpoint(
            timestamp: t1,
            latitude: 14.604500,
            longitude: 120.984000,
            elevationMeters: 25.0,
            cumulativeDistanceMeters: 500.0,
            heartRateBpm: 155,
            cadenceRpm: 176,
            powerWatts: 280,
            temperatureCelsius: 25,
          ),
          Trackpoint(
            timestamp: t2,
            latitude: 14.609000,
            longitude: 120.984000,
            elevationMeters: 30.0,
            cumulativeDistanceMeters: 1000.0,
            heartRateBpm: 165,
            cadenceRpm: 180,
            powerWatts: 300,
            temperatureCelsius: 26,
          ),
        ],
        laps: [
          Lap(
            startTime: t0,
            endTime: t1,
            distanceMeters: 500.0,
            avgHeartRateBpm: 148,
            maxHeartRateBpm: 155,
            avgCadenceRpm: 173,
            maxCadenceRpm: 176,
            calories: 200,
          ),
          Lap(
            startTime: t1,
            endTime: t2,
            distanceMeters: 500.0,
            avgHeartRateBpm: 160,
            maxHeartRateBpm: 165,
            avgCadenceRpm: 178,
            maxCadenceRpm: 180,
            calories: 220,
          ),
        ],
      );
    }

    test(
      'strips telemetry, calories, and deviceInfo with zero leakage across FIT, TCX, and GPX',
      () {
        final activity = buildRichActivity();
        const edit = ActivityEdit(
          strippedChannels: {
            StrippableChannel.heartRate,
            StrippableChannel.elevation,
            StrippableChannel.cadence,
            StrippableChannel.power,
            StrippableChannel.temperature,
            StrippableChannel.calories,
            StrippableChannel.deviceInfo,
          },
        );

        // FIT round-trip
        final fitExport = CoreEngine.exportFit(activity, edit);
        expect(fitExport.summary.avgHeartRateBpm, isNull);
        expect(fitExport.summary.maxHeartRateBpm, isNull);
        expect(fitExport.summary.elevationGainMeters, 0.0);
        expect(fitExport.summary.calories, isNull);
        expect(fitExport.summary.deviceInfo, isNull);

        final reparsedFit = CoreEngine.parseFit(fitExport.bytes);
        expect(reparsedFit.activity.calories, isNull);
        expect(reparsedFit.activity.deviceInfo, isNull);
        expect(reparsedFit.summary.avgHeartRateBpm, isNull);
        expect(reparsedFit.summary.elevationGainMeters, 0.0);
        for (final pt in reparsedFit.activity.trackpoints) {
          expect(pt.heartRateBpm, isNull);
          expect(pt.elevationMeters, isNull);
          expect(pt.cadenceRpm, isNull);
          expect(pt.powerWatts, isNull);
          expect(pt.temperatureCelsius, isNull);
          expect(pt.latitude, isNotNull);
          expect(pt.longitude, isNotNull);
        }
        for (final lap in reparsedFit.activity.laps) {
          expect(lap.avgHeartRateBpm, isNull);
          expect(lap.maxHeartRateBpm, isNull);
          expect(lap.calories, isNull);
        }

        // TCX round-trip
        final tcxExport = CoreEngine.exportTcx(activity, edit);
        final tcxXml = utf8.decode(tcxExport.bytes);
        expect(tcxXml, isNot(contains('<HeartRateBpm>')));
        expect(tcxXml, isNot(contains('<AverageHeartRateBpm>')));
        expect(tcxXml, isNot(contains('<MaximumHeartRateBpm>')));
        expect(tcxXml, isNot(contains('<AltitudeMeters>')));
        expect(tcxXml, isNot(contains('<Cadence>')));
        expect(tcxXml, isNot(contains('<ns3:RunCadence>')));
        expect(tcxXml, isNot(contains('<ns3:Watts>')));
        expect(tcxXml, isNot(contains('<Calories>')));
        expect(tcxXml, isNot(contains('<Creator')));
        expect(tcxXml, isNot(contains('Garmin')));

        final reparsedTcx = CoreEngine.parseTcx(tcxExport.bytes);
        expect(reparsedTcx.activity.calories, isNull);
        expect(reparsedTcx.activity.deviceInfo, isNull);
        for (final pt in reparsedTcx.activity.trackpoints) {
          expect(pt.heartRateBpm, isNull);
          expect(pt.elevationMeters, isNull);
          expect(pt.cadenceRpm, isNull);
          expect(pt.powerWatts, isNull);
        }

        // GPX round-trip
        final gpxExport = CoreEngine.exportGpx(activity, edit);
        final gpxXml = utf8.decode(gpxExport.bytes);
        expect(gpxXml, isNot(contains('<ele>')));
        expect(gpxXml, isNot(contains('<gpxtpx:hr>')));
        expect(gpxXml, isNot(contains('<gpxtpx:cad>')));
        expect(gpxXml, isNot(contains('Garmin')));

        final reparsedGpx = CoreEngine.parseGpx(gpxExport.bytes);
        for (final pt in reparsedGpx.activity.trackpoints) {
          expect(pt.heartRateBpm, isNull);
          expect(pt.elevationMeters, isNull);
          expect(pt.cadenceRpm, isNull);
          expect(pt.latitude, isNotNull);
        }
      },
    );

    test(
      'stripping GPS produces mapless FIT and TCX preserving distance and remaining channels, and blocks GPX',
      () {
        // Activity without pre-computed cumulativeDistanceMeters (e.g. from GPX)
        final gpsOnlyActivity = Activity(
          title: 'Outdoor Run',
          description: '',
          sportType: SportType.running,
          availableChannels: const {
            Channel.gps,
            Channel.heartRate,
          },
          trackpoints: [
            Trackpoint(
              timestamp: t0,
              latitude: 14.600000,
              longitude: 120.984000,
              heartRateBpm: 140,
            ),
            Trackpoint(
              timestamp: t2,
              latitude: 14.609000,
              longitude: 120.984000,
              heartRateBpm: 160,
            ),
          ],
          laps: [
            Lap(startTime: t0, endTime: t2),
          ],
        );

        const edit = ActivityEdit(
          strippedChannels: {StrippableChannel.gps},
        );

        // GPX export is blocked
        expect(
          () => CoreEngine.exportGpx(gpsOnlyActivity, edit),
          throwsStateError,
        );

        // FIT export is mapless & preserves distance (~1000.75 m) and HR
        final fitExport = CoreEngine.exportFit(gpsOnlyActivity, edit);
        expect(fitExport.summary.gpsDistanceMeters, greaterThan(900.0));
        final reparsedFit = CoreEngine.parseFit(fitExport.bytes);
        expect(
          reparsedFit.activity.availableChannels.contains(Channel.gps),
          isFalse,
        );
        expect(
          reparsedFit.activity.trackpoints.last.cumulativeDistanceMeters,
          greaterThan(900.0),
        );
        expect(reparsedFit.activity.trackpoints.first.latitude, isNull);
        expect(reparsedFit.activity.trackpoints.first.longitude, isNull);
        expect(reparsedFit.activity.trackpoints.first.heartRateBpm, 140);

        // TCX export is mapless & preserves distance and HR
        final tcxExport = CoreEngine.exportTcx(gpsOnlyActivity, edit);
        final tcxXml = utf8.decode(tcxExport.bytes);
        expect(tcxXml, isNot(contains('<Position>')));
        expect(tcxXml, isNot(contains('<LatitudeDegrees>')));
        final reparsedTcx = CoreEngine.parseTcx(tcxExport.bytes);
        expect(
          reparsedTcx.activity.availableChannels.contains(Channel.gps),
          isFalse,
        );
        expect(
          reparsedTcx.activity.trackpoints.last.cumulativeDistanceMeters,
          greaterThan(900.0),
        );
        expect(reparsedTcx.activity.trackpoints.first.heartRateBpm, 140);
      },
    );

    test(
      'stripping Laps collapses multi-lap Activity into a single contiguous Lap in FIT and TCX',
      () {
        final activity = buildRichActivity();
        expect(activity.laps.length, 2);

        const edit = ActivityEdit(
          strippedChannels: {StrippableChannel.laps},
        );

        final fitExport = CoreEngine.exportFit(activity, edit);
        expect(fitExport.summary.lapCount, 1);
        final reparsedFit = CoreEngine.parseFit(fitExport.bytes);
        expect(reparsedFit.activity.laps.length, 1);
        expect(reparsedFit.activity.laps.first.startTime, t0);
        expect(reparsedFit.activity.laps.first.endTime, t2);
        expect(
          reparsedFit.activity.laps.first.distanceMeters,
          closeTo(1000.0, 0.5),
        );

        final tcxExport = CoreEngine.exportTcx(activity, edit);
        expect(tcxExport.summary.lapCount, 1);
        final reparsedTcx = CoreEngine.parseTcx(tcxExport.bytes);
        expect(reparsedTcx.activity.laps.length, 1);
        expect(reparsedTcx.activity.laps.first.startTime, t0);
        expect(reparsedTcx.activity.laps.first.endTime, t2);
        expect(
          reparsedTcx.activity.laps.first.distanceMeters,
          closeTo(1000.0, 0.5),
        );
      },
    );

    test(
      'analyzeExportWarnings reports format-specific lossy-export and blocking warnings',
      () {
        final activity = buildRichActivity();

        // FIT: Strava ignores manual-upload titles/descriptions
        final fitWarnings = CoreEngine.analyzeExportWarnings(
          activity,
          const ActivityEdit(title: 'Edited Title'),
          ExportFormat.fit,
        );
        expect(
          fitWarnings.any(
            (w) =>
                w.code == ExportWarningCode.stravaIgnoresManualUploadTitle &&
                !w.isBlocking,
          ),
          isTrue,
        );

        // TCX: Strava title warning + sport narrowing (when hiking) + temperature dropped
        final tcxWarnings = CoreEngine.analyzeExportWarnings(
          activity,
          const ActivityEdit(sportType: SportType.hiking),
          ExportFormat.tcx,
        );
        expect(
          tcxWarnings.map((w) => w.code),
          containsAll([
            ExportWarningCode.stravaIgnoresManualUploadTitle,
            ExportWarningCode.tcxNarrowsSportCategory,
            ExportWarningCode.tcxDropsTemperature,
          ]),
        );

        // GPX with GPS kept: cumulative distance, laps/calories, power/temp warnings
        final gpxWarnings = CoreEngine.analyzeExportWarnings(
          activity,
          const ActivityEdit(distanceOverrideMeters: 1200.0),
          ExportFormat.gpx,
        );
        expect(
          gpxWarnings.map((w) => w.code),
          containsAll([
            ExportWarningCode.gpxDropsCumulativeDistance,
            ExportWarningCode.gpxDropsLapsAndCalories,
            ExportWarningCode.gpxDropsPowerAndTemperature,
          ]),
        );
        expect(gpxWarnings.any((w) => w.isBlocking), isFalse);

        // GPX with GPS stripped: blocking gpxRequiresGps warning
        final gpxBlockedWarnings = CoreEngine.analyzeExportWarnings(
          activity,
          const ActivityEdit(strippedChannels: {StrippableChannel.gps}),
          ExportFormat.gpx,
        );
        expect(
          gpxBlockedWarnings.any(
            (w) => w.code == ExportWarningCode.gpxRequiresGps && w.isBlocking,
          ),
          isTrue,
        );
      },
    );
  });
}
