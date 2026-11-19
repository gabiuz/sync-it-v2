import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sync_it/core/core_engine.dart';

Uint8List _utf8(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  group('CoreEngine GPX Seam', () {
    test('parses valid GPX, applies metadata edits, and preserves round-trip fidelity', () async {
      const sampleGpx = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="Sync-It Test"
  xmlns="http://www.topografix.com/GPX/1/1"
  xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1">
  <metadata>
    <name>Morning Run</name>
    <desc>Easy neighborhood loop</desc>
    <time>2026-11-19T06:30:00Z</time>
  </metadata>
  <trk>
    <name>Morning Run</name>
    <desc>Easy neighborhood loop</desc>
    <type>running</type>
    <trkseg>
      <trkpt lat="14.599500" lon="120.984200">
        <ele>10.0</ele>
        <time>2026-11-19T06:30:00Z</time>
        <extensions>
          <gpxtpx:TrackPointExtension>
            <gpxtpx:hr>142</gpxtpx:hr>
            <gpxtpx:cad>84</gpxtpx:cad>
          </gpxtpx:TrackPointExtension>
        </extensions>
      </trkpt>
      <trkpt lat="14.600400" lon="120.984200">
        <ele>15.0</ele>
        <time>2026-11-19T06:30:30Z</time>
        <extensions>
          <gpxtpx:TrackPointExtension>
            <gpxtpx:hr>152</gpxtpx:hr>
            <gpxtpx:cad>86</gpxtpx:cad>
          </gpxtpx:TrackPointExtension>
        </extensions>
      </trkpt>
      <trkpt lat="14.601300" lon="120.984200">
        <ele>12.0</ele>
        <time>2026-11-19T06:31:00Z</time>
        <extensions>
          <gpxtpx:TrackPointExtension>
            <gpxtpx:hr>156</gpxtpx:hr>
            <gpxtpx:cad>88</gpxtpx:cad>
          </gpxtpx:TrackPointExtension>
        </extensions>
      </trkpt>
    </trkseg>
  </trk>
</gpx>''';

      final parsed = await CoreEngine.parseGpxInIsolate(_utf8(sampleGpx));
      expect(parsed.diagnostics, isEmpty);
      expect(parsed.activity.title, 'Morning Run');
      expect(parsed.activity.description, 'Easy neighborhood loop');
      expect(parsed.activity.sportType, SportType.running);
      expect(parsed.activity.trackpoints, hasLength(3));
      expect(
        parsed.activity.availableChannels,
        containsAll([
          Channel.gps,
          Channel.elevation,
          Channel.heartRate,
          Channel.cadence,
        ]),
      );

      expect(parsed.summary.trackpointCount, 3);
      expect(parsed.summary.duration, const Duration(minutes: 1));
      // ~100m per 0.0009 deg lat => ~200m total
      expect(parsed.summary.gpsDistanceMeters, closeTo(200.15, 2.0));
      expect(parsed.summary.elevationGainMeters, closeTo(5.0, 0.01));
      expect(parsed.summary.avgHeartRateBpm, 150);
      expect(parsed.summary.maxHeartRateBpm, 156);

      final exported = await CoreEngine.exportGpxInIsolate(
        parsed.activity,
        const ActivityEdit(
          title: 'Sunrise 10K Prep',
          description: 'Felt strong on the flats',
          sportType: SportType.hiking,
        ),
      );

      final reparsed = CoreEngine.parseGpx(exported.bytes);
      expect(reparsed.diagnostics, isEmpty);
      expect(reparsed.activity.title, 'Sunrise 10K Prep');
      expect(reparsed.activity.description, 'Felt strong on the flats');
      expect(reparsed.activity.sportType, SportType.hiking);
      expect(reparsed.activity.trackpoints, hasLength(3));
      expect(reparsed.summary.duration, const Duration(minutes: 1));
      expect(
        reparsed.summary.gpsDistanceMeters,
        closeTo(parsed.summary.gpsDistanceMeters, 0.5),
      );
      expect(reparsed.summary.avgHeartRateBpm, 150);
      expect(reparsed.summary.maxHeartRateBpm, 156);
    });

    test('normalizes out-of-order trackpoints, duplicate timestamps, 0 bpm HR dropouts, and unknown extensions with diagnostics', () {
      const quirkyGpx = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="QuirkyWatch"
  xmlns="http://www.topografix.com/GPX/1/1"
  xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1"
  xmlns:vendor="http://example.com/vendor">
  <trk>
    <name>Quirky Run</name>
    <type>running</type>
    <trkseg>
      <trkpt lat="14.6010" lon="120.9840">
        <ele>12.0</ele>
        <time>2026-11-19T06:30:20Z</time>
        <extensions>
          <gpxtpx:TrackPointExtension>
            <gpxtpx:hr>160</gpxtpx:hr>
          </gpxtpx:TrackPointExtension>
          <vendor:groundContactTime>245</vendor:groundContactTime>
        </extensions>
      </trkpt>
      <trkpt lat="14.6000" lon="120.9840">
        <ele>10.0</ele>
        <time>2026-11-19T06:30:00Z</time>
        <extensions>
          <gpxtpx:TrackPointExtension>
            <gpxtpx:hr>0</gpxtpx:hr>
          </gpxtpx:TrackPointExtension>
        </extensions>
      </trkpt>
      <trkpt lat="14.6005" lon="120.9840">
        <ele>11.0</ele>
        <time>2026-11-19T06:30:10Z</time>
        <extensions>
          <gpxtpx:TrackPointExtension>
            <gpxtpx:hr>140</gpxtpx:hr>
          </gpxtpx:TrackPointExtension>
        </extensions>
      </trkpt>
      <trkpt lat="14.6005" lon="120.9840">
        <ele>11.5</ele>
        <time>2026-11-19T06:30:10Z</time>
        <extensions>
          <gpxtpx:TrackPointExtension>
            <gpxtpx:hr>142</gpxtpx:hr>
          </gpxtpx:TrackPointExtension>
        </extensions>
      </trkpt>
    </trkseg>
  </trk>
</gpx>''';

      final result = CoreEngine.parseGpx(_utf8(quirkyGpx));
      expect(result.activity.trackpoints, hasLength(3));
      expect(
        result.activity.trackpoints.map((t) => t.timestamp).toList(),
        [
          DateTime.utc(2026, 11, 19, 6, 30, 0),
          DateTime.utc(2026, 11, 19, 6, 30, 10),
          DateTime.utc(2026, 11, 19, 6, 30, 20),
        ],
      );
      // 0 bpm dropout is nulled out, so avg HR is (142 + 160) / 2 = 151 (not diluted by 0).
      expect(result.activity.trackpoints.first.heartRateBpm, isNull);
      expect(result.summary.avgHeartRateBpm, 151);

      final codes = result.diagnostics.map((d) => d.code).toSet();
      expect(
        codes,
        containsAll([
          DiagnosticCode.outOfOrderTrackpointsSorted,
          DiagnosticCode.duplicateTimestampsNormalized,
          DiagnosticCode.zeroHeartRateDropped,
          DiagnosticCode.unsupportedExtensionsDropped,
        ]),
      );
    });

    test('rejects corrupted XML and timestamp-less GPX files with actionable errors', () {
      expect(
        () => CoreEngine.parseGpx(_utf8('<gpx><trk><broken')),
        throwsA(
          isA<ActivityParseException>().having(
            (e) => e.message,
            'message',
            contains('Corrupted GPX XML'),
          ),
        ),
      );

      const noTimestampsGpx = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">
  <trk>
    <name>Planned Route</name>
    <trkseg>
      <trkpt lat="14.6000" lon="120.9840"><ele>10</ele></trkpt>
      <trkpt lat="14.6010" lon="120.9840"><ele>12</ele></trkpt>
    </trkseg>
  </trk>
</gpx>''';

      expect(
        () => CoreEngine.parseGpx(_utf8(noTimestampsGpx)),
        throwsA(
          isA<ActivityParseException>().having(
            (e) => e.message,
            'message',
            contains('without <time> timestamps'),
          ),
        ),
      );
    });
  });
}
