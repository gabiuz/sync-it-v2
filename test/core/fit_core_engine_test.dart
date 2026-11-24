import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gpx_lab/core/core_engine.dart';

void main() {
  group('CoreEngine FIT Seam', () {
    test('rejects empty, truncated, invalid-magic, and bad-CRC FIT files with actionable errors', () {
      // 1. Empty bytes
      expect(
        () => CoreEngine.parseFit(Uint8List(0)),
        throwsA(isA<ActivityParseException>()),
      );

      // 2. Truncated header (< 12 bytes)
      expect(
        () => CoreEngine.parseFit(Uint8List.fromList([14, 0x20, 0x54, 0x08])),
        throwsA(isA<ActivityParseException>()),
      );

      // 3. Invalid magic (not ".FIT")
      final badMagic = Uint8List.fromList([
        14, 0x20, 0x54, 0x08, // headerSize, protocol, profile
        0, 0, 0, 0, // dataSize = 0
        0x42, 0x41, 0x44, 0x21, // "BAD!"
        0, 0, // header CRC
        0, 0, // file CRC
      ]);
      expect(
        () => CoreEngine.parseFit(badMagic),
        throwsA(isA<ActivityParseException>()),
      );

      // 4. Truncated payload (dataSize says 100, but file ends early)
      final truncatedPayload = Uint8List.fromList([
        14, 0x20, 0x54, 0x08,
        100, 0, 0, 0, // dataSize = 100
        0x2E, 0x46, 0x49, 0x54, // ".FIT"
        0, 0,
        0, 0,
      ]);
      expect(
        () => CoreEngine.parseFit(truncatedPayload),
        throwsA(isA<ActivityParseException>()),
      );

      // 5. Valid header + 0-byte payload, but corrupted trailing CRC-16
      final badCrc = Uint8List.fromList([
        14, 0x20, 0x54, 0x08,
        0, 0, 0, 0, // dataSize = 0
        0x2E, 0x46, 0x49, 0x54, // ".FIT"
        0, 0,
        0xFF, 0xFF, // wrong file CRC
      ]);
      expect(
        () => CoreEngine.parseFit(badCrc),
        throwsA(isA<ActivityParseException>()),
      );
    });

    test('round-trips Activity with all standard channels, laps, calories, and device info through FIT', () async {
      final t0 = DateTime.utc(2026, 11, 19, 6, 30, 0);
      final t1 = DateTime.utc(2026, 11, 19, 6, 30, 30);
      final t2 = DateTime.utc(2026, 11, 19, 6, 31, 0);

      final sourceActivity = Activity(
        title: 'Threshold Intervals',
        description: 'Track session',
        sportType: SportType.running,
        calories: 320,
        deviceInfo: 'Garmin Forerunner 965',
        trackpoints: [
          Trackpoint(
            timestamp: t0,
            latitude: 14.599500,
            longitude: 120.984200,
            elevationMeters: 10.0,
            cumulativeDistanceMeters: 0.0,
            heartRateBpm: 142,
            cadenceRpm: 84,
            powerWatts: 250,
            temperatureCelsius: 26,
          ),
          Trackpoint(
            timestamp: t1,
            latitude: 14.600400,
            longitude: 120.984200,
            elevationMeters: 15.0,
            cumulativeDistanceMeters: 100.25,
            heartRateBpm: 154,
            cadenceRpm: 88,
            powerWatts: 280,
            temperatureCelsius: 27,
          ),
          Trackpoint(
            timestamp: t2,
            latitude: 14.601300,
            longitude: 120.984200,
            elevationMeters: 12.0,
            cumulativeDistanceMeters: 200.50,
            heartRateBpm: 160,
            cadenceRpm: 90,
            powerWatts: 295,
            temperatureCelsius: 27,
          ),
        ],
        laps: [
          Lap(startTime: t0, endTime: t1, distanceMeters: 100.25),
          Lap(startTime: t1, endTime: t2, distanceMeters: 100.25),
        ],
        availableChannels: const {
          Channel.gps,
          Channel.elevation,
          Channel.distance,
          Channel.heartRate,
          Channel.cadence,
          Channel.power,
          Channel.temperature,
        },
      );

      final exported = await CoreEngine.exportFitInIsolate(
        sourceActivity,
        const ActivityEdit(
          title: 'Threshold Intervals Edited',
          sportType: SportType.cycling,
        ),
      );

      // Verify 14-byte FIT header and ".FIT" signature
      expect(exported.bytes.length, greaterThan(16));
      expect(exported.bytes[0], 14);
      expect(
        String.fromCharCodes(exported.bytes.sublist(8, 12)),
        '.FIT',
      );

      // Re-parse exported FIT bytes (validates header + file CRC-16)
      final reparsed = await CoreEngine.parseFitInIsolate(
        exported.bytes,
        fileName: 'threshold.fit',
      );

      expect(reparsed.diagnostics, isEmpty);
      expect(reparsed.activity.sportType, SportType.cycling);
      expect(reparsed.activity.calories, 320);
      expect(reparsed.activity.deviceInfo, contains('Garmin'));
      expect(reparsed.activity.laps, hasLength(2));
      expect(reparsed.activity.laps[0].distanceMeters, closeTo(100.25, 0.05));
      expect(reparsed.activity.laps[1].distanceMeters, closeTo(100.25, 0.05));

      expect(reparsed.activity.trackpoints, hasLength(3));
      final p0 = reparsed.activity.trackpoints[0];
      final p2 = reparsed.activity.trackpoints[2];
      expect(p0.timestamp, t0);
      expect(p0.latitude!, closeTo(14.599500, 1e-5));
      expect(p0.longitude!, closeTo(120.984200, 1e-5));
      expect(p0.elevationMeters!, closeTo(10.0, 0.2));
      expect(p0.cumulativeDistanceMeters!, closeTo(0.0, 0.01));
      expect(p0.heartRateBpm, 142);
      expect(p0.cadenceRpm, 84);
      expect(p0.powerWatts, 250);
      expect(p0.temperatureCelsius, 26);

      expect(p2.timestamp, t2);
      expect(p2.cumulativeDistanceMeters!, closeTo(200.50, 0.05));
      expect(p2.heartRateBpm, 160);
      expect(p2.cadenceRpm, 90);
      expect(p2.powerWatts, 295);
      expect(p2.temperatureCelsius, 27);

      expect(
        reparsed.activity.availableChannels,
        containsAll(const [
          Channel.gps,
          Channel.elevation,
          Channel.distance,
          Channel.heartRate,
          Channel.cadence,
          Channel.power,
          Channel.temperature,
        ]),
      );
      expect(reparsed.summary.duration, const Duration(minutes: 1));
      expect(reparsed.summary.avgHeartRateBpm, 152);
      expect(reparsed.summary.maxHeartRateBpm, 160);
      expect(reparsed.summary.lapCount, 2);
      expect(reparsed.activity.laps[0].avgHeartRateBpm, 148);
      expect(reparsed.activity.laps[0].maxHeartRateBpm, 154);
      expect(reparsed.activity.laps[1].avgHeartRateBpm, 157);
      expect(reparsed.activity.laps[1].maxHeartRateBpm, 160);
    });

    test('converts GPX Source File to valid FIT Export File with matching totals and terminal distance', () async {
      const sampleGpx = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="GPX Lab Test"
  xmlns="http://www.topografix.com/GPX/1/1"
  xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1">
  <metadata>
    <name>City Loop</name>
    <time>2026-11-19T07:00:00Z</time>
  </metadata>
  <trk>
    <name>City Loop</name>
    <type>running</type>
    <trkseg>
      <trkpt lat="14.599500" lon="120.984200">
        <ele>10.0</ele>
        <time>2026-11-19T07:00:00Z</time>
        <extensions>
          <gpxtpx:TrackPointExtension>
            <gpxtpx:hr>140</gpxtpx:hr>
            <gpxtpx:cad>82</gpxtpx:cad>
          </gpxtpx:TrackPointExtension>
        </extensions>
      </trkpt>
      <trkpt lat="14.600400" lon="120.984200">
        <ele>14.0</ele>
        <time>2026-11-19T07:00:30Z</time>
        <extensions>
          <gpxtpx:TrackPointExtension>
            <gpxtpx:hr>150</gpxtpx:hr>
            <gpxtpx:cad>84</gpxtpx:cad>
          </gpxtpx:TrackPointExtension>
        </extensions>
      </trkpt>
      <trkpt lat="14.601300" lon="120.984200">
        <ele>12.0</ele>
        <time>2026-11-19T07:01:00Z</time>
        <extensions>
          <gpxtpx:TrackPointExtension>
            <gpxtpx:hr>160</gpxtpx:hr>
            <gpxtpx:cad>86</gpxtpx:cad>
          </gpxtpx:TrackPointExtension>
        </extensions>
      </trkpt>
    </trkseg>
  </trk>
</gpx>''';

      final gpxParsed = CoreEngine.parseGpx(
        Uint8List.fromList(sampleGpx.codeUnits),
        fileName: 'city_loop.gpx',
      );
      final fitExported = CoreEngine.exportFit(
        gpxParsed.activity,
        const ActivityEdit(title: 'City Loop FIT', sportType: SportType.running),
      );
      final fitReparsed = CoreEngine.parseFit(fitExported.bytes);

      expect(fitReparsed.diagnostics, isEmpty);
      expect(fitReparsed.activity.title, 'City Loop FIT');
      expect(fitReparsed.activity.sportType, SportType.running);
      expect(fitReparsed.activity.trackpoints, hasLength(3));
      expect(fitReparsed.summary.duration, gpxParsed.summary.duration);
      expect(
        fitReparsed.summary.gpsDistanceMeters,
        closeTo(gpxParsed.summary.gpsDistanceMeters, 1.0),
      );
      // Terminal trackpoint cumulative distance matches lap & session totals.
      final terminalDist =
          fitReparsed.activity.trackpoints.last.cumulativeDistanceMeters!;
      expect(terminalDist, closeTo(gpxParsed.summary.gpsDistanceMeters, 1.0));
      expect(
        fitReparsed.activity.laps.single.distanceMeters!,
        closeTo(terminalDist, 0.05),
      );
    });

    test('surfaces informational diagnostic when FIT contains proprietary vendor or developer fields', () {
      // Build a minimal valid FIT file with:
      // - Record definition with Developer Data Flag (0x20) + 1 unknown vendor field (39) + 1 developer field
      final data = BytesBuilder();
      final fitTs = (DateTime.utc(2026, 11, 19, 8, 0, 0)
                  .millisecondsSinceEpoch ~/
              1000) -
          631065600;

      // Record definition: local 0, global 20, 2 standard fields (253 timestamp, 39 vertical_oscillation), 1 dev field
      data.addByte(0x40 | 0x20 | 0); // definition + dev data flag + local 0
      data.addByte(0); // reserved
      data.addByte(0); // little-endian
      data.add([20, 0]); // global 20 (record)
      data.addByte(3); // 3 standard fields
      data.add([253, 4, 0x86]); // timestamp
      data.add([3, 1, 0x02]); // heart_rate
      data.add([39, 2, 0x84]); // proprietary Garmin vertical_oscillation
      data.addByte(1); // 1 developer field
      data.add([0, 2, 0]); // dev field 0, size 2, dev index 0

      // Data message for local 0
      data.addByte(0);
      final tsBytes = ByteData(4)..setUint32(0, fitTs, Endian.little);
      data.add(tsBytes.buffer.asUint8List());
      data.addByte(148); // heart_rate
      data.add([0x50, 0x00]); // vertical_oscillation
      data.add([0x2A, 0x00]); // developer field payload

      final fitBytes = _wrapFitContainer(data.toBytes());
      final parsed = CoreEngine.parseFit(fitBytes, fileName: 'garmin_rd.fit');

      expect(parsed.activity.trackpoints, hasLength(1));
      expect(parsed.activity.trackpoints.single.heartRateBpm, 148);
      expect(parsed.diagnostics, hasLength(1));
      expect(
        parsed.diagnostics.single.code,
        DiagnosticCode.unsupportedExtensionsDropped,
      );
      expect(
        parsed.diagnostics.single.severity,
        DiagnosticSeverity.info,
      );
      expect(parsed.diagnostics.single.count, 2);
    });

    test('decodes big-endian FIT records and compressed timestamp headers', () {
      final data = BytesBuilder();
      final t0 = DateTime.utc(2026, 11, 19, 9, 0, 0);
      final fitTs0 = (t0.millisecondsSinceEpoch ~/ 1000) - 631065600;

      // Record definition (big-endian, local 0, global 20)
      data.addByte(0x40); // definition, local 0
      data.addByte(0); // reserved
      data.addByte(1); // big-endian
      data.add([0, 20]); // global 20 (record) big-endian
      data.addByte(2); // 2 fields
      data.add([253, 4, 0x86]); // timestamp
      data.add([3, 1, 0x02]); // heart_rate

      // Normal data message at t0
      data.addByte(0);
      final tsBytes = ByteData(4)..setUint32(0, fitTs0, Endian.big);
      data.add(tsBytes.buffer.asUint8List());
      data.addByte(135);

      // Compressed timestamp data message at t0 + 5s (local 0)
      final t1Low5 = (fitTs0 + 5) & 0x1F;
      data.addByte(0x80 | t1Low5);
      data.addByte(140);

      final fitBytes = _wrapFitContainer(data.toBytes());
      final parsed = CoreEngine.parseFit(fitBytes);

      expect(parsed.diagnostics, isEmpty);
      expect(parsed.activity.trackpoints, hasLength(2));
      expect(parsed.activity.trackpoints[0].timestamp, t0);
      expect(parsed.activity.trackpoints[0].heartRateBpm, 135);
      expect(
        parsed.activity.trackpoints[1].timestamp,
        t0.add(const Duration(seconds: 5)),
      );
      expect(parsed.activity.trackpoints[1].heartRateBpm, 140);
    });
  });
}

Uint8List _wrapFitContainer(Uint8List dataBytes) {
  const crcTable = <int>[
    0x0000, 0xCC01, 0xD801, 0x1400, 0xF001, 0x3C00, 0x2800, 0xE401,
    0xA001, 0x6C00, 0x7800, 0xB401, 0x5000, 0x9C01, 0x8801, 0x4400,
  ];
  int crc16(Uint8List b, int end) {
    var crc = 0;
    for (var i = 0; i < end; i++) {
      final byte = b[i];
      var tmp = crcTable[crc & 0x0F];
      crc = ((crc >> 4) & 0x0FFF) ^ tmp ^ crcTable[byte & 0x0F];
      tmp = crcTable[crc & 0x0F];
      crc = ((crc >> 4) & 0x0FFF) ^ tmp ^ crcTable[(byte >> 4) & 0x0F];
    }
    return crc;
  }

  final out = Uint8List(14 + dataBytes.length + 2);
  final bd = ByteData.sublistView(out);
  out[0] = 14;
  out[1] = 0x20;
  bd.setUint16(2, 2132, Endian.little);
  bd.setUint32(4, dataBytes.length, Endian.little);
  out.setRange(8, 12, '.FIT'.codeUnits);
  bd.setUint16(12, crc16(out, 12), Endian.little);
  out.setRange(14, 14 + dataBytes.length, dataBytes);
  bd.setUint16(14 + dataBytes.length, crc16(out, 14 + dataBytes.length), Endian.little);
  return out;
}
