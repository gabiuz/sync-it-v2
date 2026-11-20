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

const _stravaTaxTcx = '''<?xml version="1.0" encoding="UTF-8"?>
<TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2">
  <Activities>
    <Activity Sport="Running">
      <Id>2026-11-19T06:00:00Z</Id>
      <Lap StartTime="2026-11-19T06:00:00Z">
        <TotalTimeSeconds>3000.000</TotalTimeSeconds>
        <DistanceMeters>9998.00</DistanceMeters>
        <Calories>600</Calories>
        <Track>
          <Trackpoint>
            <Time>2026-11-19T06:00:00Z</Time>
            <Position>
              <LatitudeDegrees>14.600000</LatitudeDegrees>
              <LongitudeDegrees>120.984000</LongitudeDegrees>
            </Position>
            <DistanceMeters>0.00</DistanceMeters>
          </Trackpoint>
          <Trackpoint>
            <Time>2026-11-19T06:50:00Z</Time>
            <Position>
              <LatitudeDegrees>14.689000</LatitudeDegrees>
              <LongitudeDegrees>120.984000</LongitudeDegrees>
            </Position>
            <DistanceMeters>9998.00</DistanceMeters>
          </Trackpoint>
        </Track>
      </Lap>
      <Notes>Morning 10K</Notes>
    </Activity>
  </Activities>
</TrainingCenterDatabase>''';

Future<void> _importTcx(
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
    'Overview shows Strava Tax, floor-truncation warning, one-tap nudge, manual override, and GPX lossy warning',
    (tester) async {
      final port = _InMemoryPlatformIoPort(
        nextPickedFile: PickedSourceFile(
          fileName: 'morning_10k.tcx',
          bytes: _utf8(_stravaTaxTcx),
        ),
      );

      await _importTcx(tester, port);

      // Overview shows Strava Tax card with recorded vs GPS distance and predicted 9.99 km
      final taxCard = find.byKey(const Key('strava-tax-card'));
      await tester.scrollUntilVisible(
        taxCard,
        200.0,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(taxCard, findsOneWidget);
      expect(find.textContaining('9.998 km'), findsOneWidget);
      expect(find.textContaining('9.90 km'), findsOneWidget);
      expect(find.textContaining('9.99 km'), findsWidgets);

      // Floor-truncation warning & one-tap nudge are visible
      final warningCard =
          find.byKey(const Key('strava-truncation-warning-card'));
      final nudgeBtn = find.byKey(const Key('nudge-distance-override-button'));
      await tester.scrollUntilVisible(
        nudgeBtn,
        200.0,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(warningCard, findsOneWidget);
      expect(nudgeBtn, findsOneWidget);

      // Tap one-tap nudge -> populates Distance Override to 10.00 km & clears warning
      await tester.tap(nudgeBtn);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('strava-truncation-warning-card')),
        findsNothing,
      );

      // Edit & Channels reflects the populated Distance Override and allows manual edit & clear
      await tester.tap(find.text('Edit & Channels'));
      await tester.pumpAndSettle();

      final overrideField =
          find.byKey(const Key('edit-distance-override-field'));
      expect(overrideField, findsOneWidget);
      expect(
        tester.widget<TextField>(overrideField).controller?.text,
        '10.00',
      );

      // Manual override to 10.50 km
      await tester.enterText(overrideField, '10.50');
      await tester.pumpAndSettle();

      // Export tab: FIT has no GPX warning, GPX surfaces lossy-export warning
      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('gpx-distance-override-warning')),
        findsNothing,
      );

      await tester.tap(find.text('GPX'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('gpx-distance-override-warning')),
        findsOneWidget,
      );

      // Switching back to FIT hides the GPX warning and exports 10500 m
      await tester.tap(find.text('FIT'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('gpx-distance-override-warning')),
        findsNothing,
      );

      await tester.tap(find.text('Save FIT'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();

      expect(port.lastSavedBytes, isNotNull);
      final exportedFit = CoreEngine.parseFit(port.lastSavedBytes!);
      expect(
        exportedFit.activity.trackpoints.last.cumulativeDistanceMeters,
        closeTo(10500.0, 0.05),
      );

      // Clearing Distance Override on Edit & Channels restores original 9.998 km
      await tester.tap(find.text('Edit & Channels'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('clear-distance-override-button')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(overrideField).controller?.text,
        isEmpty,
      );

      await tester.tap(find.text('Overview'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('strava-truncation-warning-card')),
        findsOneWidget,
      );
    },
  );
}
