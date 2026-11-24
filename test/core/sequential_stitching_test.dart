import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gpx_lab/core/core_engine.dart';

Uint8List _utf8(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  group('CoreEngine Sequential Stitching Seam', () {
    test(
      'orders parts chronologically and synthesizes GPX distance before offsetting by prior terminal distance',
      () {
        // Part 1 (06:00:00 - 06:02:00): TCX with recorded cumulative distance 0 -> 500 m
        const part1Tcx = '''<?xml version="1.0" encoding="UTF-8"?>
<TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2">
  <Activities>
    <Activity Sport="Running">
      <Id>2026-11-20T06:00:00Z</Id>
      <Lap StartTime="2026-11-20T06:00:00Z">
        <TotalTimeSeconds>120</TotalTimeSeconds>
        <DistanceMeters>500</DistanceMeters>
        <Track>
          <Trackpoint>
            <Time>2026-11-20T06:00:00Z</Time>
            <Position>
              <LatitudeDegrees>14.600000</LatitudeDegrees>
              <LongitudeDegrees>120.984000</LongitudeDegrees>
            </Position>
            <DistanceMeters>0</DistanceMeters>
          </Trackpoint>
          <Trackpoint>
            <Time>2026-11-20T06:02:00Z</Time>
            <Position>
              <LatitudeDegrees>14.604500</LatitudeDegrees>
              <LongitudeDegrees>120.984000</LongitudeDegrees>
            </Position>
            <DistanceMeters>500</DistanceMeters>
          </Trackpoint>
        </Track>
      </Lap>
    </Activity>
  </Activities>
</TrainingCenterDatabase>''';

        // Part 2 (06:05:00 - 06:07:00): GPX without cumulative distance (0.0018 deg lat ~ 200 m)
        const part2Gpx = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="PhoneGPX"
  xmlns="http://www.topografix.com/GPX/1/1">
  <trk>
    <name>Phone Backup</name>
    <type>running</type>
    <trkseg>
      <trkpt lat="14.604500" lon="120.984000">
        <time>2026-11-20T06:05:00Z</time>
      </trkpt>
      <trkpt lat="14.605400" lon="120.984000">
        <time>2026-11-20T06:06:00Z</time>
      </trkpt>
      <trkpt lat="14.606300" lon="120.984000">
        <time>2026-11-20T06:07:00Z</time>
      </trkpt>
    </trkseg>
  </trk>
</gpx>''';

        final parsed1 = CoreEngine.parseTcx(_utf8(part1Tcx), fileName: 'watch.tcx');
        final parsed2 = CoreEngine.parseGpx(_utf8(part2Gpx), fileName: 'phone.gpx');

        // Pass in reverse chronological order to verify automatic sorting
        final result = CoreEngine.stitchActivities([
          StitchSource(
            id: 'p2',
            fileName: 'phone.gpx',
            activity: parsed2.activity,
            diagnostics: parsed2.diagnostics,
          ),
          StitchSource(
            id: 'p1',
            fileName: 'watch.tcx',
            activity: parsed1.activity,
            diagnostics: parsed1.diagnostics,
          ),
        ]);

        expect(result.parts.map((p) => p.fileName).toList(), [
          'watch.tcx',
          'phone.gpx',
        ]);
        expect(result.activity.trackpoints.length, 5);
        expect(
          result.activity.trackpoints.map((p) => p.timestamp.toUtc()).toList(),
          [
            DateTime.utc(2026, 11, 20, 6, 0, 0),
            DateTime.utc(2026, 11, 20, 6, 2, 0),
            DateTime.utc(2026, 11, 20, 6, 5, 0),
            DateTime.utc(2026, 11, 20, 6, 6, 0),
            DateTime.utc(2026, 11, 20, 6, 7, 0),
          ],
        );

        // Part 1 ends at 500 m; Part 2 starts at 500 m and adds ~100 m + ~100 m = ~700 m
        final pts = result.activity.trackpoints;
        expect(pts[0].cumulativeDistanceMeters, closeTo(0.0, 1e-6));
        expect(pts[1].cumulativeDistanceMeters, closeTo(500.0, 1e-6));
        expect(pts[2].cumulativeDistanceMeters, closeTo(500.0, 1e-6));
        expect(pts[3].cumulativeDistanceMeters, greaterThan(595.0));
        expect(pts[3].cumulativeDistanceMeters, lessThan(605.0));
        expect(pts[4].cumulativeDistanceMeters, greaterThan(695.0));
        expect(pts[4].cumulativeDistanceMeters, lessThan(705.0));
      },
    );

    test(
      'preserves union of Channels while leaving missing Channels null only on parts that lack them',
      () {
        final t0 = DateTime.utc(2026, 11, 20, 7, 0, 0);
        // Part 1: Watch TCX with HR, Cadence, GPS, Distance (no Elevation, no Power)
        final watchPart = StitchSource(
          id: 'p1',
          fileName: 'watch.tcx',
          activity: Activity(
            title: 'Watch Part',
            description: 'First half',
            sportType: SportType.running,
            calories: 180,
            deviceInfo: 'Huawei Watch',
            availableChannels: const {
              Channel.gps,
              Channel.distance,
              Channel.heartRate,
              Channel.cadence,
            },
            laps: [
              Lap(
                startTime: t0,
                endTime: t0.add(const Duration(seconds: 60)),
                distanceMeters: 250,
                calories: 180,
              ),
            ],
            trackpoints: [
              Trackpoint(
                timestamp: t0,
                latitude: 14.6000,
                longitude: 120.9840,
                cumulativeDistanceMeters: 0,
                heartRateBpm: 145,
                cadenceRpm: 172,
              ),
              Trackpoint(
                timestamp: t0.add(const Duration(seconds: 60)),
                latitude: 14.6022,
                longitude: 120.9840,
                cumulativeDistanceMeters: 250,
                heartRateBpm: 155,
                cadenceRpm: 176,
              ),
            ],
          ),
        );

        // Part 2: Phone GPX with GPS + Elevation (no HR, no Cadence, no Distance)
        final phonePart = StitchSource(
          id: 'p2',
          fileName: 'phone.gpx',
          activity: Activity(
            title: 'Phone Part',
            description: 'Second half',
            sportType: SportType.running,
            deviceInfo: 'Phone GPX',
            availableChannels: const {Channel.gps, Channel.elevation},
            laps: const [],
            trackpoints: [
              Trackpoint(
                timestamp: t0.add(const Duration(minutes: 3)),
                latitude: 14.6022,
                longitude: 120.9840,
                elevationMeters: 22.0,
              ),
              Trackpoint(
                timestamp: t0.add(const Duration(minutes: 4)),
                latitude: 14.6031,
                longitude: 120.9840,
                elevationMeters: 28.0,
              ),
            ],
          ),
        );

        final stitched = CoreEngine.stitchActivities([watchPart, phonePart]);

        expect(
          stitched.activity.availableChannels,
          containsAll([
            Channel.gps,
            Channel.elevation,
            Channel.distance,
            Channel.heartRate,
            Channel.cadence,
          ]),
        );
        expect(stitched.activity.calories, 180);
        expect(stitched.activity.deviceInfo, 'Huawei Watch + Phone GPX');

        final pts = stitched.activity.trackpoints;
        expect(pts.length, 4);
        // Part 1 keeps HR & Cadence, leaves Elevation null
        expect(pts[0].heartRateBpm, 145);
        expect(pts[0].cadenceRpm, 172);
        expect(pts[0].elevationMeters, isNull);
        expect(pts[1].heartRateBpm, 155);
        expect(pts[1].elevationMeters, isNull);

        // Part 2 keeps Elevation, leaves HR & Cadence null
        expect(pts[2].heartRateBpm, isNull);
        expect(pts[2].cadenceRpm, isNull);
        expect(pts[2].elevationMeters, closeTo(22.0, 1e-6));
        expect(pts[3].heartRateBpm, isNull);
        expect(pts[3].cadenceRpm, isNull);
        expect(pts[3].elevationMeters, closeTo(28.0, 1e-6));

        // Round-trip FIT export preserves per-part Channel nulls
        final fitExport = CoreEngine.exportFit(
          stitched.activity,
          const ActivityEdit(),
        );
        final fitReparsed = CoreEngine.parseFit(fitExport.bytes);
        expect(fitReparsed.activity.trackpoints[0].heartRateBpm, 145);
        expect(fitReparsed.activity.trackpoints[0].elevationMeters, isNull);
        expect(fitReparsed.activity.trackpoints[2].heartRateBpm, isNull);
        expect(
          fitReparsed.activity.trackpoints[2].elevationMeters,
          closeTo(22.0, 0.2),
        );
      },
    );

    test(
      'preserves real timestamps with Lap boundary by default, and shifts flush when removeGap is true',
      () {
        final t0 = DateTime.utc(2026, 11, 20, 8, 0, 0);

        final part1 = StitchSource(
          id: 'p1',
          fileName: 'part1.fit',
          activity: Activity(
            title: 'Long Run',
            description: '',
            sportType: SportType.running,
            availableChannels: const {Channel.gps, Channel.distance},
            laps: [
              Lap(
                startTime: t0,
                endTime: t0.add(const Duration(minutes: 5)),
                distanceMeters: 1000,
              ),
            ],
            trackpoints: [
              Trackpoint(
                timestamp: t0,
                latitude: 14.6000,
                longitude: 120.9840,
                cumulativeDistanceMeters: 0,
              ),
              Trackpoint(
                timestamp: t0.add(const Duration(minutes: 5)),
                latitude: 14.6090,
                longitude: 120.9840,
                cumulativeDistanceMeters: 1000,
              ),
            ],
          ),
        );

        // 10-minute gap from 08:05:00 to 08:15:00, with 2 Laps in Part 2
        final part2Start = t0.add(const Duration(minutes: 15));
        final part2Mid = t0.add(const Duration(minutes: 20));
        final part2End = t0.add(const Duration(minutes: 25));
        final part2 = StitchSource(
          id: 'p2',
          fileName: 'part2.tcx',
          activity: Activity(
            title: 'Part 2',
            description: '',
            sportType: SportType.running,
            availableChannels: const {Channel.gps, Channel.distance},
            laps: [
              Lap(startTime: part2Start, endTime: part2Mid, distanceMeters: 1000),
              Lap(startTime: part2Mid, endTime: part2End, distanceMeters: 1000),
            ],
            trackpoints: [
              Trackpoint(
                timestamp: part2Start,
                latitude: 14.6090,
                longitude: 120.9840,
                cumulativeDistanceMeters: 0,
              ),
              Trackpoint(
                timestamp: part2Mid,
                latitude: 14.6180,
                longitude: 120.9840,
                cumulativeDistanceMeters: 1000,
              ),
              Trackpoint(
                timestamp: part2End,
                latitude: 14.6270,
                longitude: 120.9840,
                cumulativeDistanceMeters: 2000,
              ),
            ],
          ),
        );

        // Default: preserve real timestamps & Lap boundary across gap
        final gapPreserved = CoreEngine.stitchActivities([part1, part2]);
        expect(gapPreserved.summary.duration, const Duration(minutes: 25));
        expect(gapPreserved.activity.laps.length, 3);
        expect(gapPreserved.activity.laps[0].endTime, t0.add(const Duration(minutes: 5)));
        expect(gapPreserved.activity.laps[1].startTime, part2Start);
        expect(gapPreserved.activity.trackpoints[2].timestamp, part2Start);
        expect(gapPreserved.activity.trackpoints.last.cumulativeDistanceMeters, closeTo(3000.0, 1e-6));

        final tcxRoundTrip = CoreEngine.parseTcx(
          CoreEngine.exportTcx(gapPreserved.activity, const ActivityEdit()).bytes,
        );
        expect(tcxRoundTrip.activity.laps.length, 3);
        expect(
          tcxRoundTrip.activity.trackpoints.last.cumulativeDistanceMeters,
          closeTo(3000.0, 1e-3),
        );

        // Remove gap: shift Part 2 flush against Part 1
        final gapRemoved = CoreEngine.stitchActivities(
          [part1, part2],
          const StitchConfiguration(removeGap: true),
        );
        final expectedPart2Start = t0.add(const Duration(minutes: 5, seconds: 1));
        final expectedPart2End = t0.add(const Duration(minutes: 15, seconds: 1));
        expect(gapRemoved.activity.trackpoints[2].timestamp, expectedPart2Start);
        expect(gapRemoved.activity.trackpoints.last.timestamp, expectedPart2End);
        expect(
          gapRemoved.summary.duration,
          const Duration(minutes: 15, seconds: 1),
        );
        expect(gapRemoved.activity.laps.length, 3);
        expect(gapRemoved.activity.laps[1].startTime, expectedPart2Start);
        expect(gapRemoved.activity.laps[2].endTime, expectedPart2End);

        final fitRoundTrip = CoreEngine.parseFit(
          CoreEngine.exportFit(gapRemoved.activity, const ActivityEdit()).bytes,
        );
        expect(fitRoundTrip.diagnostics, isEmpty);
        expect(fitRoundTrip.activity.laps.length, 3);
        expect(fitRoundTrip.activity.trackpoints.length, 5);
        expect(
          fitRoundTrip.activity.trackpoints.last.cumulativeDistanceMeters,
          closeTo(3000.0, 0.1),
        );
      },
    );

    test(
      'warns and trims overlapping head of later Source File (earlier file wins) without blocking export',
      () async {
        final t0 = DateTime.utc(2026, 11, 20, 9, 0, 0);

        final part1 = StitchSource(
          id: 'p1',
          fileName: 'earlier.tcx',
          activity: Activity(
            title: 'Earlier Watch',
            description: '',
            sportType: SportType.running,
            availableChannels: const {Channel.heartRate, Channel.distance},
            laps: [
              Lap(
                startTime: t0,
                endTime: t0.add(const Duration(minutes: 10)),
                distanceMeters: 2000,
              ),
            ],
            trackpoints: [
              Trackpoint(
                timestamp: t0,
                cumulativeDistanceMeters: 0,
                heartRateBpm: 140,
              ),
              Trackpoint(
                timestamp: t0.add(const Duration(minutes: 10)),
                cumulativeDistanceMeters: 2000,
                heartRateBpm: 150,
              ),
            ],
          ),
        );

        // Starts at +8m (overlaps 09:08 and 09:10 with Part 1)
        final part2 = StitchSource(
          id: 'p2',
          fileName: 'later.tcx',
          activity: Activity(
            title: 'Later Watch',
            description: '',
            sportType: SportType.running,
            availableChannels: const {Channel.heartRate, Channel.distance},
            laps: const [],
            trackpoints: [
              Trackpoint(
                timestamp: t0.add(const Duration(minutes: 8)),
                cumulativeDistanceMeters: 0,
                heartRateBpm: 170,
              ),
              Trackpoint(
                timestamp: t0.add(const Duration(minutes: 10)),
                cumulativeDistanceMeters: 400,
                heartRateBpm: 172,
              ),
              Trackpoint(
                timestamp: t0.add(const Duration(minutes: 12)),
                cumulativeDistanceMeters: 800,
                heartRateBpm: 160,
              ),
              Trackpoint(
                timestamp: t0.add(const Duration(minutes: 15)),
                cumulativeDistanceMeters: 1400,
                heartRateBpm: 165,
              ),
            ],
          ),
        );

        // Completely overlapped by Part 2 (09:11..09:14 inside 09:08..09:15)
        final part3 = StitchSource(
          id: 'p3',
          fileName: 'duplicate.gpx',
          activity: Activity(
            title: 'Duplicate',
            description: '',
            sportType: SportType.running,
            availableChannels: const {Channel.gps},
            laps: const [],
            trackpoints: [
              Trackpoint(
                timestamp: t0.add(const Duration(minutes: 11)),
                latitude: 14.61,
                longitude: 120.98,
              ),
              Trackpoint(
                timestamp: t0.add(const Duration(minutes: 14)),
                latitude: 14.62,
                longitude: 120.98,
              ),
            ],
          ),
        );

        final stitched = await CoreEngine.stitchActivitiesInIsolate(
          [part2, part3, part1],
        );

        final overlapWarnings = stitched.diagnostics
            .where((d) => d.code == DiagnosticCode.stitchOverlapTrimmed)
            .toList();
        expect(overlapWarnings.length, 2);
        expect(overlapWarnings.every((d) => d.severity == DiagnosticSeverity.warning), isTrue);

        // Earlier file wins at +10m (HR 150 kept, not 172)
        final pts = stitched.activity.trackpoints;
        expect(pts.length, 4);
        expect(pts[1].timestamp, t0.add(const Duration(minutes: 10)));
        expect(pts[1].heartRateBpm, 150);
        expect(pts[1].cumulativeDistanceMeters, closeTo(2000.0, 1e-6));

        // Later file keeps +12m and +15m with continuous distance (2000 -> 2600)
        expect(pts[2].timestamp, t0.add(const Duration(minutes: 12)));
        expect(pts[2].heartRateBpm, 160);
        expect(pts[2].cumulativeDistanceMeters, closeTo(2000.0, 1e-6));
        expect(pts[3].timestamp, t0.add(const Duration(minutes: 15)));
        expect(pts[3].cumulativeDistanceMeters, closeTo(2600.0, 1e-6));

        expect(stitched.parts[1].trimmedHeadCount, 2);
        expect(stitched.parts[1].keptTrackpointCount, 2);
        expect(stitched.parts[2].trimmedHeadCount, 2);
        expect(stitched.parts[2].keptTrackpointCount, 0);

        // Export is not blocked
        final exported = CoreEngine.exportFit(
          stitched.activity,
          const ActivityEdit(),
        );
        expect(exported.bytes, isNotEmpty);
      },
    );
  });
}
