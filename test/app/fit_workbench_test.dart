import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_it/app/sync_it_app.dart';
import 'package:sync_it/core/core_engine.dart';
import 'package:sync_it/port/platform_io_port.dart';

class _FakePlatformIoPort implements PlatformIoPort {
  _FakePlatformIoPort({this.nextPickedFile});

  PickedSourceFile? nextPickedFile;
  String? lastSavedFileName;
  Uint8List? lastSavedBytes;
  String? lastSharedFileName;
  Uint8List? lastSharedBytes;

  @override
  Future<PickedSourceFile?> pickSourceFile() async => nextPickedFile;

  @override
  Future<bool> saveExportFile({
    required String suggestedFileName,
    required Uint8List bytes,
  }) async {
    lastSavedFileName = suggestedFileName;
    lastSavedBytes = bytes;
    return true;
  }

  @override
  Future<void> shareExportFile({
    required String fileName,
    required Uint8List bytes,
  }) async {
    lastSharedFileName = fileName;
    lastSharedBytes = bytes;
  }
}

Uint8List _buildFitWithVendorExtension() {
  final t0 = DateTime.utc(2026, 11, 19, 6, 0, 0);
  final t1 = DateTime.utc(2026, 11, 19, 6, 1, 0);
  final fitT0 = (t0.millisecondsSinceEpoch ~/ 1000) - 631065600;
  final fitT1 = (t1.millisecondsSinceEpoch ~/ 1000) - 631065600;

  // Export a clean FIT first, then inject a vendor-extension record or build raw.
  // Building raw with file_id, device_info, sport, record (with unknown field 39), lap, session.
  final data = BytesBuilder();

  // 1. file_id (local 0, global 0)
  data.add([0x40, 0, 0, 0, 0, 3]);
  data.add([0, 1, 0x00, 1, 2, 0x84, 2, 2, 0x84]);
  data.add([0, 4, 1, 0, 10, 0]); // type=4, mfg=1 (Garmin), prod=10

  // 2. sport (local 1, global 12)
  data.add([0x41, 0, 0, 12, 0, 2]);
  data.add([0, 1, 0x00, 3, 16, 0x07]);
  data.addByte(1); // local type 1
  final nameBytes = Uint8List(16)..setRange(0, 9, 'Tempo Run'.codeUnits);
  data.add([1, ...nameBytes]); // sport=1 (running), name

  // 3. record (local 2, global 20) with unknown vendor field 39
  data.add([0x42, 0, 0, 20, 0, 5]);
  data.add([
    253, 4, 0x86, // timestamp
    0, 4, 0x85, // lat
    1, 4, 0x85, // lon
    3, 1, 0x02, // hr
    39, 2, 0x84, // proprietary Garmin vertical_oscillation
  ]);

  void addRecord(int ts, int lat, int lon, int hr, int vo) {
    data.addByte(2);
    final bd = ByteData(15);
    bd.setUint32(0, ts, Endian.little);
    bd.setInt32(4, lat, Endian.little);
    bd.setInt32(8, lon, Endian.little);
    bd.setUint8(12, hr);
    bd.setUint16(13, vo, Endian.little);
    data.add(bd.buffer.asUint8List());
  }

  const scale = 2147483648.0 / 180.0;
  addRecord(fitT0, (14.6000 * scale).round(), (120.9840 * scale).round(), 145, 85);
  addRecord(fitT1, (14.6018 * scale).round(), (120.9840 * scale).round(), 155, 88);

  // 4. session (local 3, global 18)
  data.add([0x43, 0, 0, 18, 0, 2]);
  data.add([5, 1, 0x00, 11, 2, 0x84]); // sport, total_calories
  data.add([3, 1, 0x90, 0x01]); // sport=1 (running), calories=400

  return _wrapFit(data.toBytes());
}

