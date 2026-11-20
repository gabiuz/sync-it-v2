import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_it/app/sync_it_app.dart';
import 'package:sync_it/core/core_engine.dart';
import 'package:sync_it/port/platform_io_port.dart';

class _InMemoryPlatformIoPort implements PlatformIoPort {
  _InMemoryPlatformIoPort({this.nextPickedFile});

  PickedSourceFile? nextPickedFile;
  String? lastSavedFileName;
  Uint8List? lastSavedBytes;

  @override
  Future<PickedSourceFile?> pickSourceFile() async => nextPickedFile;

  @override
  Future<List<PickedSourceFile>> pickMultipleSourceFiles() async => const [];

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

const _richTcx = '''<?xml version="1.0" encoding="UTF-8"?>
<TrainingCenterDatabase
  xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xmlns:ns3="http://www.garmin.com/xmlschemas/ActivityExtension/v2">
  <Activities>
    <Activity Sport="Running">
      <Id>2026-11-20T06:00:00Z</Id>
      <Lap StartTime="2026-11-20T06:00:00Z">
        <TotalTimeSeconds>300.000</TotalTimeSeconds>
        <DistanceMeters>500.00</DistanceMeters>
        <Calories>150</Calories>
        <AverageHeartRateBpm><Value>145</Value></AverageHeartRateBpm>
        <MaximumHeartRateBpm><Value>155</Value></MaximumHeartRateBpm>
        <Track>
          <Trackpoint>
            <Time>2026-11-20T06:00:00Z</Time>
            <Position>
              <LatitudeDegrees>14.600000</LatitudeDegrees>
              <LongitudeDegrees>120.984000</LongitudeDegrees>
            </Position>
            <AltitudeMeters>10.0</AltitudeMeters>
            <DistanceMeters>0.00</DistanceMeters>
            <HeartRateBpm><Value>140</Value></HeartRateBpm>
          </Trackpoint>
          <Trackpoint>
            <Time>2026-11-20T06:05:00Z</Time>
            <Position>
              <LatitudeDegrees>14.604500</LatitudeDegrees>
              <LongitudeDegrees>120.984000</LongitudeDegrees>
            </Position>
            <AltitudeMeters>25.0</AltitudeMeters>
            <DistanceMeters>500.00</DistanceMeters>
            <HeartRateBpm><Value>155</Value></HeartRateBpm>
          </Trackpoint>
        </Track>
      </Lap>
      <Lap StartTime="2026-11-20T06:05:00Z">
        <TotalTimeSeconds>300.000</TotalTimeSeconds>
        <DistanceMeters>500.00</DistanceMeters>
        <Calories>160</Calories>
        <AverageHeartRateBpm><Value>160</Value></AverageHeartRateBpm>
        <MaximumHeartRateBpm><Value>165</Value></MaximumHeartRateBpm>
        <Track>
          <Trackpoint>
            <Time>2026-11-20T06:10:00Z</Time>
            <Position>
              <LatitudeDegrees>14.609000</LatitudeDegrees>
              <LongitudeDegrees>120.984000</LongitudeDegrees>
            </Position>
            <AltitudeMeters>30.0</AltitudeMeters>
            <DistanceMeters>1000.00</DistanceMeters>
            <HeartRateBpm><Value>165</Value></HeartRateBpm>
          </Trackpoint>
        </Track>
      </Lap>
      <Notes>Morning Tempo</Notes>
      <Creator xsi:type="Device_t">
        <Name>Garmin Forerunner 965</Name>
      </Creator>
    </Activity>
  </Activities>
</TrainingCenterDatabase>''';

Future<void> _importRichTcx(
  WidgetTester tester,
  _InMemoryPlatformIoPort port,
) async {
  await tester.pumpWidget(SyncItApp(platformIoPort: port));
  await tester.tap(find.byKey(const Key('import-source-button')));
  await tester.pump();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Edit & Channels shows all 9 toggles, Device Info note, GPS-stripped GPX blocking, and Export warnings',
    (tester) async {
      final port = _InMemoryPlatformIoPort(
        nextPickedFile: PickedSourceFile(
          fileName: 'morning_tempo.tcx',
          bytes: _utf8(_richTcx),
        ),
      );

      await _importRichTcx(tester, port);

      // Navigate to Edit & Channels
      await tester.tap(find.text('Edit & Channels'));
      await tester.pumpAndSettle();

      // All 9 toggles are present
      for (final channel in StrippableChannel.values) {
        final toggleFinder = find.byKey(Key('channel-toggle-${channel.name}'));
        await tester.ensureVisible(toggleFinder);
        expect(toggleFinder, findsOneWidget);
      }

      // Change sport to Hiking to verify TCX sport-narrowing warning later
      final sportDropdown = find.byKey(const Key('edit-sport-dropdown'));
      await tester.ensureVisible(sportDropdown);
      await tester.pumpAndSettle();
      await tester.tap(sportDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hiking').last);
      await tester.pumpAndSettle();

      // Strip Device / Creator Info -> inline note appears
      final deviceToggle = find.byKey(
        Key('channel-toggle-${StrippableChannel.deviceInfo.name}'),
      );
      await tester.ensureVisible(deviceToggle);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('device-info-strip-note')), findsNothing);
      await tester.tap(deviceToggle);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('device-info-strip-note')), findsOneWidget);
      expect(find.textContaining('elevation correction'), findsOneWidget);

      // Strip Heart Rate and GPS Position
      for (final ch in [StrippableChannel.heartRate, StrippableChannel.gps]) {
        final finder = find.byKey(Key('channel-toggle-${ch.name}'));
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      // Navigate to Export tab and select TCX
      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('TCX'));
      await tester.pumpAndSettle();

      // TCX shows Strava title warning + sport narrowing warning
      final exportScrollable = find
          .descendant(
            of: find.byKey(const Key('export-tab-list')),
            matching: find.byType(Scrollable),
          )
          .first;
      final tcxTitleWarning = find.byKey(
        Key('export-warning-${ExportWarningCode.stravaIgnoresManualUploadTitle.name}'),
      );
      await tester.scrollUntilVisible(
        tcxTitleWarning,
        200.0,
        scrollable: exportScrollable,
      );
      expect(tcxTitleWarning, findsOneWidget);
      final tcxSportWarning = find.byKey(
        Key('export-warning-${ExportWarningCode.tcxNarrowsSportCategory.name}'),
      );
      await tester.scrollUntilVisible(
        tcxSportWarning,
        200.0,
        scrollable: exportScrollable,
      );
      expect(tcxSportWarning, findsOneWidget);

      // Switch to GPX -> Save GPX & Share GPX are disabled and blocking warning is shown
      await tester.scrollUntilVisible(
        find.text('GPX'),
        -200.0,
        scrollable: exportScrollable,
      );
      await tester.tap(find.text('GPX'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('export-blocking-warning')), findsOneWidget);
      final saveGpxButton = tester.widget<ButtonStyleButton>(
        find.widgetWithText(FilledButton, 'Save GPX'),
      );
      final shareGpxButton = tester.widget<ButtonStyleButton>(
        find.widgetWithText(OutlinedButton, 'Share GPX'),
      );
      expect(saveGpxButton.onPressed, isNull);
      expect(shareGpxButton.onPressed, isNull);

      // Switch to FIT -> Save FIT is enabled and exports mapless, HR-free, device-free FIT
      await tester.tap(find.text('FIT'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('export-blocking-warning')), findsNothing);
      final fitTitleWarning = find.byKey(
        Key('export-warning-${ExportWarningCode.stravaIgnoresManualUploadTitle.name}'),
      );
      await tester.scrollUntilVisible(
        fitTitleWarning,
        200.0,
        scrollable: exportScrollable,
      );
      expect(fitTitleWarning, findsOneWidget);

      final saveFitBtn = find.text('Save FIT');
      await tester.scrollUntilVisible(
        saveFitBtn,
        -200.0,
        scrollable: exportScrollable,
      );
      await tester.tap(saveFitBtn);
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();

      expect(port.lastSavedBytes, isNotNull);
      final exportedFit = CoreEngine.parseFit(port.lastSavedBytes!);
      expect(exportedFit.activity.deviceInfo, isNull);
      expect(exportedFit.summary.avgHeartRateBpm, isNull);
      expect(exportedFit.activity.trackpoints.first.latitude, isNull);
      expect(
        exportedFit.activity.trackpoints.last.cumulativeDistanceMeters,
        closeTo(1000.0, 0.5),
      );
    },
  );
}
