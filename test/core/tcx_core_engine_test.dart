import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gpx_lab/core/core_engine.dart';

Uint8List _utf8(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  group('CoreEngine TCX Seam', () {
    test('rejects empty, non-UTF8, malformed XML, and trackpoint-less TCX files with actionable errors', () {
      expect(
        () => CoreEngine.parseTcx(Uint8List(0)),
        throwsA(isA<ActivityParseException>()),
      );

      expect(
        () => CoreEngine.parseTcx(Uint8List.fromList([0xFF, 0xFE, 0x80])),
        throwsA(isA<ActivityParseException>()),
      );

      expect(
        () => CoreEngine.parseTcx(_utf8('<TrainingCenterDatabase><unclosed>')),
        throwsA(isA<ActivityParseException>()),
      );

      expect(
        () => CoreEngine.parseTcx(_utf8('<?xml version="1.0"?><gpx/>')),
        throwsA(isA<ActivityParseException>()),
      );

      expect(
        () => CoreEngine.parseTcx(
          _utf8('''<?xml version="1.0" encoding="UTF-8"?>
<TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2">
  <Activities/>
</TrainingCenterDatabase>'''),
        ),
        throwsA(isA<ActivityParseException>()),
      );

      expect(
        () => CoreEngine.parseTcx(
          _utf8('''<?xml version="1.0" encoding="UTF-8"?>
<TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2">
  <Activities>
    <Activity Sport="Running">
      <Id>2026-11-19T06:00:00Z</Id>
      <Lap StartTime="2026-11-19T06:00:00Z">
        <Track/>
      </Lap>
    </Activity>
  </Activities>
</TrainingCenterDatabase>'''),
        ),
        throwsA(isA<ActivityParseException>()),
      );
    });

    test('parses Huawei Health-style multi-Lap TCX with Creator, cumulative distance, and extensions', () async {
      const huaweiTcx = '''<?xml version="1.0" encoding="UTF-8"?>
<TrainingCenterDatabase
  xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xmlns:ns3="http://www.garmin.com/xmlschemas/ActivityExtension/v2">
  <Activities>
    <Activity Sport="Running">
      <Id>2026-11-19T06:00:00Z</Id>
      <Lap StartTime="2026-11-19T06:00:00Z">
        <TotalTimeSeconds>30.0</TotalTimeSeconds>
        <DistanceMeters>105.0</DistanceMeters>
        <Calories>15</Calories>
        <AverageHeartRateBpm><Value>145</Value></AverageHeartRateBpm>
        <MaximumHeartRateBpm><Value>150</Value></MaximumHeartRateBpm>
        <Intensity>Active</Intensity>
        <TriggerMethod>Manual</TriggerMethod>
        <Track>
          <Trackpoint>
            <Time>2026-11-19T06:00:00Z</Time>
            <Position>
              <LatitudeDegrees>14.599500</LatitudeDegrees>
              <LongitudeDegrees>120.984200</LongitudeDegrees>
            </Position>
            <AltitudeMeters>10.0</AltitudeMeters>
            <DistanceMeters>0.0</DistanceMeters>
            <HeartRateBpm><Value>140</Value></HeartRateBpm>
            <Extensions>
              <ns3:TPX>
                <ns3:RunCadence>84</ns3:RunCadence>
                <ns3:Watts>240</ns3:Watts>
              </ns3:TPX>
            </Extensions>
          </Trackpoint>
          <Trackpoint>
            <Time>2026-11-19T06:00:30Z</Time>
            <Position>
              <LatitudeDegrees>14.600400</LatitudeDegrees>
              <LongitudeDegrees>120.984200</LongitudeDegrees>
            </Position>
            <AltitudeMeters>14.0</AltitudeMeters>
            <DistanceMeters>105.0</DistanceMeters>
            <HeartRateBpm><Value>150</Value></HeartRateBpm>
            <Extensions>
              <ns3:TPX>
                <ns3:RunCadence>86</ns3:RunCadence>
                <ns3:Watts>260</ns3:Watts>
              </ns3:TPX>
            </Extensions>
          </Trackpoint>
        </Track>
      </Lap>
      <Lap StartTime="2026-11-19T06:00:30Z">
        <TotalTimeSeconds>30.0</TotalTimeSeconds>
        <DistanceMeters>110.0</DistanceMeters>
        <Calories>18</Calories>
        <AverageHeartRateBpm><Value>158</Value></AverageHeartRateBpm>
        <MaximumHeartRateBpm><Value>162</Value></MaximumHeartRateBpm>
        <Intensity>Active</Intensity>
        <TriggerMethod>Manual</TriggerMethod>
        <Track>
          <Trackpoint>
            <Time>2026-11-19T06:01:00Z</Time>
            <Position>
              <LatitudeDegrees>14.601300</LatitudeDegrees>
              <LongitudeDegrees>120.984200</LongitudeDegrees>
            </Position>
            <AltitudeMeters>12.0</AltitudeMeters>
            <DistanceMeters>215.0</DistanceMeters>
            <HeartRateBpm><Value>162</Value></HeartRateBpm>
            <Extensions>
              <ns3:TPX>
                <ns3:RunCadence>90</ns3:RunCadence>
                <ns3:Watts>280</ns3:Watts>
              </ns3:TPX>
            </Extensions>
          </Trackpoint>
        </Track>
      </Lap>
      <Notes>Huawei Morning Run</Notes>
      <Creator xsi:type="Device_t">
        <Name>HUAWEI WATCH GT 4</Name>
      </Creator>
    </Activity>
  </Activities>
</TrainingCenterDatabase>''';

      final parsed = await CoreEngine.parseTcxInIsolate(
        _utf8(huaweiTcx),
        fileName: 'huawei_run.tcx',
      );

      expect(parsed.diagnostics, isEmpty);
      expect(parsed.activity.title, 'Huawei Morning Run');
      expect(parsed.activity.sportType, SportType.running);
      expect(parsed.activity.deviceInfo, 'HUAWEI WATCH GT 4');
      expect(parsed.activity.calories, 33);
      expect(parsed.activity.trackpoints, hasLength(3));
      expect(
        parsed.activity.availableChannels,
        containsAll(const [
          Channel.gps,
          Channel.elevation,
          Channel.distance,
          Channel.heartRate,
          Channel.cadence,
          Channel.power,
        ]),
      );

      expect(parsed.activity.trackpoints[0].cumulativeDistanceMeters, 0.0);
      expect(parsed.activity.trackpoints[1].cumulativeDistanceMeters, 105.0);
      expect(parsed.activity.trackpoints[2].cumulativeDistanceMeters, 215.0);
      expect(parsed.activity.trackpoints[0].cadenceRpm, 84);
      expect(parsed.activity.trackpoints[0].powerWatts, 240);

      expect(parsed.activity.laps, hasLength(2));
      expect(parsed.activity.laps[0].distanceMeters, 105.0);
      expect(parsed.activity.laps[0].calories, 15);
      expect(parsed.activity.laps[0].avgHeartRateBpm, 145);
      expect(parsed.activity.laps[0].maxHeartRateBpm, 150);
      expect(parsed.activity.laps[0].avgCadenceRpm, 85);
      expect(parsed.activity.laps[0].maxCadenceRpm, 86);
      expect(parsed.activity.laps[1].distanceMeters, 110.0);
      expect(parsed.activity.laps[1].calories, 18);
      expect(parsed.summary.lapCount, 2);
      expect(parsed.summary.calories, 33);
    });

    test('normalizes missing first-point distance, 0 bpm HR dropouts, out-of-order trackpoints, duplicate timestamps, and unsupported extensions with diagnostics', () {
      const quirkyTcx = '''<?xml version="1.0" encoding="UTF-8"?>
<TrainingCenterDatabase
  xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2"
  xmlns:ns3="http://www.garmin.com/xmlschemas/ActivityExtension/v2"
  xmlns:vendor="http://example.com/vendor">
  <Activities>
    <Activity Sport="Running">
      <Id>2026-11-19T06:30:00Z</Id>
      <Lap StartTime="2026-11-19T06:30:00Z">
        <TotalTimeSeconds>30.0</TotalTimeSeconds>
        <DistanceMeters>100.0</DistanceMeters>
        <Calories>20</Calories>
        <Track>
          <Trackpoint>
            <Time>2026-11-19T06:30:20Z</Time>
            <DistanceMeters>70.0</DistanceMeters>
            <HeartRateBpm><Value>152</Value></HeartRateBpm>
            <Extensions>
              <vendor:GroundContactTime>235</vendor:GroundContactTime>
            </Extensions>
          </Trackpoint>
          <Trackpoint>
            <Time>2026-11-19T06:30:00Z</Time>
            <HeartRateBpm><Value>0</Value></HeartRateBpm>
          </Trackpoint>
          <Trackpoint>
            <Time>2026-11-19T06:30:20Z</Time>
            <DistanceMeters>70.0</DistanceMeters>
            <HeartRateBpm><Value>154</Value></HeartRateBpm>
          </Trackpoint>
          <Trackpoint>
            <Time>2026-11-19T06:30:30Z</Time>
            <DistanceMeters>100.0</DistanceMeters>
            <HeartRateBpm><Value>158</Value></HeartRateBpm>
          </Trackpoint>
        </Track>
      </Lap>
      <Notes>Quirky TCX</Notes>
    </Activity>
  </Activities>
</TrainingCenterDatabase>''';

      final parsed = CoreEngine.parseTcx(_utf8(quirkyTcx));
      expect(parsed.activity.trackpoints, hasLength(3));
      expect(
        parsed.activity.trackpoints[0].timestamp,
        DateTime.utc(2026, 11, 19, 6, 30, 0),
      );
      expect(parsed.activity.trackpoints[0].cumulativeDistanceMeters, 0.0);
      expect(parsed.activity.trackpoints[0].heartRateBpm, isNull);
      expect(parsed.activity.trackpoints[1].heartRateBpm, 154);
      expect(parsed.activity.trackpoints[2].cumulativeDistanceMeters, 100.0);

      final codes = parsed.diagnostics.map((d) => d.code).toSet();
      expect(
        codes,
        containsAll(const [
          DiagnosticCode.outOfOrderTrackpointsSorted,
          DiagnosticCode.duplicateTimestampsNormalized,
          DiagnosticCode.zeroHeartRateDropped,
          DiagnosticCode.unsupportedExtensionsDropped,
          DiagnosticCode.missingFirstPointDistanceNormalized,
        ]),
      );
    });

    test('TCX -> TCX round-trip preserves recorded cumulative distance verbatim and recomputes Lap summaries', () async {
      const sourceTcx = '''<?xml version="1.0" encoding="UTF-8"?>
<TrainingCenterDatabase
  xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xmlns:ns3="http://www.garmin.com/xmlschemas/ActivityExtension/v2">
  <Activities>
    <Activity Sport="Running">
      <Id>2026-11-19T06:00:00Z</Id>
      <Lap StartTime="2026-11-19T06:00:00Z">
        <TotalTimeSeconds>30.0</TotalTimeSeconds>
        <DistanceMeters>999.0</DistanceMeters>
        <Calories>15</Calories>
        <Track>
          <Trackpoint>
            <Time>2026-11-19T06:00:00Z</Time>
            <Position>
              <LatitudeDegrees>14.599500</LatitudeDegrees>
              <LongitudeDegrees>120.984200</LongitudeDegrees>
            </Position>
            <AltitudeMeters>10.0</AltitudeMeters>
            <DistanceMeters>0.0</DistanceMeters>
            <HeartRateBpm><Value>140</Value></HeartRateBpm>
            <Extensions><ns3:TPX><ns3:RunCadence>84</ns3:RunCadence></ns3:TPX></Extensions>
          </Trackpoint>
          <Trackpoint>
            <Time>2026-11-19T06:00:30Z</Time>
            <Position>
              <LatitudeDegrees>14.600400</LatitudeDegrees>
              <LongitudeDegrees>120.984200</LongitudeDegrees>
            </Position>
            <AltitudeMeters>14.0</AltitudeMeters>
            <DistanceMeters>112.5</DistanceMeters>
            <HeartRateBpm><Value>150</Value></HeartRateBpm>
            <Extensions><ns3:TPX><ns3:RunCadence>86</ns3:RunCadence></ns3:TPX></Extensions>
          </Trackpoint>
        </Track>
      </Lap>
      <Lap StartTime="2026-11-19T06:00:30Z">
        <TotalTimeSeconds>30.0</TotalTimeSeconds>
        <DistanceMeters>999.0</DistanceMeters>
        <Calories>18</Calories>
        <Track>
          <Trackpoint>
            <Time>2026-11-19T06:01:00Z</Time>
            <Position>
              <LatitudeDegrees>14.601300</LatitudeDegrees>
              <LongitudeDegrees>120.984200</LongitudeDegrees>
            </Position>
            <AltitudeMeters>12.0</AltitudeMeters>
            <DistanceMeters>230.0</DistanceMeters>
            <HeartRateBpm><Value>162</Value></HeartRateBpm>
            <Extensions><ns3:TPX><ns3:RunCadence>90</ns3:RunCadence></ns3:TPX></Extensions>
          </Trackpoint>
        </Track>
      </Lap>
      <Notes>Watch Run</Notes>
      <Creator xsi:type="Device_t"><Name>HUAWEI WATCH GT 4</Name></Creator>
    </Activity>
  </Activities>
</TrainingCenterDatabase>''';

      final parsed = CoreEngine.parseTcx(_utf8(sourceTcx));
      final exported = await CoreEngine.exportTcxInIsolate(
        parsed.activity,
        const ActivityEdit(
          title: 'Edited Watch Run',
          description: 'Preserved watch distance',
          sportType: SportType.running,
        ),
      );
      final reparsed = CoreEngine.parseTcx(exported.bytes);

      expect(reparsed.diagnostics, isEmpty);
      expect(reparsed.activity.title, 'Edited Watch Run');
      expect(reparsed.activity.description, 'Preserved watch distance');
      expect(reparsed.activity.deviceInfo, 'HUAWEI WATCH GT 4');

      // Recorded cumulative distance is preserved verbatim (230.0m, NOT ~200.15m Haversine).
      expect(reparsed.activity.trackpoints[0].cumulativeDistanceMeters, 0.0);
      expect(reparsed.activity.trackpoints[1].cumulativeDistanceMeters, 112.5);
      expect(reparsed.activity.trackpoints[2].cumulativeDistanceMeters, 230.0);

      // Lap summaries are recomputed so summed lap distances match terminal trackpoint distance.
      expect(reparsed.activity.laps, hasLength(2));
      expect(reparsed.activity.laps[0].distanceMeters, closeTo(112.5, 0.01));
      expect(reparsed.activity.laps[1].distanceMeters, closeTo(117.5, 0.01));
      final summedLapDist = reparsed.activity.laps
          .fold<double>(0.0, (sum, l) => sum + (l.distanceMeters ?? 0.0));
      expect(
        summedLapDist,
        closeTo(reparsed.activity.trackpoints.last.cumulativeDistanceMeters!, 0.01),
      );
      expect(reparsed.activity.laps[0].avgHeartRateBpm, 145);
      expect(reparsed.activity.laps[0].maxHeartRateBpm, 150);
      expect(reparsed.activity.laps[0].avgCadenceRpm, 85);
      expect(reparsed.activity.laps[0].maxCadenceRpm, 86);
      expect(reparsed.activity.laps[0].calories, 15);
      expect(reparsed.activity.laps[1].calories, 18);
    });

    test('GPX -> TCX conversion synthesizes monotonic cumulative distance from 2D Haversine', () async {
      const sampleGpx = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="GPX Lab Test"
  xmlns="http://www.topografix.com/GPX/1/1"
  xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1">
  <trk>
    <name>City Loop</name>
    <type>running</type>
    <trkseg>
      <trkpt lat="14.599500" lon="120.984200">
        <ele>10.0</ele>
        <time>2026-11-19T07:00:00Z</time>
        <extensions><gpxtpx:TrackPointExtension><gpxtpx:hr>140</gpxtpx:hr><gpxtpx:cad>82</gpxtpx:cad></gpxtpx:TrackPointExtension></extensions>
      </trkpt>
      <trkpt lat="14.600400" lon="120.984200">
        <ele>14.0</ele>
        <time>2026-11-19T07:00:30Z</time>
        <extensions><gpxtpx:TrackPointExtension><gpxtpx:hr>150</gpxtpx:hr><gpxtpx:cad>84</gpxtpx:cad></gpxtpx:TrackPointExtension></extensions>
      </trkpt>
      <trkpt lat="14.601300" lon="120.984200">
        <ele>12.0</ele>
        <time>2026-11-19T07:01:00Z</time>
        <extensions><gpxtpx:TrackPointExtension><gpxtpx:hr>160</gpxtpx:hr><gpxtpx:cad>86</gpxtpx:cad></gpxtpx:TrackPointExtension></extensions>
      </trkpt>
    </trkseg>
  </trk>
</gpx>''';

      final gpxParsed = CoreEngine.parseGpx(_utf8(sampleGpx));
      expect(gpxParsed.activity.trackpoints.first.cumulativeDistanceMeters, isNull);

      final tcxExported = CoreEngine.exportTcx(
        gpxParsed.activity,
        const ActivityEdit(title: 'City Loop TCX', sportType: SportType.running),
      );
      final tcxReparsed = CoreEngine.parseTcx(tcxExported.bytes);

      expect(tcxReparsed.diagnostics, isEmpty);
      expect(tcxReparsed.activity.title, 'City Loop TCX');
      expect(tcxReparsed.activity.trackpoints, hasLength(3));
      expect(tcxReparsed.activity.trackpoints[0].cumulativeDistanceMeters, 0.0);
      expect(
        tcxReparsed.activity.trackpoints[1].cumulativeDistanceMeters!,
        greaterThan(90.0),
      );
      expect(
        tcxReparsed.activity.trackpoints[2].cumulativeDistanceMeters!,
        closeTo(gpxParsed.summary.gpsDistanceMeters, 0.5),
      );
      expect(
        tcxReparsed.activity.laps.single.distanceMeters!,
        closeTo(tcxReparsed.activity.trackpoints.last.cumulativeDistanceMeters!, 0.01),
      );
    });

    test('TCX -> GPX conversion preserves trackpoints, channels, and metadata', () {
      const sampleTcx = '''<?xml version="1.0" encoding="UTF-8"?>
<TrainingCenterDatabase
  xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2"
  xmlns:ns3="http://www.garmin.com/xmlschemas/ActivityExtension/v2">
  <Activities>
    <Activity Sport="Biking">
      <Id>2026-11-19T08:00:00Z</Id>
      <Lap StartTime="2026-11-19T08:00:00Z">
        <TotalTimeSeconds>30.0</TotalTimeSeconds>
        <DistanceMeters>250.0</DistanceMeters>
        <Track>
          <Trackpoint>
            <Time>2026-11-19T08:00:00Z</Time>
            <Position><LatitudeDegrees>14.5995</LatitudeDegrees><LongitudeDegrees>120.9842</LongitudeDegrees></Position>
            <AltitudeMeters>10.0</AltitudeMeters>
            <DistanceMeters>0.0</DistanceMeters>
            <HeartRateBpm><Value>135</Value></HeartRateBpm>
            <Cadence>88</Cadence>
          </Trackpoint>
          <Trackpoint>
            <Time>2026-11-19T08:00:30Z</Time>
            <Position><LatitudeDegrees>14.6015</LatitudeDegrees><LongitudeDegrees>120.9842</LongitudeDegrees></Position>
            <AltitudeMeters>15.0</AltitudeMeters>
            <DistanceMeters>250.0</DistanceMeters>
            <HeartRateBpm><Value>145</Value></HeartRateBpm>
            <Cadence>92</Cadence>
          </Trackpoint>
        </Track>
      </Lap>
      <Notes>Morning Spin</Notes>
    </Activity>
  </Activities>
</TrainingCenterDatabase>''';

      final tcxParsed = CoreEngine.parseTcx(_utf8(sampleTcx));
      final gpxExported = CoreEngine.exportGpx(
        tcxParsed.activity,
        const ActivityEdit(title: 'Morning Spin GPX'),
      );
      final gpxReparsed = CoreEngine.parseGpx(gpxExported.bytes);

      expect(gpxReparsed.diagnostics, isEmpty);
      expect(gpxReparsed.activity.title, 'Morning Spin GPX');
      expect(gpxReparsed.activity.sportType, SportType.cycling);
      expect(gpxReparsed.activity.trackpoints, hasLength(2));
      expect(gpxReparsed.activity.trackpoints[0].heartRateBpm, 135);
      expect(gpxReparsed.activity.trackpoints[1].cadenceRpm, 92);
      expect(gpxReparsed.summary.duration, const Duration(seconds: 30));
    });

    test('recovers Huawei Health TCX root creator, Outdoor run sport, Lap-level DistanceMeters without trackpoint distance, and preserves on FIT/TCX export', () {
      const huaweiTcx = '''<?xml version="1.0" encoding="UTF-8"?>
<TrainingCenterDatabase
  creator="Health"
  xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <Activities>
    <Activity Sport="Outdoor run">
      <Id>2026-11-20T06:00:00Z</Id>
      <Lap StartTime="2026-11-20T06:00:00Z">
        <TotalTimeSeconds>2520.0</TotalTimeSeconds>
        <DistanceMeters>7150.0</DistanceMeters>
        <Calories>480</Calories>
        <Track>
          <Trackpoint>
            <Time>2026-11-20T06:00:00Z</Time>
            <Position>
              <LatitudeDegrees>14.600000</LatitudeDegrees>
              <LongitudeDegrees>120.984000</LongitudeDegrees>
            </Position>
            <AltitudeMeters>12.0</AltitudeMeters>
            <HeartRateBpm><Value>142</Value></HeartRateBpm>
          </Trackpoint>
          <Trackpoint>
            <Time>2026-11-20T06:14:00Z</Time>
            <Position>
              <LatitudeDegrees>14.621289</LatitudeDegrees>
              <LongitudeDegrees>120.984000</LongitudeDegrees>
            </Position>
            <AltitudeMeters>16.0</AltitudeMeters>
            <HeartRateBpm><Value>154</Value></HeartRateBpm>
          </Trackpoint>
          <Trackpoint>
            <Time>2026-11-20T06:28:00Z</Time>
            <Position>
              <LatitudeDegrees>14.642577</LatitudeDegrees>
              <LongitudeDegrees>120.984000</LongitudeDegrees>
            </Position>
            <AltitudeMeters>14.0</AltitudeMeters>
            <HeartRateBpm><Value>160</Value></HeartRateBpm>
          </Trackpoint>
          <Trackpoint>
            <Time>2026-11-20T06:42:00Z</Time>
            <Position>
              <LatitudeDegrees>14.663866</LatitudeDegrees>
              <LongitudeDegrees>120.984000</LongitudeDegrees>
            </Position>
            <AltitudeMeters>18.0</AltitudeMeters>
            <HeartRateBpm><Value>165</Value></HeartRateBpm>
          </Trackpoint>
        </Track>
      </Lap>
      <Notes>Outdoor run</Notes>
    </Activity>
  </Activities>
</TrainingCenterDatabase>''';

      final parsed = CoreEngine.parseTcx(
        _utf8(huaweiTcx),
        fileName: 'huawei_outdoor_run.tcx',
      );

      expect(parsed.diagnostics, isEmpty);
      expect(parsed.activity.deviceInfo, 'Health');
      expect(parsed.activity.sportType, SportType.running);
      expect(parsed.activity.availableChannels, contains(Channel.distance));

      final pts = parsed.activity.trackpoints;
      expect(pts, hasLength(4));
      expect(pts[0].cumulativeDistanceMeters, closeTo(0.0, 0.01));
      expect(pts[1].cumulativeDistanceMeters, closeTo(7150.0 / 3.0, 0.5));
      expect(pts[2].cumulativeDistanceMeters, closeTo(7150.0 * 2.0 / 3.0, 0.5));
      expect(pts[3].cumulativeDistanceMeters, closeTo(7150.0, 0.01));

      expect(parsed.activity.laps.single.distanceMeters, closeTo(7150.0, 0.01));
      expect(parsed.summary.gpsDistanceMeters, closeTo(7150.0, 0.01));
      expect(parsed.summary.avgPaceSecondsPerKm, closeTo(2520.0 / 7.15, 0.05));

      final diag = CoreEngine.analyzeDistance(
        parsed.activity,
        isImperial: false,
      );
      expect(diag.recordedDistanceMeters, closeTo(7150.0, 0.01));
      expect(diag.gpsDistanceMeters, closeTo(7101.58, 0.5));
      expect(diag.effectiveDistanceMeters, closeTo(7150.0, 0.01));
      expect(
        diag.stravaTaxMeters,
        closeTo(7150.0 - diag.gpsDistanceMeters, 0.01),
      );

      // FIT export preserves recovered total distance and creator without manual override
      final fitExport = CoreEngine.exportFit(
        parsed.activity,
        const ActivityEdit(),
      );
      final fitReparsed = CoreEngine.parseFit(fitExport.bytes);
      expect(fitReparsed.activity.deviceInfo, 'Health');
      expect(
        fitReparsed.activity.trackpoints.last.cumulativeDistanceMeters,
        closeTo(7150.0, 0.05),
      );
      expect(
        fitReparsed.activity.laps.single.distanceMeters,
        closeTo(7150.0, 0.05),
      );
      expect(fitReparsed.summary.gpsDistanceMeters, closeTo(7150.0, 0.05));

      // TCX export preserves recovered total distance and creator without manual override
      final tcxExport = CoreEngine.exportTcx(
        parsed.activity,
        const ActivityEdit(),
      );
      final tcxReparsed = CoreEngine.parseTcx(tcxExport.bytes);
      expect(tcxReparsed.activity.deviceInfo, 'Health');
      expect(
        tcxReparsed.activity.trackpoints.last.cumulativeDistanceMeters,
        closeTo(7150.0, 0.05),
      );
      expect(
        tcxReparsed.activity.laps.single.distanceMeters,
        closeTo(7150.0, 0.05),
      );
      expect(tcxReparsed.summary.gpsDistanceMeters, closeTo(7150.0, 0.05));
    });

    test('multi-Lap TCX without trackpoint distance distributes per-Lap and prefers Activity Creator over root creator', () {
      const multiLapTcx = '''<?xml version="1.0" encoding="UTF-8"?>
<TrainingCenterDatabase
  creator="Health"
  xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <Activities>
    <Activity Sport="Running">
      <Id>2026-11-20T06:00:00Z</Id>
      <Lap StartTime="2026-11-20T06:00:00Z">
        <TotalTimeSeconds>300.0</TotalTimeSeconds>
        <DistanceMeters>1020.0</DistanceMeters>
        <Track>
          <Trackpoint>
            <Time>2026-11-20T06:00:00Z</Time>
            <Position><LatitudeDegrees>14.600000</LatitudeDegrees><LongitudeDegrees>120.984000</LongitudeDegrees></Position>
          </Trackpoint>
          <Trackpoint>
            <Time>2026-11-20T06:05:00Z</Time>
            <Position><LatitudeDegrees>14.609000</LatitudeDegrees><LongitudeDegrees>120.984000</LongitudeDegrees></Position>
          </Trackpoint>
        </Track>
      </Lap>
      <Lap StartTime="2026-11-20T06:05:00Z">
        <TotalTimeSeconds>300.0</TotalTimeSeconds>
        <DistanceMeters>1030.0</DistanceMeters>
        <Track>
          <Trackpoint>
            <Time>2026-11-20T06:10:00Z</Time>
            <Position><LatitudeDegrees>14.618000</LatitudeDegrees><LongitudeDegrees>120.984000</LongitudeDegrees></Position>
          </Trackpoint>
        </Track>
      </Lap>
      <Notes>Two Lap Run</Notes>
      <Creator xsi:type="Device_t">
        <Name>HUAWEI WATCH GT 4</Name>
      </Creator>
    </Activity>
  </Activities>
</TrainingCenterDatabase>''';

      final parsed = CoreEngine.parseTcx(_utf8(multiLapTcx));
      expect(parsed.diagnostics, isEmpty);
      expect(parsed.activity.deviceInfo, 'HUAWEI WATCH GT 4');
      expect(parsed.activity.trackpoints[0].cumulativeDistanceMeters, closeTo(0.0, 0.01));
      expect(parsed.activity.trackpoints[1].cumulativeDistanceMeters, closeTo(1020.0, 0.01));
      expect(parsed.activity.trackpoints[2].cumulativeDistanceMeters, closeTo(2050.0, 0.01));
      expect(parsed.activity.laps[0].distanceMeters, closeTo(1020.0, 0.01));
      expect(parsed.activity.laps[1].distanceMeters, closeTo(1030.0, 0.01));
      expect(parsed.summary.gpsDistanceMeters, closeTo(2050.0, 0.01));
    });

    test('prefers TrainingCenterDatabase Author Name over root creator when Activity Creator is absent', () {
      const authorTcx = '''<?xml version="1.0" encoding="UTF-8"?>
<TrainingCenterDatabase
  creator="Health"
  xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <Activities>
    <Activity Sport="Running">
      <Id>2026-11-20T06:00:00Z</Id>
      <Lap StartTime="2026-11-20T06:00:00Z">
        <TotalTimeSeconds>60.0</TotalTimeSeconds>
        <DistanceMeters>200.0</DistanceMeters>
        <Track>
          <Trackpoint>
            <Time>2026-11-20T06:00:00Z</Time>
            <Position><LatitudeDegrees>14.600000</LatitudeDegrees><LongitudeDegrees>120.984000</LongitudeDegrees></Position>
          </Trackpoint>
          <Trackpoint>
            <Time>2026-11-20T06:01:00Z</Time>
            <Position><LatitudeDegrees>14.601800</LatitudeDegrees><LongitudeDegrees>120.984000</LongitudeDegrees></Position>
          </Trackpoint>
        </Track>
      </Lap>
    </Activity>
  </Activities>
  <Author xsi:type="Application_t">
    <Name>Huawei Health App</Name>
  </Author>
</TrainingCenterDatabase>''';

      final parsed = CoreEngine.parseTcx(_utf8(authorTcx));
      expect(parsed.activity.deviceInfo, 'Huawei Health App');
      expect(parsed.summary.gpsDistanceMeters, closeTo(200.0, 0.01));
    });
  });
}
