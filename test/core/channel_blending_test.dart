import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sync_it/core/core_engine.dart';

Uint8List _utf8(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  group('CoreEngine Channel Blending Seam', () {
    test(
      'blends GPX (GPS + elevation) and TCX (heart rate + cadence) on exact timestamps',
      () {
        const gpxXml = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="Huawei Health"
  xmlns="http://www.topografix.com/GPX/1/1">
  <trk>
    <name>Morning Run</name>
    <type>running</type>
    <trkseg>
      <trkpt lat="14.600000" lon="120.984000">
        <ele>10.0</ele>
        <time>2026-11-20T06:00:00Z</time>
      </trkpt>
      <trkpt lat="14.600900" lon="120.984000">
        <ele>14.0</ele>
        <time>2026-11-20T06:00:10Z</time>
      </trkpt>
      <trkpt lat="14.601800" lon="120.984000">
        <ele>18.0</ele>
        <time>2026-11-20T06:00:20Z</time>
      </trkpt>
    </trkseg>
  </trk>
</gpx>''';

        const tcxXml = '''<?xml version="1.0" encoding="UTF-8"?>
<TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2">
  <Activities>
    <Activity Sport="Running">
      <Id>2026-11-20T06:00:00Z</Id>
      <Lap StartTime="2026-11-20T06:00:00Z">
        <TotalTimeSeconds>20</TotalTimeSeconds>
        <DistanceMeters>200</DistanceMeters>
        <Calories>25</Calories>
        <Track>
          <Trackpoint>
            <Time>2026-11-20T06:00:00Z</Time>
            <DistanceMeters>0</DistanceMeters>
            <HeartRateBpm><Value>140</Value></HeartRateBpm>
            <Cadence>85</Cadence>
          </Trackpoint>
          <Trackpoint>
            <Time>2026-11-20T06:00:10Z</Time>
            <DistanceMeters>100</DistanceMeters>
            <HeartRateBpm><Value>150</Value></HeartRateBpm>
            <Cadence>88</Cadence>
          </Trackpoint>
          <Trackpoint>
            <Time>2026-11-20T06:00:20Z</Time>
            <DistanceMeters>200</DistanceMeters>
            <HeartRateBpm><Value>160</Value></HeartRateBpm>
            <Cadence>90</Cadence>
          </Trackpoint>
        </Track>
      </Lap>
    </Activity>
  </Activities>
</TrainingCenterDatabase>''';

        final gpxResult = CoreEngine.parseGpx(
          _utf8(gpxXml),
          fileName: 'route.gpx',
        );
        final tcxResult = CoreEngine.parseTcx(
          _utf8(tcxXml),
          fileName: 'sensor.tcx',
        );

        final sources = [
          BlendSource(
            id: 'gpx',
            fileName: 'route.gpx',
            activity: gpxResult.activity,
            diagnostics: gpxResult.diagnostics,
          ),
          BlendSource(
            id: 'tcx',
            fileName: 'sensor.tcx',
            activity: tcxResult.activity,
            diagnostics: tcxResult.diagnostics,
          ),
        ];

        final config = CoreEngine.defaultBlendConfiguration(sources);
        expect(config.baseSourceId, 'gpx');
        expect(config.channelSources[Channel.gps], 'gpx');
        expect(config.channelSources[Channel.elevation], 'gpx');
        expect(config.channelSources[Channel.heartRate], 'tcx');
        expect(config.channelSources[Channel.cadence], 'tcx');
        expect(config.channelSources[Channel.distance], 'tcx');

        final blended = CoreEngine.blendActivities(sources, config);
        expect(blended.activity.trackpoints.length, 3);
        expect(
          blended.activity.availableChannels,
          containsAll([
            Channel.gps,
            Channel.elevation,
            Channel.distance,
            Channel.heartRate,
            Channel.cadence,
          ]),
        );

        final pt1 = blended.activity.trackpoints[1];
        expect(pt1.latitude, closeTo(14.600900, 1e-6));
        expect(pt1.elevationMeters, closeTo(14.0, 1e-6));
        expect(pt1.cumulativeDistanceMeters, closeTo(100.0, 1e-6));
        expect(pt1.heartRateBpm, 150);
        expect(pt1.cadenceRpm, 88);

        expect(blended.summary.avgHeartRateBpm, 150);
        expect(blended.summary.maxHeartRateBpm, 160);
        expect(blended.summary.elevationGainMeters, closeTo(8.0, 1e-6));
      },
    );

    test(
      'interpolates numeric Channels and GPS within ±5s and leaves out-of-tolerance gaps null',
      () {
        final t0 = DateTime.utc(2026, 11, 20, 7, 0, 0);
        final baseActivity = Activity(
          title: 'Base',
          description: '',
          sportType: SportType.cycling,
          availableChannels: const {Channel.power},
          laps: const [],
          trackpoints: [
            // Exact match at +0s
            Trackpoint(timestamp: t0, powerWatts: 200),
            // Midpoint between +0s and +4s -> +2s (within ±5s of both)
            Trackpoint(
              timestamp: t0.add(const Duration(seconds: 2)),
              powerWatts: 210,
            ),
            // Exact boundary +5s after +4s -> +9s (5s from +4s, 7s from +16s)
            Trackpoint(
              timestamp: t0.add(const Duration(seconds: 9)),
              powerWatts: 220,
            ),
            // Dropout center at +10s (6s from +4s, 6s from +16s -> both > 5s!)
            Trackpoint(
              timestamp: t0.add(const Duration(seconds: 10)),
              powerWatts: 230,
            ),
            // +18s (2s after +16s)
            Trackpoint(
              timestamp: t0.add(const Duration(seconds: 18)),
              powerWatts: 240,
            ),
          ],
        );

        final secondaryActivity = Activity(
          title: 'GPS + HR',
          description: '',
          sportType: SportType.cycling,
          availableChannels: const {Channel.gps, Channel.heartRate},
          laps: const [],
          trackpoints: [
            Trackpoint(
              timestamp: t0,
              latitude: 14.600000,
              longitude: 120.980000,
              heartRateBpm: 140,
            ),
            Trackpoint(
              timestamp: t0.add(const Duration(seconds: 4)),
              latitude: 14.600400,
              longitude: 120.980800,
              heartRateBpm: 148,
            ),
            // 12-second dropout gap between +4s and +16s
            Trackpoint(
              timestamp: t0.add(const Duration(seconds: 16)),
              latitude: 14.602000,
              longitude: 120.982000,
              heartRateBpm: 160,
            ),
          ],
        );

        final sources = [
          BlendSource(id: 'base', fileName: 'pwr.fit', activity: baseActivity),
          BlendSource(
            id: 'sec',
            fileName: 'gps_hr.gpx',
            activity: secondaryActivity,
          ),
        ];

        final config = CoreEngine.defaultBlendConfiguration(sources);
        final blended = CoreEngine.blendActivities(sources, config);
        final pts = blended.activity.trackpoints;

        // +0s exact match
        expect(pts[0].latitude, closeTo(14.600000, 1e-7));
        expect(pts[0].longitude, closeTo(120.980000, 1e-7));
        expect(pts[0].heartRateBpm, 140);

        // +2s linear interpolation between +0s and +4s (t = 0.5)
        expect(pts[1].latitude, closeTo(14.600200, 1e-7));
        expect(pts[1].longitude, closeTo(120.980400, 1e-7));
        expect(pts[1].heartRateBpm, 144);

        // +9s: +4s is within 5s (5000ms), +16s is 7s away (>5s) -> clamps to +4s without interpolating across dropout
        expect(pts[2].latitude, closeTo(14.600400, 1e-7));
        expect(pts[2].heartRateBpm, 148);

        // +10s: 6s from +4s and 6s from +16s -> outside ±5s -> null!
        expect(pts[3].latitude, isNull);
        expect(pts[3].longitude, isNull);
        expect(pts[3].heartRateBpm, isNull);
        expect(pts[3].powerWatts, 230);

        // +18s: 2s after +16s -> within ±5s of +16s
        expect(pts[4].latitude, closeTo(14.602000, 1e-7));
        expect(pts[4].heartRateBpm, 160);
      },
    );

    test(
      'supports 3-file blending, Base Timeline switching, metadata overrides, lap recomputation, and isolate execution',
      () async {
        final t0 = DateTime.utc(2026, 11, 20, 8, 0, 0);
        final t1 = t0.add(const Duration(seconds: 30));
        final t2 = t0.add(const Duration(seconds: 60));

        final gpxSource = BlendSource(
          id: 's1',
          fileName: 'watch.gpx',
          activity: Activity(
            title: 'Watch Track',
            description: 'GPX',
            sportType: SportType.walking,
            calories: 100,
            deviceInfo: 'Watch GPX',
            availableChannels: const {Channel.gps, Channel.elevation},
            laps: [Lap(startTime: t0, endTime: t2)],
            trackpoints: [
              Trackpoint(
                timestamp: t0,
                latitude: 14.6000,
                longitude: 120.9800,
                elevationMeters: 10,
              ),
              Trackpoint(
                timestamp: t1,
                latitude: 14.6010,
                longitude: 120.9800,
                elevationMeters: 15,
              ),
              Trackpoint(
                timestamp: t2,
                latitude: 14.6020,
                longitude: 120.9800,
                elevationMeters: 20,
              ),
            ],
          ),
        );

        final tcxSource = BlendSource(
          id: 's2',
          fileName: 'hr_strap.tcx',
          activity: Activity(
            title: 'HR Strap',
            description: 'TCX',
            sportType: SportType.running,
            calories: 250,
            deviceInfo: 'Polar H10',
            availableChannels: const {Channel.heartRate, Channel.distance},
            laps: [
              Lap(startTime: t0, endTime: t1, distanceMeters: 110, calories: 120),
              Lap(startTime: t1, endTime: t2, distanceMeters: 115, calories: 130),
            ],
            trackpoints: [
              Trackpoint(
                timestamp: t0,
                heartRateBpm: 130,
                cumulativeDistanceMeters: 0,
              ),
              Trackpoint(
                timestamp: t1,
                heartRateBpm: 150,
                cumulativeDistanceMeters: 110,
              ),
              Trackpoint(
                timestamp: t2,
                heartRateBpm: 170,
                cumulativeDistanceMeters: 225,
              ),
            ],
          ),
        );

        // Export a real FIT file as the 3rd source to verify binary FIT participation
        final fitBytes = CoreEngine.exportFit(
          Activity(
            title: 'Pod',
            description: '',
            sportType: SportType.running,
            deviceInfo: 'Stryd Pod',
            availableChannels: const {
              Channel.cadence,
              Channel.power,
              Channel.temperature,
            },
            laps: const [],
            trackpoints: [
              Trackpoint(
                timestamp: t0,
                cadenceRpm: 170,
                powerWatts: 250,
                temperatureCelsius: 22,
              ),
              Trackpoint(
                timestamp: t1,
                cadenceRpm: 176,
                powerWatts: 270,
                temperatureCelsius: 23,
              ),
              Trackpoint(
                timestamp: t2,
                cadenceRpm: 180,
                powerWatts: 290,
                temperatureCelsius: 24,
              ),
            ],
          ),
          const ActivityEdit(),
        ).bytes;
        final fitParsed = CoreEngine.parseFit(fitBytes, fileName: 'pod.fit');
        final fitSource = BlendSource(
          id: 's3',
          fileName: 'pod.fit',
          activity: fitParsed.activity,
          diagnostics: fitParsed.diagnostics,
        );

        final sources = [gpxSource, tcxSource, fitSource];
        final config = BlendConfiguration(
          baseSourceId: 's1',
          channelSources: const {
            Channel.gps: 's1',
            Channel.elevation: 's1',
            Channel.heartRate: 's2',
            Channel.distance: 's2',
            Channel.cadence: 's3',
            Channel.power: 's3',
            Channel.temperature: 's3',
          },
          lapsSourceId: 's2',
          caloriesSourceId: 's2',
          sportTypeSourceId: 's2',
          deviceInfoSourceId: 's3',
        );

        final blended = await CoreEngine.blendActivitiesInIsolate(
          sources,
          config,
        );
        expect(blended.activity.sportType, SportType.running);
        expect(blended.activity.calories, 250);
        expect(blended.activity.deviceInfo, 'Stryd Pod');
        expect(blended.activity.laps.length, 2);

        // Lap summaries recomputed from blended trackpoints
        expect(blended.activity.laps[0].avgHeartRateBpm, 140);
        expect(blended.activity.laps[0].maxHeartRateBpm, 150);
        expect(blended.activity.laps[0].distanceMeters, closeTo(110, 1e-6));
        expect(blended.activity.laps[1].avgHeartRateBpm, 160);
        expect(blended.activity.laps[1].maxHeartRateBpm, 170);
        expect(blended.activity.laps[1].distanceMeters, closeTo(115, 1e-6));

        expect(blended.activity.trackpoints[1].powerWatts, 270);
        expect(blended.activity.trackpoints[1].temperatureCelsius, 23);
      },
    );
  });
}
