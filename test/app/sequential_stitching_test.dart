import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_it/app/sync_it_app.dart';
import 'package:sync_it/core/core_engine.dart';
import 'package:sync_it/port/platform_io_port.dart';

class _StitchFakePort implements PlatformIoPort {
  _StitchFakePort({this.pickedFiles = const []});

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
}

Uint8List _utf8(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  testWidgets(
    'stitch parts -> chronological order & overlap warning -> toggle Remove gap -> export FIT',
    (tester) async {
      // Part 1 (06:00:00 - 06:10:00): Watch TCX with HR + Distance (1000 m)
      const part1Tcx = '''<?xml version="1.0" encoding="UTF-8"?>
<TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2">
  <Activities>
    <Activity Sport="Running">
      <Id>2026-11-20T06:00:00Z</Id>
      <Lap StartTime="2026-11-20T06:00:00Z">
        <TotalTimeSeconds>600</TotalTimeSeconds>
        <DistanceMeters>1000</DistanceMeters>
        <Calories>120</Calories>
        <Track>
          <Trackpoint>
            <Time>2026-11-20T06:00:00Z</Time>
            <Position>
              <LatitudeDegrees>14.600000</LatitudeDegrees>
              <LongitudeDegrees>120.984000</LongitudeDegrees>
            </Position>
            <DistanceMeters>0</DistanceMeters>
            <HeartRateBpm><Value>145</Value></HeartRateBpm>
          </Trackpoint>
          <Trackpoint>
            <Time>2026-11-20T06:10:00Z</Time>
            <Position>
              <LatitudeDegrees>14.609000</LatitudeDegrees>
              <LongitudeDegrees>120.984000</LongitudeDegrees>
            </Position>
            <DistanceMeters>1000</DistanceMeters>
            <HeartRateBpm><Value>155</Value></HeartRateBpm>
          </Trackpoint>
        </Track>
      </Lap>
      <Notes>Morning Split Run</Notes>
    </Activity>
  </Activities>
</TrainingCenterDatabase>''';

      // Part 2 (06:08:00 - 06:18:00): Phone GPX without HR, overlapping 06:08 & 06:10
      const part2Gpx = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="PhoneGPX"
  xmlns="http://www.topografix.com/GPX/1/1">
  <trk>
    <name>Phone Backup</name>
    <type>running</type>
    <trkseg>
      <trkpt lat="14.607200" lon="120.984000">
        <ele>15.0</ele>
        <time>2026-11-20T06:08:00Z</time>
      </trkpt>
      <trkpt lat="14.609000" lon="120.984000">
        <ele>18.0</ele>
        <time>2026-11-20T06:10:00Z</time>
      </trkpt>
      <trkpt lat="14.609000" lon="120.984000">
        <ele>20.0</ele>
        <time>2026-11-20T06:15:00Z</time>
      </trkpt>
      <trkpt lat="14.613500" lon="120.984000">
        <ele>25.0</ele>
        <time>2026-11-20T06:18:00Z</time>
      </trkpt>
    </trkseg>
  </trk>
</gpx>''';

      final fakePort = _StitchFakePort(
        pickedFiles: [
          PickedSourceFile(fileName: 'part1_watch.tcx', bytes: _utf8(part1Tcx)),
        ],
      );

      await tester.pumpWidget(SyncItApp(platformIoPort: fakePort));

      // Selecting < 2 files shows actionable error
      await tester.tap(find.byKey(const Key('stitch-parts-button')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('2 or more Source Files'),
        findsOneWidget,
      );

      // Provide 2 files in reverse chronological order
      fakePort.pickedFiles = [
        PickedSourceFile(fileName: 'part2_phone.gpx', bytes: _utf8(part2Gpx)),
        PickedSourceFile(fileName: 'part1_watch.tcx', bytes: _utf8(part1Tcx)),
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

      await tester.tap(find.byKey(const Key('stitch-parts-button')));
      await waitForFinder(find.text('Overview'));
      await tester.pumpAndSettle();

      // Overlap diagnostic warning banner is displayed
      expect(
        find.textContaining('Overlapping timestamps detected'),
        findsOneWidget,
      );

      // Overview initially preserves real timestamps across gap (06:00 -> 06:18 = 18:00) and 2 Laps
      expect(find.text('18:00'), findsOneWidget);
      expect(find.text('2'), findsWidgets);

      // Switch to Edit & Channels -> verify chronological order & toggle Remove gap
      await tester.tap(find.text('Edit & Channels'));
      await tester.pumpAndSettle();

      final part0Widget = tester.widget<ListTile>(
        find.byKey(const Key('stitch-part-0')),
      );
      final part1Widget = tester.widget<ListTile>(
        find.byKey(const Key('stitch-part-1')),
      );
      expect(
        (part0Widget.title as Text).data,
        contains('part1_watch.tcx'),
      );
      expect(
        (part1Widget.title as Text).data,
        contains('part2_phone.gpx'),
      );

      final removeGapSwitch = find.byKey(const Key('stitch-remove-gap-switch'));
      await tester.scrollUntilVisible(
        removeGapSwitch,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(removeGapSwitch);
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pumpAndSettle();

      // Overview now reflects shifted flush timeline: 06:00:00 -> 06:13:01 (13:01)
      await tester.tap(find.text('Overview'));
      await tester.pumpAndSettle();
      expect(find.text('13:01'), findsOneWidget);

      // Export tab -> Save FIT (unblocked even with overlap warning)
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
      expect(exported.activity.laps.length, 2);
      expect(exported.activity.trackpoints.length, 4);
      expect(exported.summary.duration, const Duration(minutes: 13, seconds: 1));
      // Part 1 keeps HR, Part 2 leaves HR null
      expect(exported.activity.trackpoints[0].heartRateBpm, 145);
      expect(exported.activity.trackpoints[1].heartRateBpm, 155);
      expect(exported.activity.trackpoints[2].heartRateBpm, isNull);
      expect(exported.activity.trackpoints[3].heartRateBpm, isNull);
      // Continuous distance: 1000 m + ~500 m GPX segment
      expect(
        exported.activity.trackpoints.last.cumulativeDistanceMeters,
        greaterThan(1490.0),
      );
    },
  );
}
