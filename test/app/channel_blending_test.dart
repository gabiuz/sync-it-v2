import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpx_lab/app/gpx_lab_app.dart';
import 'package:gpx_lab/core/core_engine.dart';
import 'package:gpx_lab/port/platform_io_port.dart';

class _BlendFakePort implements PlatformIoPort {
  _BlendFakePort({this.pickedFiles = const []});

  List<PickedSourceFile> pickedFiles;
  String? lastSavedFileName;
  Uint8List? lastSavedBytes;

  @override
  Future<PickedSourceFile?> pickSourceFile() async =>
      pickedFiles.isEmpty ? null : pickedFiles.first;

  @override
  Future<List<PickedSourceFile>> pickMultipleSourceFiles() async => pickedFiles;

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
  }) async {}

  @override
  Future<bool> isMapTilesAvailable() async => false;

  @override
  Future<void> copyToClipboard(String text) async {}

  @override
  Future<bool> launchExternalUrl(Uri url) async => true;

  @override
  Future<IncomingSourceBatch?> consumeInitialIncomingSources() async => null;

  @override
  Stream<IncomingSourceBatch> get incomingSourceBatches => const Stream.empty();
}

Uint8List _utf8(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  testWidgets(
    'multi-file blend -> inspect -> switch Base Timeline & metadata -> export flow',
    (tester) async {
      const gpxXml = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="WatchGPX"
  xmlns="http://www.topografix.com/GPX/1/1">
  <trk>
    <name>Huawei Blend Run</name>
    <type>walking</type>
    <trkseg>
      <trkpt lat="14.600000" lon="120.984000">
        <ele>10.0</ele>
        <time>2026-11-20T06:00:00Z</time>
      </trkpt>
      <trkpt lat="14.604500" lon="120.984000">
        <ele>20.0</ele>
        <time>2026-11-20T06:02:00Z</time>
      </trkpt>
      <trkpt lat="14.609000" lon="120.984000">
        <ele>30.0</ele>
        <time>2026-11-20T06:04:00Z</time>
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
        <TotalTimeSeconds>120</TotalTimeSeconds>
        <DistanceMeters>500</DistanceMeters>
        <Calories>80</Calories>
        <Track>
          <Trackpoint>
            <Time>2026-11-20T06:00:00Z</Time>
            <DistanceMeters>0</DistanceMeters>
            <HeartRateBpm><Value>140</Value></HeartRateBpm>
            <Cadence>85</Cadence>
          </Trackpoint>
          <Trackpoint>
            <Time>2026-11-20T06:02:00Z</Time>
            <DistanceMeters>500</DistanceMeters>
            <HeartRateBpm><Value>156</Value></HeartRateBpm>
            <Cadence>88</Cadence>
          </Trackpoint>
        </Track>
      </Lap>
      <Lap StartTime="2026-11-20T06:02:00Z">
        <TotalTimeSeconds>120</TotalTimeSeconds>
        <DistanceMeters>500</DistanceMeters>
        <Calories>90</Calories>
        <Track>
          <Trackpoint>
            <Time>2026-11-20T06:04:00Z</Time>
            <DistanceMeters>1000</DistanceMeters>
            <HeartRateBpm><Value>166</Value></HeartRateBpm>
            <Cadence>90</Cadence>
          </Trackpoint>
        </Track>
      </Lap>
      <Creator>
        <Name>Huawei Watch GT</Name>
      </Creator>
    </Activity>
  </Activities>
</TrainingCenterDatabase>''';

      final fakePort = _BlendFakePort(
        pickedFiles: [
          PickedSourceFile(fileName: 'route.gpx', bytes: _utf8(gpxXml)),
        ],
      );

      await tester.pumpWidget(GpxLabApp(platformIoPort: fakePort));

      // Selecting only 1 file shows an error
      await tester.tap(find.byKey(const Key('blend-channels-button')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('2 or more Source Files'),
        findsOneWidget,
      );

      // Now provide 2 files (GPX + TCX)
      fakePort.pickedFiles = [
        PickedSourceFile(fileName: 'route.gpx', bytes: _utf8(gpxXml)),
        PickedSourceFile(fileName: 'sensor.tcx', bytes: _utf8(tcxXml)),
      ];

      Future<void> waitForFinder(Finder finder) async {
        for (var i = 0; i < 40; i++) {
          await tester.pump();
          if (finder.evaluate().isNotEmpty) return;
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
        }
      }

      await tester.tap(find.byKey(const Key('blend-channels-button')));
      await waitForFinder(find.text('Overview'));
      await tester.pumpAndSettle();

      // Overview shows blended HR from TCX + Elevation from GPX
      expect(find.text('154 bpm'), findsOneWidget);
      expect(find.text('20 m'), findsOneWidget);

      // Switch to Edit & Channels tab
      await tester.tap(find.text('Edit & Channels'));
      await tester.pumpAndSettle();

      // Switch Laps, Calories, Sport Type, and Device Info to sensor.tcx
      Future<void> selectDropdownOption(Key key, String optionSubstring) async {
        final finder = find.byKey(key);
        await tester.scrollUntilVisible(
          finder,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(finder);
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining(optionSubstring).last);
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)),
        );
        await tester.pumpAndSettle();
      }

      await selectDropdownOption(
        const Key('blend-meta-laps-dropdown'),
        'sensor.tcx',
      );
      await selectDropdownOption(
        const Key('blend-meta-calories-dropdown'),
        'sensor.tcx',
      );
      await selectDropdownOption(
        const Key('blend-meta-sport-dropdown'),
        'sensor.tcx',
      );
      await selectDropdownOption(
        const Key('blend-meta-device-dropdown'),
        'sensor.tcx',
      );

      // Overview now reflects 2 Laps, 170 kcal, Running, Huawei Watch GT
      await tester.tap(find.text('Overview'));
      await tester.pumpAndSettle();

      expect(find.text('170 kcal'), findsOneWidget);
      expect(find.text('Huawei Watch GT'), findsOneWidget);
      expect(find.textContaining('Running'), findsWidgets);
      await tester.scrollUntilVisible(
        find.byKey(const Key('lap-breakdown-table')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('lap-breakdown-table')), findsOneWidget);

      // Export tab -> Save FIT
      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Save FIT'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Save FIT'));
      await waitForFinder(find.textContaining('Export File saved'));
      await tester.pumpAndSettle();

      expect(fakePort.lastSavedBytes, isNotNull);
      final exported = CoreEngine.parseFit(
        fakePort.lastSavedBytes!,
        fileName: fakePort.lastSavedFileName,
      );
      expect(exported.activity.sportType, SportType.running);
      expect(exported.activity.calories, 170);
      expect(exported.activity.laps.length, 2);
      expect(exported.activity.trackpoints.length, 3);
      expect(exported.activity.trackpoints[1].heartRateBpm, 156);
      expect(exported.activity.trackpoints[1].latitude, closeTo(14.6045, 1e-4));
    },
  );
}
