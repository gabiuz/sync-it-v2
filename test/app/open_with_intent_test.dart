import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpx_lab/app/gpx_lab_app.dart';
import 'package:gpx_lab/port/platform_io_port.dart';

class _IntentFakePort implements PlatformIoPort {
  _IntentFakePort({this.initialBatch});

  IncomingSourceBatch? initialBatch;
  final StreamController<IncomingSourceBatch> _incomingController =
      StreamController<IncomingSourceBatch>.broadcast();

  void emitIncoming(IncomingSourceBatch batch) {
    _incomingController.add(batch);
  }

  Future<void> dispose() => _incomingController.close();

  @override
  Future<IncomingSourceBatch?> consumeInitialIncomingSources() async {
    final batch = initialBatch;
    initialBatch = null;
    return batch;
  }

  @override
  Stream<IncomingSourceBatch> get incomingSourceBatches =>
      _incomingController.stream;

  @override
  Future<PickedSourceFile?> pickSourceFile() async => null;

  @override
  Future<List<PickedSourceFile>> pickMultipleSourceFiles() async => const [];

  @override
  Future<bool> saveExportFile({
    required String suggestedFileName,
    required Uint8List bytes,
  }) async =>
      true;

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

Future<void> _settleIsolateWork(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 150)),
  );
  await tester.pumpAndSettle();
}

const _gpxMorning = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="Huawei Health"
  xmlns="http://www.topografix.com/GPX/1/1">
  <trk>
    <name>Morning Canal Run</name>
    <type>running</type>
    <trkseg>
      <trkpt lat="14.600000" lon="120.984000">
        <ele>10.0</ele>
        <time>2026-11-20T06:00:00Z</time>
      </trkpt>
      <trkpt lat="14.601000" lon="120.984000">
        <ele>12.0</ele>
        <time>2026-11-20T06:10:00Z</time>
      </trkpt>
    </trkseg>
  </trk>
</gpx>''';

const _tcxOverlapping = '''<?xml version="1.0" encoding="UTF-8"?>
<TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2">
  <Activities>
    <Activity Sport="Running">
      <Id>2026-11-20T06:02:00Z</Id>
      <Lap StartTime="2026-11-20T06:02:00Z">
        <TotalTimeSeconds>480</TotalTimeSeconds>
        <DistanceMeters>1200</DistanceMeters>
        <Calories>80</Calories>
        <Track>
          <Trackpoint>
            <Time>2026-11-20T06:02:00Z</Time>
            <DistanceMeters>0</DistanceMeters>
            <HeartRateBpm><Value>145</Value></HeartRateBpm>
          </Trackpoint>
          <Trackpoint>
            <Time>2026-11-20T06:10:00Z</Time>
            <DistanceMeters>1200</DistanceMeters>
            <HeartRateBpm><Value>158</Value></HeartRateBpm>
          </Trackpoint>
        </Track>
      </Lap>
    </Activity>
  </Activities>
</TrainingCenterDatabase>''';

const _gpxAfternoon = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="Huawei Health"
  xmlns="http://www.topografix.com/GPX/1/1">
  <trk>
    <name>Afternoon Cool Down</name>
    <type>running</type>
    <trkseg>
      <trkpt lat="14.601000" lon="120.984000">
        <ele>12.0</ele>
        <time>2026-11-20T07:00:00Z</time>
      </trkpt>
      <trkpt lat="14.602000" lon="120.984000">
        <ele>14.0</ele>
        <time>2026-11-20T07:10:00Z</time>
      </trkpt>
    </trkseg>
  </trk>
</gpx>''';

