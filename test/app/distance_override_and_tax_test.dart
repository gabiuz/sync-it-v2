import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpx_lab/app/gpx_lab_app.dart';
import 'package:gpx_lab/core/core_engine.dart';
import 'package:gpx_lab/port/platform_io_port.dart';

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

Future<void> _importSource(
  WidgetTester tester,
  _InMemoryPlatformIoPort port,
) async {
  await tester.pumpWidget(GpxLabApp(platformIoPort: port));
  await tester.tap(find.byKey(const Key('import-source-button')));
  await tester.pump();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await tester.pumpAndSettle();
}

const _huaweiHealthGpx = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="Health"
  xmlns="http://www.topografix.com/GPX/1/1"
  xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1"
  xmlns:hw="http://www.huawei.com/gpx/extensions">
  <metadata>
    <name>Outdoor run</name>
    <time/>
  </metadata>
  <trk>
    <name>Outdoor run</name>
    <type>Outdoor run</type>
    <extensions>
      <hw:totalDistance>7150.0</hw:totalDistance>
    </extensions>
    <trkseg>
      <trkpt lat="14.600000" lon="120.984000">
        <ele>12.0</ele>
        <time>2026-11-20T06:00:00Z</time>
        <extensions><gpxtpx:TrackPointExtension><gpxtpx:hr>142</gpxtpx:hr></gpxtpx:TrackPointExtension></extensions>
      </trkpt>
      <trkpt lat="14.621289" lon="120.984000">
        <ele>16.0</ele>
        <time>2026-11-20T06:14:00Z</time>
        <extensions><gpxtpx:TrackPointExtension><gpxtpx:hr>154</gpxtpx:hr></gpxtpx:TrackPointExtension></extensions>
      </trkpt>
      <trkpt lat="14.642577" lon="120.984000">
        <ele>14.0</ele>
        <time>2026-11-20T06:28:00Z</time>
        <extensions><gpxtpx:TrackPointExtension><gpxtpx:hr>160</gpxtpx:hr></gpxtpx:TrackPointExtension></extensions>
      </trkpt>
      <trkpt lat="14.663866" lon="120.984000">
        <ele>18.0</ele>
        <time>2026-11-20T06:42:00Z</time>
        <extensions><gpxtpx:TrackPointExtension><gpxtpx:hr>165</gpxtpx:hr></gpxtpx:TrackPointExtension></extensions>
      </trkpt>
    </trkseg>
  </trk>
</gpx>''';

const _huaweiHealthTcx = '''<?xml version="1.0" encoding="UTF-8"?>
<TrainingCenterDatabase
  creator="Health"
  xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2">
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
            <Position><LatitudeDegrees>14.600000</LatitudeDegrees><LongitudeDegrees>120.984000</LongitudeDegrees></Position>
          </Trackpoint>
          <Trackpoint>
            <Time>2026-11-20T06:21:00Z</Time>
            <Position><LatitudeDegrees>14.631933</LatitudeDegrees><LongitudeDegrees>120.984000</LongitudeDegrees></Position>
          </Trackpoint>
          <Trackpoint>
            <Time>2026-11-20T06:42:00Z</Time>
            <Position><LatitudeDegrees>14.663866</LatitudeDegrees><LongitudeDegrees>120.984000</LongitudeDegrees></Position>
          </Trackpoint>
        </Track>
      </Lap>
      <Notes>Outdoor run</Notes>
    </Activity>
  </Activities>
