import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gpx_lab/core/core_engine.dart';

Uint8List _utf8(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  group('CoreEngine KML Seam', () {
    test(
      'parses timestamped <gx:Track> with sensor arrays, applies edits/stripping, and preserves round-trip fidelity',
      () async {
        const sampleKml = '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2"
  xmlns:gx="http://www.google.com/kml/ext/2.2">
  <Document>
    <name>Huawei Canal Run</name>
    <description>Morning aerobic loop</description>
    <ExtendedData>
      <Data name="sport"><value>running</value></Data>
      <Data name="creator"><value>HUAWEI WATCH GT 4</value></Data>
    </ExtendedData>
    <Placemark>
      <name>Start</name>
      <Point><coordinates>120.984200,14.599500,10.0</coordinates></Point>
    </Placemark>
    <Placemark>
      <name>Track</name>
      <gx:Track>
        <when>2026-11-19T06:30:00Z</when>
        <when>2026-11-19T06:30:30Z</when>
        <when>2026-11-19T06:31:00Z</when>
        <gx:coord>120.984200 14.599500 10.0</gx:coord>
        <gx:coord>120.984200 14.600400 15.0</gx:coord>
        <gx:coord>120.984200 14.601300 12.0</gx:coord>
        <ExtendedData>
          <SchemaData schemaUrl="#huaweiSchema">
            <gx:SimpleArrayData name="heartrate">
              <gx:value>142</gx:value>
              <gx:value>152</gx:value>
              <gx:value>156</gx:value>
            </gx:SimpleArrayData>
            <gx:SimpleArrayData name="cadence">
              <gx:value>84</gx:value>
              <gx:value>86</gx:value>
              <gx:value>88</gx:value>
            </gx:SimpleArrayData>
            <gx:SimpleArrayData name="power">
              <gx:value>240</gx:value>
              <gx:value>260</gx:value>
              <gx:value>275</gx:value>
            </gx:SimpleArrayData>
            <gx:SimpleArrayData name="temperature">
              <gx:value>24</gx:value>
              <gx:value>25</gx:value>
              <gx:value>25</gx:value>
            </gx:SimpleArrayData>
          </SchemaData>
        </ExtendedData>
      </gx:Track>
    </Placemark>
    <Placemark>
      <name>End</name>
      <Point><coordinates>120.984200,14.601300,12.0</coordinates></Point>
    </Placemark>
  </Document>
</kml>''';

        final parsed = await CoreEngine.parseKmlInIsolate(
          _utf8(sampleKml),
          fileName: 'huawei_canal_run.kml',
        );

        expect(parsed.diagnostics, isEmpty);
        expect(parsed.activity.title, 'Huawei Canal Run');
        expect(parsed.activity.description, 'Morning aerobic loop');
        expect(parsed.activity.sportType, SportType.running);
        expect(parsed.activity.deviceInfo, 'HUAWEI WATCH GT 4');
        expect(parsed.activity.trackpoints, hasLength(3));
        expect(
          parsed.activity.availableChannels,
          containsAll(const [
            Channel.gps,
            Channel.elevation,
            Channel.heartRate,
            Channel.cadence,
            Channel.power,
            Channel.temperature,
          ]),
        );

        expect(parsed.activity.trackpoints[0].latitude, closeTo(14.5995, 1e-6));
        expect(parsed.activity.trackpoints[0].longitude, closeTo(120.9842, 1e-6));
        expect(parsed.activity.trackpoints[0].elevationMeters, 10.0);
        expect(parsed.activity.trackpoints[1].heartRateBpm, 152);
        expect(parsed.activity.trackpoints[1].cadenceRpm, 86);
        expect(parsed.activity.trackpoints[2].powerWatts, 275);
        expect(parsed.activity.trackpoints[2].temperatureCelsius, 25);

        expect(parsed.summary.trackpointCount, 3);
        expect(parsed.summary.duration, const Duration(minutes: 1));
        expect(parsed.summary.gpsDistanceMeters, closeTo(200.15, 2.0));
        expect(parsed.summary.elevationGainMeters, closeTo(5.0, 0.01));
        expect(parsed.summary.avgHeartRateBpm, 150);
        expect(parsed.summary.maxHeartRateBpm, 156);

        // Round-trip export -> re-parse with metadata edits and channel stripping
        final exported = await CoreEngine.exportKmlInIsolate(
          parsed.activity,
          const ActivityEdit(
            title: 'Sunset Tempo KML',
            description: 'Edited in GPX Lab',
            sportType: SportType.hiking,
            strippedChannels: {
              StrippableChannel.power,
              StrippableChannel.deviceInfo,
            },
          ),
        );
        final exportedXml = utf8.decode(exported.bytes);
        expect(exportedXml, contains('<gx:Track>'));
        expect(exportedXml, isNot(contains('name="power"')));
        expect(exportedXml, isNot(contains('HUAWEI WATCH GT 4')));

        final reparsed = CoreEngine.parseKml(exported.bytes);
        expect(reparsed.diagnostics, isEmpty);
        expect(reparsed.activity.title, 'Sunset Tempo KML');
        expect(reparsed.activity.description, 'Edited in GPX Lab');
        expect(reparsed.activity.sportType, SportType.hiking);
        expect(reparsed.activity.deviceInfo, isNull);
        expect(reparsed.activity.trackpoints, hasLength(3));
        expect(reparsed.activity.availableChannels.contains(Channel.power), isFalse);
        expect(
          reparsed.activity.availableChannels,
          containsAll(const [
            Channel.gps,
            Channel.elevation,
            Channel.heartRate,
            Channel.cadence,
            Channel.temperature,
          ]),
        );
        expect(reparsed.summary.duration, const Duration(minutes: 1));
        expect(
          reparsed.summary.gpsDistanceMeters,
          closeTo(parsed.summary.gpsDistanceMeters, 0.5),
        );
        expect(reparsed.summary.avgHeartRateBpm, 150);
        expect(reparsed.summary.maxHeartRateBpm, 156);
      },
    );

    test(
      'parses timestamped <Placemark><Point> KMLs with ExtendedData telemetry',
      () {
        const placemarkKml = '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <name>Waypoint Jog</name>
    <Placemark>
      <TimeStamp><when>2026-11-19T07:00:00Z</when></TimeStamp>
      <Point><coordinates>120.984000,14.600000,12.0</coordinates></Point>
      <ExtendedData>
        <Data name="hr"><value>138</value></Data>
        <Data name="cadence"><value>82</value></Data>
      </ExtendedData>
    </Placemark>
    <Placemark>
      <TimeStamp><when>2026-11-19T07:01:00Z</when></TimeStamp>
      <Point><coordinates>120.984000,14.600900,16.0</coordinates></Point>
      <ExtendedData>
        <Data name="hr"><value>148</value></Data>
        <Data name="cadence"><value>86</value></Data>
      </ExtendedData>
    </Placemark>
  </Document>
</kml>''';

        final parsed = CoreEngine.parseKml(_utf8(placemarkKml));
        expect(parsed.diagnostics, isEmpty);
        expect(parsed.activity.title, 'Waypoint Jog');
        expect(parsed.activity.trackpoints, hasLength(2));
        expect(parsed.summary.duration, const Duration(minutes: 1));
        expect(parsed.summary.avgHeartRateBpm, 143);
        expect(parsed.activity.trackpoints[0].cadenceRpm, 82);
        expect(parsed.activity.trackpoints[1].elevationMeters, 16.0);
      },
    );

    test(
      'normalizes out-of-order trackpoints, duplicate timestamps, 0 bpm HR dropouts, and unknown extensions with diagnostics',
      () {
        const quirkyKml = '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2"
  xmlns:gx="http://www.google.com/kml/ext/2.2">
  <Document>
    <name>Quirky KML Run</name>
    <Placemark>
      <gx:Track>
        <when>2026-11-19T06:30:20Z</when>
        <when>2026-11-19T06:30:00Z</when>
        <when>2026-11-19T06:30:10Z</when>
        <when>2026-11-19T06:30:10Z</when>
        <gx:coord>120.9840 14.6010 12.0</gx:coord>
        <gx:coord>120.9840 14.6000 10.0</gx:coord>
        <gx:coord>120.9840 14.6005 11.0</gx:coord>
        <gx:coord>120.9840 14.6005 11.5</gx:coord>
        <ExtendedData>
          <SchemaData schemaUrl="#s">
            <gx:SimpleArrayData name="heartrate">
              <gx:value>160</gx:value>
              <gx:value>0</gx:value>
              <gx:value>140</gx:value>
              <gx:value>142</gx:value>
            </gx:SimpleArrayData>
            <gx:SimpleArrayData name="vertical_oscillation">
              <gx:value>85</gx:value>
              <gx:value>80</gx:value>
              <gx:value>82</gx:value>
              <gx:value>84</gx:value>
            </gx:SimpleArrayData>
          </SchemaData>
        </ExtendedData>
      </gx:Track>
    </Placemark>
  </Document>
</kml>''';

        final result = CoreEngine.parseKml(_utf8(quirkyKml));
        expect(result.activity.trackpoints, hasLength(3));
        expect(
          result.activity.trackpoints.map((t) => t.timestamp).toList(),
          [
            DateTime.utc(2026, 11, 19, 6, 30, 0),
            DateTime.utc(2026, 11, 19, 6, 30, 10),
            DateTime.utc(2026, 11, 19, 6, 30, 20),
          ],
        );
        expect(result.activity.trackpoints.first.heartRateBpm, isNull);
        expect(result.activity.trackpoints[1].heartRateBpm, 142);
        expect(result.summary.avgHeartRateBpm, 151);

        final codes = result.diagnostics.map((d) => d.code).toSet();
        expect(
          codes,
          containsAll(const [
            DiagnosticCode.outOfOrderTrackpointsSorted,
            DiagnosticCode.duplicateTimestampsNormalized,
            DiagnosticCode.zeroHeartRateDropped,
            DiagnosticCode.unsupportedExtensionsDropped,
          ]),
        );
      },
    );

    test(
      'rejects empty, non-UTF8, corrupted XML, wrong root, and untimestamped <LineString> / trackless KMLs with actionable errors',
      () {
        expect(
          () => CoreEngine.parseKml(Uint8List(0)),
          throwsA(isA<ActivityParseException>()),
        );

        expect(
          () => CoreEngine.parseKml(Uint8List.fromList([0xFF, 0xFE, 0x80])),
          throwsA(isA<ActivityParseException>()),
        );

        expect(
          () => CoreEngine.parseKml(_utf8('<kml><Document><broken')),
          throwsA(
            isA<ActivityParseException>().having(
              (e) => e.message,
              'message',
              contains('Corrupted KML XML'),
            ),
          ),
        );

        expect(
          () => CoreEngine.parseKml(_utf8('<?xml version="1.0"?><gpx/>')),
          throwsA(
            isA<ActivityParseException>().having(
              (e) => e.message,
              'message',
              contains('Expected a <kml> root element'),
            ),
          ),
        );

        const routeOnlyLineStringKml = '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <name>Planned Trail Route</name>
    <Placemark>
      <LineString>
        <coordinates>
          120.9840,14.6000,10 120.9840,14.6010,12
        </coordinates>
      </LineString>
    </Placemark>
  </Document>
</kml>''';

        expect(
          () => CoreEngine.parseKml(_utf8(routeOnlyLineStringKml)),
          throwsA(
            isA<ActivityParseException>().having(
              (e) => e.message,
              'message',
              allOf(
                contains('<LineString>'),
                contains('GPX Lab requires timestamped'),
              ),
            ),
          ),
        );

        const untimestampedGxTrackKml = '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2"
  xmlns:gx="http://www.google.com/kml/ext/2.2">
  <Document>
    <Placemark>
      <gx:Track>
        <gx:coord>120.9840 14.6000 10</gx:coord>
        <gx:coord>120.9840 14.6010 12</gx:coord>
      </gx:Track>
    </Placemark>
  </Document>
</kml>''';

        expect(
          () => CoreEngine.parseKml(_utf8(untimestampedGxTrackKml)),
          throwsA(
            isA<ActivityParseException>().having(
              (e) => e.message,
              'message',
              allOf(
                contains('without <when> timestamps'),
                contains('GPX Lab requires timestamped trackpoints.'),
              ),
            ),
          ),
        );
      },
    );

    test(
      'blocks GPS-less KML export and surfaces blocking, lossy, and Strava incompatibility warnings',
      () {
        final t0 = DateTime.utc(2026, 11, 20, 6, 0, 0);
        final t1 = DateTime.utc(2026, 11, 20, 6, 5, 0);
        final t2 = DateTime.utc(2026, 11, 20, 6, 10, 0);

        final richActivity = Activity(
          title: 'Morning Tempo',
          description: 'Intervals',
          sportType: SportType.running,
          calories: 320,
          deviceInfo: 'HUAWEI WATCH GT 4',
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
              latitude: 14.6000,
              longitude: 120.9840,
              elevationMeters: 10.0,
              cumulativeDistanceMeters: 0.0,
              heartRateBpm: 140,
              cadenceRpm: 170,
              powerWatts: 250,
              temperatureCelsius: 24,
            ),
            Trackpoint(
              timestamp: t1,
              latitude: 14.6045,
              longitude: 120.9840,
              elevationMeters: 25.0,
              cumulativeDistanceMeters: 500.0,
              heartRateBpm: 155,
              cadenceRpm: 176,
              powerWatts: 280,
              temperatureCelsius: 25,
            ),
            Trackpoint(
              timestamp: t2,
              latitude: 14.6090,
              longitude: 120.9840,
              elevationMeters: 30.0,
              cumulativeDistanceMeters: 1000.0,
              heartRateBpm: 165,
              cadenceRpm: 180,
              powerWatts: 300,
              temperatureCelsius: 26,
            ),
          ],
          laps: [
            Lap(startTime: t0, endTime: t1, distanceMeters: 500.0, calories: 150),
            Lap(startTime: t1, endTime: t2, distanceMeters: 500.0, calories: 170),
          ],
        );

        expect(
          () => CoreEngine.exportKml(
            richActivity,
            const ActivityEdit(strippedChannels: {StrippableChannel.gps}),
          ),
          throwsStateError,
        );

        final maplessActivity = Activity(
          title: 'Treadmill',
          description: '',
          sportType: SportType.running,
          trackpoints: [
            Trackpoint(
              timestamp: t0,
              cumulativeDistanceMeters: 0.0,
              heartRateBpm: 140,
            ),
            Trackpoint(
              timestamp: t1,
              cumulativeDistanceMeters: 800.0,
              heartRateBpm: 155,
            ),
          ],
          laps: [Lap(startTime: t0, endTime: t1, distanceMeters: 800.0)],
          availableChannels: const {Channel.distance, Channel.heartRate},
        );

        expect(
          () => CoreEngine.exportKml(maplessActivity, const ActivityEdit()),
          throwsStateError,
        );

        final kmlWarnings = CoreEngine.analyzeExportWarnings(
          richActivity,
          const ActivityEdit(distanceOverrideMeters: 1200.0),
          ExportFormat.kml,
        );
        expect(
          kmlWarnings.map((w) => w.code),
          containsAll(const [
            ExportWarningCode.kmlNotAcceptedByStrava,
            ExportWarningCode.kmlDropsCumulativeDistance,
            ExportWarningCode.kmlDropsLapsAndCalories,
          ]),
        );
        expect(kmlWarnings.any((w) => w.isBlocking), isFalse);

        final kmlBlockedWarnings = CoreEngine.analyzeExportWarnings(
          richActivity,
          const ActivityEdit(strippedChannels: {StrippableChannel.gps}),
          ExportFormat.kml,
        );
        expect(
          kmlBlockedWarnings.any(
            (w) => w.code == ExportWarningCode.kmlRequiresGps && w.isBlocking,
          ),
          isTrue,
        );
      },
    );

    test(
      'supports cross-format conversion, Channel Blending, and Sequential Stitching across KML, FIT, TCX, and GPX',
      () {
        const kmlMorning = '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2"
  xmlns:gx="http://www.google.com/kml/ext/2.2">
  <Document>
    <name>Huawei Morning KML</name>
    <ExtendedData><Data name="sport"><value>running</value></Data></ExtendedData>
    <Placemark>
      <gx:Track>
        <when>2026-11-20T06:00:00Z</when>
        <when>2026-11-20T06:05:00Z</when>
        <gx:coord>120.984000 14.600000 10.0</gx:coord>
        <gx:coord>120.984000 14.604500 20.0</gx:coord>
      </gx:Track>
    </Placemark>
  </Document>
</kml>''';

        const tcxOverlapping = '''<?xml version="1.0" encoding="UTF-8"?>
<TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2">
  <Activities>
    <Activity Sport="Running">
      <Id>2026-11-20T06:00:00Z</Id>
      <Lap StartTime="2026-11-20T06:00:00Z">
        <TotalTimeSeconds>300</TotalTimeSeconds>
        <DistanceMeters>510</DistanceMeters>
        <Calories>70</Calories>
        <Track>
          <Trackpoint>
            <Time>2026-11-20T06:00:00Z</Time>
            <DistanceMeters>0</DistanceMeters>
            <HeartRateBpm><Value>145</Value></HeartRateBpm>
            <Cadence>85</Cadence>
          </Trackpoint>
          <Trackpoint>
            <Time>2026-11-20T06:05:00Z</Time>
            <DistanceMeters>510</DistanceMeters>
            <HeartRateBpm><Value>160</Value></HeartRateBpm>
            <Cadence>90</Cadence>
          </Trackpoint>
        </Track>
      </Lap>
    </Activity>
  </Activities>
</TrainingCenterDatabase>''';

        const gpxAfternoon = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="Test" xmlns="http://www.topografix.com/GPX/1/1">
  <trk>
    <name>Cool Down</name>
    <type>running</type>
    <trkseg>
      <trkpt lat="14.604500" lon="120.984000">
        <ele>20.0</ele>
        <time>2026-11-20T06:10:00Z</time>
      </trkpt>
      <trkpt lat="14.609000" lon="120.984000">
        <ele>25.0</ele>
        <time>2026-11-20T06:15:00Z</time>
      </trkpt>
    </trkseg>
  </trk>
</gpx>''';

        final kmlParsed = CoreEngine.parseKml(_utf8(kmlMorning));
        final tcxParsed = CoreEngine.parseTcx(_utf8(tcxOverlapping));
        final gpxParsed = CoreEngine.parseGpx(_utf8(gpxAfternoon));

        // Cross-format conversion: KML -> FIT, TCX, GPX -> KML
        final fitBytes =
            CoreEngine.exportFit(kmlParsed.activity, const ActivityEdit()).bytes;
        final fitReparsed = CoreEngine.parseFit(fitBytes);
        expect(fitReparsed.activity.trackpoints, hasLength(2));

        final tcxBytes =
            CoreEngine.exportTcx(kmlParsed.activity, const ActivityEdit()).bytes;
        final tcxReparsed = CoreEngine.parseTcx(tcxBytes);
        expect(tcxReparsed.activity.trackpoints, hasLength(2));

        final gpxBytes =
            CoreEngine.exportGpx(kmlParsed.activity, const ActivityEdit()).bytes;
        final gpxReparsed = CoreEngine.parseGpx(gpxBytes);
        expect(gpxReparsed.activity.trackpoints, hasLength(2));

        final kmlFromTcxBytes = CoreEngine.exportKml(
          tcxParsed.activity.copyWith(
            trackpoints: kmlParsed.activity.trackpoints,
            availableChannels: {
              ...kmlParsed.activity.availableChannels,
              Channel.heartRate,
            },
          ),
          const ActivityEdit(title: 'Blended KML'),
        ).bytes;
        final reparsedFromTcx = CoreEngine.parseKml(kmlFromTcxBytes);
        expect(reparsedFromTcx.activity.title, 'Blended KML');

        // Channel Blending: KML (GPS + Elevation) + TCX (HR + Cadence + Distance)
        final blendSources = [
          BlendSource(
            id: 'kml',
            fileName: 'morning.kml',
            activity: kmlParsed.activity,
          ),
          BlendSource(
            id: 'tcx',
            fileName: 'sensor.tcx',
            activity: tcxParsed.activity,
          ),
        ];
        final blendConfig = CoreEngine.defaultBlendConfiguration(blendSources);
        final blended = CoreEngine.blendActivities(blendSources, blendConfig);
        expect(
          blended.activity.availableChannels,
          containsAll(const [
            Channel.gps,
            Channel.elevation,
            Channel.distance,
            Channel.heartRate,
            Channel.cadence,
          ]),
        );
        expect(blended.activity.trackpoints[0].heartRateBpm, 145);
        expect(blended.activity.trackpoints[1].elevationMeters, 20.0);

        // Sequential Stitching: KML + GPX
        final stitched = CoreEngine.stitchActivities([
          StitchSource(
            id: 'part1',
            fileName: 'morning.kml',
            activity: kmlParsed.activity,
          ),
          StitchSource(
            id: 'part2',
            fileName: 'cooldown.gpx',
            activity: gpxParsed.activity,
          ),
        ]);
        expect(stitched.parts, hasLength(2));
        expect(stitched.activity.trackpoints, hasLength(4));
        expect(stitched.activity.laps, hasLength(2));
        expect(stitched.summary.gpsDistanceMeters, greaterThan(950.0));
      },
    );
  });
}