void main() {
  testWidgets(
    'cold-launch single-file OS intent bypasses Start screen into 3-tab Workbench',
    (tester) async {
      final port = _IntentFakePort(
        initialBatch: IncomingSourceBatch(
          files: [
            PickedSourceFile(
              fileName: 'morning_run.gpx',
              bytes: _utf8(_gpxMorning),
            ),
          ],
        ),
      );
      addTearDown(port.dispose);

      await tester.pumpWidget(GpxLabApp(platformIoPort: port));
      await _settleIsolateWork(tester);

      expect(find.byKey(const Key('import-source-button')), findsNothing);
      expect(find.text('Overview'), findsOneWidget);
      expect(find.text('Edit & Channels'), findsOneWidget);
      expect(find.text('Export'), findsOneWidget);
      expect(find.text('Morning Canal Run'), findsWidgets);
    },
  );

  testWidgets(
    'warm-launch single-file OS intent replaces active Workbench Activity',
    (tester) async {
      final port = _IntentFakePort(
        initialBatch: IncomingSourceBatch(
          files: [
            PickedSourceFile(
              fileName: 'morning_run.gpx',
              bytes: _utf8(_gpxMorning),
            ),
          ],
        ),
      );
      addTearDown(port.dispose);

      await tester.pumpWidget(GpxLabApp(platformIoPort: port));
      await _settleIsolateWork(tester);
      expect(find.text('Morning Canal Run'), findsWidgets);

      port.emitIncoming(
        IncomingSourceBatch(
          files: [
            PickedSourceFile(
              fileName: 'afternoon.gpx',
              bytes: _utf8(_gpxAfternoon),
            ),
          ],
        ),
      );
      await _settleIsolateWork(tester);

      expect(find.text('Afternoon Cool Down'), findsWidgets);
      expect(find.text('Morning Canal Run'), findsNothing);
    },
  );

  testWidgets(
    'multi-file overlapping OS intent recommends Channel Blending and routes to Workbench',
    (tester) async {
      final port = _IntentFakePort();
      addTearDown(port.dispose);

      await tester.pumpWidget(GpxLabApp(platformIoPort: port));
      await tester.pumpAndSettle();

      port.emitIncoming(
        IncomingSourceBatch(
          files: [
            PickedSourceFile(
              fileName: 'watch.gpx',
              bytes: _utf8(_gpxMorning),
            ),
            PickedSourceFile(
              fileName: 'strap.tcx',
              bytes: _utf8(_tcxOverlapping),
            ),
          ],
        ),
      );
      await _settleIsolateWork(tester);

      expect(find.byKey(const Key('multi-file-mode-dialog')), findsOneWidget);
      expect(
        find.byKey(const Key('recommended-mode-channelBlending')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('choose-blend-mode-button')));
      await _settleIsolateWork(tester);

      expect(find.byKey(const Key('multi-file-mode-dialog')), findsNothing);
      expect(find.text('Overview'), findsOneWidget);
      expect(find.text('Edit & Channels'), findsOneWidget);
      await tester.tap(find.text('Edit & Channels'));
      await tester.pumpAndSettle();
      expect(find.text('Channel Blending'), findsOneWidget);
    },
  );

  testWidgets(
    'multi-file sequential OS intent recommends Sequential Stitching and routes to Workbench',
    (tester) async {
      final port = _IntentFakePort();
      addTearDown(port.dispose);

      await tester.pumpWidget(GpxLabApp(platformIoPort: port));
      await tester.pumpAndSettle();

      port.emitIncoming(
        IncomingSourceBatch(
          files: [
            PickedSourceFile(
              fileName: 'part1.gpx',
              bytes: _utf8(_gpxMorning),
            ),
            PickedSourceFile(
              fileName: 'part2.gpx',
              bytes: _utf8(_gpxAfternoon),
            ),
          ],
        ),
      );
      await _settleIsolateWork(tester);

      expect(find.byKey(const Key('multi-file-mode-dialog')), findsOneWidget);
      expect(
        find.byKey(const Key('recommended-mode-sequentialStitching')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('choose-stitch-mode-button')));
      await _settleIsolateWork(tester);

      expect(find.byKey(const Key('multi-file-mode-dialog')), findsNothing);
      expect(find.text('Overview'), findsOneWidget);
      expect(find.text('Edit & Channels'), findsOneWidget);
      await tester.tap(find.text('Edit & Channels'));
      await tester.pumpAndSettle();
      expect(find.text('Sequential Stitching'), findsOneWidget);
    },
  );

  testWidgets(
    'unsupported file type and unreadable URI errors fail cleanly and return to Start screen',
    (tester) async {
      final port = _IntentFakePort(
        initialBatch: IncomingSourceBatch(
          files: [
            PickedSourceFile(
              fileName: 'morning_run.gpx',
              bytes: _utf8(_gpxMorning),
            ),
          ],
        ),
      );
      addTearDown(port.dispose);

      await tester.pumpWidget(GpxLabApp(platformIoPort: port));
      await _settleIsolateWork(tester);
      expect(find.text('Morning Canal Run'), findsWidgets);

      port.emitIncoming(
        IncomingSourceBatch(
          files: [
            PickedSourceFile(
              fileName: 'notes.txt',
              bytes: _utf8('not a workout file'),
            ),
          ],
        ),
      );
      await _settleIsolateWork(tester);

      expect(find.byKey(const Key('import-source-button')), findsOneWidget);
      expect(find.textContaining('Unsupported file type'), findsOneWidget);
      expect(
        find.textContaining(
          'GPX Lab only supports .gpx, .tcx, .fit, and .kml files.',
        ),
        findsOneWidget,
      );

      port.emitIncoming(
        const IncomingSourceBatch(
          errors: ['Unable to read shared file "broken.fit".'],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('import-source-button')), findsOneWidget);
      expect(
        find.text('Unable to read shared file "broken.fit".'),
        findsOneWidget,
      );
    },
  );
}