Uint8List _wrapFit(Uint8List dataBytes) {
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

void main() {
  testWidgets('imports FIT with vendor-extension notice, defaults Export to .fit, and switches to .gpx in one tap', (tester) async {
    final fakePort = _FakePlatformIoPort(
      nextPickedFile: PickedSourceFile(
        fileName: 'tempo_run.fit',
        bytes: _buildFitWithVendorExtension(),
      ),
    );

    await tester.pumpWidget(SyncItApp(platformIoPort: fakePort));

    await tester.tap(find.byKey(const Key('import-source-button')));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();

    // Overview: totals, device info, calories, and vendor-extension notice
    expect(find.textContaining('proprietary vendor or developer'), findsOneWidget);
    expect(find.text('Tempo Run'), findsWidgets);
    expect(find.text('400 kcal'), findsOneWidget);
    expect(find.textContaining('Garmin'), findsWidgets);

    // Export tab: defaults to .fit
    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();
    expect(find.text('tempo_run.fit'), findsOneWidget);

    await tester.tap(find.text('Save FIT'));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();

    expect(fakePort.lastSavedFileName, 'tempo_run.fit');
    expect(fakePort.lastSavedBytes, isNotNull);
    final reparsedFit = CoreEngine.parseFit(fakePort.lastSavedBytes!);
    expect(reparsedFit.activity.calories, 400);

    // One-tap switch to GPX
    await tester.tap(find.text('GPX'));
    await tester.pumpAndSettle();
    expect(find.text('tempo_run.gpx'), findsOneWidget);

    await tester.tap(find.text('Save GPX'));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();

    expect(fakePort.lastSavedFileName, 'tempo_run.gpx');
    final reparsedGpx = CoreEngine.parseGpx(fakePort.lastSavedBytes!);
    expect(reparsedGpx.activity.title, 'Tempo Run');
  });

  testWidgets('defaults Export to .fit when importing a GPX Source File', (tester) async {
    const sampleGpx = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="Test" xmlns="http://www.topografix.com/GPX/1/1">
  <trk>
    <name>Morning Walk</name>
    <type>walking</type>
    <trkseg>
      <trkpt lat="14.6000" lon="120.9840"><time>2026-11-19T06:00:00Z</time></trkpt>
      <trkpt lat="14.6009" lon="120.9840"><time>2026-11-19T06:01:00Z</time></trkpt>
    </trkseg>
  </trk>
</gpx>''';

    final fakePort = _FakePlatformIoPort(
      nextPickedFile: PickedSourceFile(
        fileName: 'morning_walk.gpx',
        bytes: Uint8List.fromList(utf8.encode(sampleGpx)),
      ),
    );

    await tester.pumpWidget(SyncItApp(platformIoPort: fakePort));
    await tester.tap(find.byKey(const Key('import-source-button')));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();
    expect(find.text('morning_walk.fit'), findsOneWidget);

    await tester.tap(find.text('Save FIT'));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();

    expect(fakePort.lastSavedFileName, 'morning_walk.fit');
    final reparsedFit = CoreEngine.parseFit(fakePort.lastSavedBytes!);
    expect(reparsedFit.activity.sportType, SportType.walking);
  });

  testWidgets('surfaces actionable error on Start screen when FIT is corrupted', (tester) async {
    final fakePort = _FakePlatformIoPort(
      nextPickedFile: PickedSourceFile(
        fileName: 'corrupt.fit',
        bytes: Uint8List.fromList([14, 0x20, 0x54, 0x08]),
      ),
    );

    await tester.pumpWidget(SyncItApp(platformIoPort: fakePort));
    await tester.tap(find.byKey(const Key('import-source-button')));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();

    expect(find.textContaining('Truncated FIT file'), findsOneWidget);
  });

  testWidgets('labels Overview distance as Distance for indoor FIT without GPS', (tester) async {
    final t0 = DateTime.utc(2026, 11, 19, 7, 0, 0);
    final t1 = DateTime.utc(2026, 11, 19, 7, 5, 0);
    final indoorActivity = Activity(
      title: 'Treadmill Run',
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
          cumulativeDistanceMeters: 1250.0,
          heartRateBpm: 155,
        ),
      ],
      laps: [Lap(startTime: t0, endTime: t1, distanceMeters: 1250.0)],
      availableChannels: const {Channel.distance, Channel.heartRate},
    );
    final fitBytes =
        CoreEngine.exportFit(indoorActivity, const ActivityEdit()).bytes;

    final fakePort = _FakePlatformIoPort(
      nextPickedFile: PickedSourceFile(
        fileName: 'treadmill.fit',
        bytes: fitBytes,
      ),
    );

    await tester.pumpWidget(SyncItApp(platformIoPort: fakePort));
    await tester.tap(find.byKey(const Key('import-source-button')));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();

    expect(find.text('Distance'), findsOneWidget);
    expect(find.text('GPS Distance'), findsNothing);
    expect(find.text('1.25 km'), findsOneWidget);
  });
}