</TrainingCenterDatabase>''';

const _standardGpxNoRecordedDistance = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="StandardGPS"
  xmlns="http://www.topografix.com/GPX/1/1">
  <trk>
    <name>Standard Loop</name>
    <type>running</type>
    <trkseg>
      <trkpt lat="14.600000" lon="120.984000">
        <time>2026-11-20T06:00:00Z</time>
      </trkpt>
      <trkpt lat="14.663866" lon="120.984000">
        <time>2026-11-20T06:42:00Z</time>
      </trkpt>
    </trkseg>
  </trk>
</gpx>''';

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

      await _importSource(tester, port);

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

  testWidgets(
    'Overview displays Huawei Health GPX recorded distance, pace, Health creator, Strava Tax, and preserves 7150 m on FIT/TCX export',
    (tester) async {
      final port = _InMemoryPlatformIoPort(
        nextPickedFile: PickedSourceFile(
          fileName: 'huawei_run.gpx',
          bytes: _utf8(_huaweiHealthGpx),
        ),
      );

      await _importSource(tester, port);

      // Overview shows recorded distance (7.15 km), recorded pace (5:52 /km), and Health creator.
      await tester.scrollUntilVisible(
        find.text('Device'),
        200.0,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('7.15 km'), findsWidgets);
      expect(find.text('5:52 /km'), findsOneWidget);
      expect(find.text('Health'), findsOneWidget);

      // Strava Tax card shows recorded vs GPS distance, discrepancy, quick override button & FIT/TCX reminder.
      final taxCard = find.byKey(const Key('strava-tax-card'));
      await tester.scrollUntilVisible(
        taxCard,
        200.0,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('7.150 km'), findsOneWidget);
      expect(find.textContaining('7.10 km'), findsOneWidget);
      expect(find.textContaining('+0.048 km'), findsOneWidget);
      expect(
        find.byKey(const Key('overview-set-distance-override-button')),
        findsOneWidget,
      );
      expect(find.textContaining('FIT or TCX'), findsOneWidget);

      // Export FIT and TCX without manual Distance Override -> 7150.0 m & Health preserved.
      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save FIT'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();

      final fitReparsed = CoreEngine.parseFit(port.lastSavedBytes!);
      expect(fitReparsed.activity.deviceInfo, 'Health');
      expect(
        fitReparsed.activity.trackpoints.last.cumulativeDistanceMeters,
        closeTo(7150.0, 0.05),
      );

      await tester.tap(find.text('TCX'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save TCX'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();

      final tcxReparsed = CoreEngine.parseTcx(port.lastSavedBytes!);
      expect(tcxReparsed.activity.deviceInfo, 'Health');
      expect(
        tcxReparsed.activity.trackpoints.last.cumulativeDistanceMeters,
        closeTo(7150.0, 0.05),
      );
    },
  );

  testWidgets(
    'Overview displays Huawei Health TCX Lap-level distance, Health creator, Strava Tax, and preserves 7150 m on FIT export',
    (tester) async {
      final port = _InMemoryPlatformIoPort(
        nextPickedFile: PickedSourceFile(
          fileName: 'huawei_run.tcx',
          bytes: _utf8(_huaweiHealthTcx),
        ),
      );

      await _importSource(tester, port);

      await tester.scrollUntilVisible(
        find.text('Device'),
        200.0,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('7.15 km'), findsWidgets);
      expect(find.text('5:52 /km'), findsOneWidget);
      expect(find.text('Health'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.byKey(const Key('strava-tax-card')),
        200.0,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('7.150 km'), findsOneWidget);
      expect(find.textContaining('7.10 km'), findsOneWidget);

      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save FIT'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();

      final fitReparsed = CoreEngine.parseFit(port.lastSavedBytes!);
      expect(fitReparsed.activity.deviceInfo, 'Health');
      expect(
        fitReparsed.activity.trackpoints.last.cumulativeDistanceMeters,
        closeTo(7150.0, 0.05),
      );
    },
  );

  testWidgets(
    'Overview quick Set Distance Override shortcut works for standard GPX lacking recorded distance and syncs with Edit tab',
    (tester) async {
      final port = _InMemoryPlatformIoPort(
        nextPickedFile: PickedSourceFile(
          fileName: 'standard_loop.gpx',
          bytes: _utf8(_standardGpxNoRecordedDistance),
        ),
      );

      await _importSource(tester, port);

      final quickBtn =
          find.byKey(const Key('overview-set-distance-override-button'));
      await tester.scrollUntilVisible(
        quickBtn,
        200.0,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(quickBtn, findsOneWidget);
      expect(find.textContaining('FIT or TCX'), findsOneWidget);

      // Tap quick Set Distance Override -> enter 7.15 -> Apply
      await tester.tap(quickBtn);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('overview-distance-override-dialog')),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const Key('overview-distance-override-field')),
        '7.15',
      );
      await tester.tap(
        find.byKey(const Key('overview-apply-distance-override-button')),
      );
      await tester.pumpAndSettle();

      // Overview immediately reflects 7.15 km and Distance Override row
      expect(find.text('7.15 km'), findsWidgets);

      // Edit & Channels tab is synced to 7.15
      await tester.tap(find.text('Edit & Channels'));
      await tester.pumpAndSettle();
      final editField =
          find.byKey(const Key('edit-distance-override-field'));
      expect(tester.widget<TextField>(editField).controller?.text, '7.15');

      // Export FIT preserves 7150.0 m
      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save FIT'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();

      final fitReparsed = CoreEngine.parseFit(port.lastSavedBytes!);
      expect(
        fitReparsed.activity.trackpoints.last.cumulativeDistanceMeters,
        closeTo(7150.0, 0.05),
      );

      // Re-open quick Set Distance Override on Overview and clear it -> Edit tab clears too
      await tester.tap(find.text('Overview'));
      await tester.pumpAndSettle();
      await tester.tap(quickBtn);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('overview-clear-distance-override-button')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Edit & Channels'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(editField).controller?.text, isEmpty);
    },
  );
}
