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

  @override
  Future<bool> isMapTilesAvailable() async => false;
}

Future<void> _pumpUntilSettledAsync(WidgetTester tester) async {
  for (var i = 0; i < 50; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      break;
    }
  }
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('imports multi-Lap TCX with diagnostic banner, displays Lap summaries, and exports across TCX, GPX, and FIT', (tester) async {
    const sampleTcx = '''<?xml version="1.0" encoding="UTF-8"?>
<TrainingCenterDatabase
  xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xmlns:ns3="http://www.garmin.com/xmlschemas/ActivityExtension/v2">
  <Activities>
    <Activity Sport="Running">
      <Id>2026-11-19T06:00:00Z</Id>
      <Lap StartTime="2026-11-19T06:00:00Z">
        <TotalTimeSeconds>30.0</TotalTimeSeconds>
        <DistanceMeters>110.0</DistanceMeters>
        <Calories>15</Calories>
        <Track>
          <Trackpoint>
            <Time>2026-11-19T06:00:00Z</Time>
            <Position><LatitudeDegrees>14.599500</LatitudeDegrees><LongitudeDegrees>120.984200</LongitudeDegrees></Position>
            <AltitudeMeters>10.0</AltitudeMeters>
            <HeartRateBpm><Value>140</Value></HeartRateBpm>
            <Extensions><ns3:TPX><ns3:RunCadence>84</ns3:RunCadence></ns3:TPX></Extensions>
          </Trackpoint>
          <Trackpoint>
            <Time>2026-11-19T06:00:30Z</Time>
            <Position><LatitudeDegrees>14.600400</LatitudeDegrees><LongitudeDegrees>120.984200</LongitudeDegrees></Position>
            <AltitudeMeters>14.0</AltitudeMeters>
            <DistanceMeters>110.0</DistanceMeters>
            <HeartRateBpm><Value>150</Value></HeartRateBpm>
            <Extensions><ns3:TPX><ns3:RunCadence>86</ns3:RunCadence></ns3:TPX></Extensions>
          </Trackpoint>
        </Track>
      </Lap>
      <Lap StartTime="2026-11-19T06:00:30Z">
        <TotalTimeSeconds>30.0</TotalTimeSeconds>
        <DistanceMeters>120.0</DistanceMeters>
        <Calories>18</Calories>
        <Track>
          <Trackpoint>
            <Time>2026-11-19T06:01:00Z</Time>
            <Position><LatitudeDegrees>14.601300</LatitudeDegrees><LongitudeDegrees>120.984200</LongitudeDegrees></Position>
            <AltitudeMeters>12.0</AltitudeMeters>
            <DistanceMeters>230.0</DistanceMeters>
            <HeartRateBpm><Value>162</Value></HeartRateBpm>
            <Extensions><ns3:TPX><ns3:RunCadence>90</ns3:RunCadence></ns3:TPX></Extensions>
          </Trackpoint>
        </Track>
      </Lap>
      <Notes>Huawei Tempo</Notes>
      <Creator xsi:type="Device_t"><Name>HUAWEI WATCH GT 4</Name></Creator>
    </Activity>
  </Activities>
</TrainingCenterDatabase>''';

    final fakePort = _FakePlatformIoPort(
      nextPickedFile: PickedSourceFile(
        fileName: 'huawei_tempo.tcx',
        bytes: Uint8List.fromList(utf8.encode(sampleTcx)),
      ),
    );

    await tester.pumpWidget(SyncItApp(platformIoPort: fakePort));
    await tester.tap(find.byKey(const Key('import-source-button')));
    await tester.pump();
    await _pumpUntilSettledAsync(tester);

    // Diagnostic banner for normalized first-point distance
    expect(find.textContaining('first trackpoint'), findsOneWidget);
    expect(find.text('Huawei Tempo'), findsWidgets);
    expect(find.textContaining('HUAWEI WATCH GT 4'), findsWidgets);
    await tester.scrollUntilVisible(find.text('Lap 2'), 200);
    expect(find.text('Lap 1'), findsOneWidget);
    expect(find.text('Lap 2'), findsOneWidget);

    // Export tab: switch to TCX and save
    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('TCX'));
    await tester.pumpAndSettle();
    expect(find.text('huawei_tempo.tcx'), findsOneWidget);

    await tester.tap(find.text('Save TCX'));
    await tester.pump();
    await _pumpUntilSettledAsync(tester);

    expect(fakePort.lastSavedFileName, 'huawei_tempo.tcx');
    expect(fakePort.lastSavedBytes, isNotNull);
    final reparsedTcx = CoreEngine.parseTcx(fakePort.lastSavedBytes!);
    expect(reparsedTcx.activity.trackpoints.last.cumulativeDistanceMeters, 230.0);

    // Switch to GPX and save
    await tester.tap(find.text('GPX'));
    await tester.pumpAndSettle();
    expect(find.text('huawei_tempo.gpx'), findsOneWidget);

    await tester.tap(find.text('Save GPX'));
    await tester.pump();
    await _pumpUntilSettledAsync(tester);

    expect(fakePort.lastSavedFileName, 'huawei_tempo.gpx');
    final reparsedGpx = CoreEngine.parseGpx(fakePort.lastSavedBytes!);
    expect(reparsedGpx.activity.title, 'Huawei Tempo');
  });

  testWidgets('surfaces actionable error on Start screen when TCX is corrupted', (tester) async {
    final fakePort = _FakePlatformIoPort(
      nextPickedFile: PickedSourceFile(
        fileName: 'corrupt.tcx',
        bytes: Uint8List.fromList(utf8.encode('<TrainingCenterDatabase><bad')),
      ),
    );

    await tester.pumpWidget(SyncItApp(platformIoPort: fakePort));
    await tester.tap(find.byKey(const Key('import-source-button')));
    await tester.pump();
    await _pumpUntilSettledAsync(tester);

    expect(find.textContaining('Corrupted TCX XML file'), findsOneWidget);
  });
}
