import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpx_lab/app/gpx_lab_app.dart';
import 'package:gpx_lab/core/core_engine.dart';
import 'package:gpx_lab/port/platform_io_port.dart';

class _FakeKmlPlatformIoPort implements PlatformIoPort {
  _FakeKmlPlatformIoPort({
    this.nextPickedFile,
    this.pickedFiles = const [],
    this.initialBatch,
  });

  PickedSourceFile? nextPickedFile;
  List<PickedSourceFile> pickedFiles;
  IncomingSourceBatch? initialBatch;
  String? lastSavedFileName;
  Uint8List? lastSavedBytes;
  String? lastSharedFileName;
  Uint8List? lastSharedBytes;

  final StreamController<IncomingSourceBatch> _incomingController =
      StreamController<IncomingSourceBatch>.broadcast();

  Future<void> dispose() => _incomingController.close();

  @override
  Future<PickedSourceFile?> pickSourceFile() async => nextPickedFile;

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
  }) async {
    lastSharedFileName = fileName;
    lastSharedBytes = bytes;
  }

  @override
  Future<bool> isMapTilesAvailable() async => false;

  @override
  Future<void> copyToClipboard(String text) async {}

  @override
  Future<bool> launchExternalUrl(Uri url) async => true;

  @override
  Future<IncomingSourceBatch?> consumeInitialIncomingSources() async {
    final batch = initialBatch;
    initialBatch = null;
    return batch;
  }

  @override
  Stream<IncomingSourceBatch> get incomingSourceBatches =>
      _incomingController.stream;
}

Uint8List _utf8(String s) => Uint8List.fromList(utf8.encode(s));

Future<void> _settleIsolateWork(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
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

const _sampleHuaweiKml = '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2"
  xmlns:gx="http://www.google.com/kml/ext/2.2">
  <Document>
    <name>Huawei Evening Run</name>
    <description>Park loop</description>
    <ExtendedData>
      <Data name="sport"><value>running</value></Data>
      <Data name="creator"><value>HUAWEI WATCH GT 4</value></Data>
    </ExtendedData>
    <Placemark>
      <gx:Track>
        <when>2026-11-19T18:00:00Z</when>
        <when>2026-11-19T18:05:00Z</when>
        <gx:coord>120.984000 14.600000 10.0</gx:coord>
        <gx:coord>120.984000 14.604500 25.0</gx:coord>
        <ExtendedData>
          <SchemaData schemaUrl="#s">
            <gx:SimpleArrayData name="heartrate">
              <gx:value>0</gx:value>
              <gx:value>158</gx:value>
            </gx:SimpleArrayData>
            <gx:SimpleArrayData name="cadence">
              <gx:value>84</gx:value>
              <gx:value>88</gx:value>
            </gx:SimpleArrayData>
          </SchemaData>
        </ExtendedData>
      </gx:Track>
    </Placemark>
  </Document>
</kml>''';

const _overlappingTcx = '''<?xml version="1.0" encoding="UTF-8"?>
<TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2">
  <Activities>
    <Activity Sport="Running">
      <Id>2026-11-19T18:00:00Z</Id>
      <Lap StartTime="2026-11-19T18:00:00Z">
        <TotalTimeSeconds>300</TotalTimeSeconds>
        <DistanceMeters>500</DistanceMeters>
        <Calories>75</Calories>
        <Track>
          <Trackpoint>
            <Time>2026-11-19T18:00:00Z</Time>
            <DistanceMeters>0</DistanceMeters>
            <HeartRateBpm><Value>145</Value></HeartRateBpm>
          </Trackpoint>
          <Trackpoint>
            <Time>2026-11-19T18:05:00Z</Time>
            <DistanceMeters>500</DistanceMeters>
            <HeartRateBpm><Value>162</Value></HeartRateBpm>
          </Trackpoint>
        </Track>
      </Lap>
    </Activity>
  </Activities>
</TrainingCenterDatabase>''';

void main() {
  testWidgets(
    'end-to-end KML import, diagnostic banner, edit, 4-format selector (FIT default), KML warnings, and save/share export',
    (tester) async {
      final fakePort = _FakeKmlPlatformIoPort(
        nextPickedFile: PickedSourceFile(
          fileName: 'huawei_evening.kml',
          bytes: _utf8(_sampleHuaweiKml),
        ),
      );
      addTearDown(fakePort.dispose);

      await tester.pumpWidget(GpxLabApp(platformIoPort: fakePort));
      await tester.tap(find.byKey(const Key('import-source-button')));
      await _settleIsolateWork(tester);

      // Overview: zero-bpm HR dropout banner & stats
      expect(find.textContaining('zero-bpm heart rate dropout'), findsOneWidget);
      expect(find.text('Huawei Evening Run'), findsWidgets);
      expect(find.text('158 bpm'), findsWidgets);

      // Edit & Channels: update metadata and apply Distance Override
      await tester.tap(find.text('Edit & Channels'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('edit-title-field')),
        'KML Tempo Edit',
      );
      await tester.enterText(
        find.byKey(const Key('edit-description-field')),
        'Updated description',
      );
      await tester.enterText(
        find.byKey(const Key('edit-distance-override-field')),
        '0.60',
      );
      await tester.pumpAndSettle();

      // Export tab: FIT remains default in 4-format selector (FIT, TCX, GPX, KML)
      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();

      expect(find.text('FIT'), findsOneWidget);
      expect(find.text('TCX'), findsOneWidget);
      expect(find.text('GPX'), findsOneWidget);
      expect(find.text('KML'), findsOneWidget);
      expect(find.text('2026-11-19_kml_tempo_edit.fit'), findsOneWidget);

      // Switch to KML -> updates filename & surfaces Distance Override + Strava incompatibility warnings
      await tester.tap(find.text('KML'));
      await tester.pumpAndSettle();

      final filenameField = find.byKey(const Key('export-filename-field'));
      expect(
        tester.widget<TextField>(filenameField).controller?.text,
        '2026-11-19_kml_tempo_edit.kml',
      );
      expect(
        find.byKey(const Key('kml-distance-override-warning')),
        findsOneWidget,
      );

      final exportScrollable = find
          .descendant(
            of: find.byKey(const Key('export-tab-list')),
            matching: find.byType(Scrollable),
          )
          .first;
      final stravaWarning = find.byKey(
        Key('export-warning-${ExportWarningCode.kmlNotAcceptedByStrava.name}'),
      );
      await tester.scrollUntilVisible(
        stravaWarning,
        200.0,
        scrollable: exportScrollable,
      );
      expect(stravaWarning, findsOneWidget);

      // Custom filename sanitization supports .kml
      await tester.scrollUntilVisible(
        filenameField,
        -200.0,
        scrollable: exportScrollable,
      );
      await tester.enterText(filenameField, 'my/kml:export.kml');
      await tester.pumpAndSettle();

      final saveKmlBtn = find.text('Save KML');
      await tester.ensureVisible(saveKmlBtn);
      await tester.pumpAndSettle();
      await tester.tap(saveKmlBtn);
      await _settleIsolateWork(tester);

      expect(fakePort.lastSavedFileName, 'my_kml_export.kml');
      expect(fakePort.lastSavedBytes, isNotNull);
      final reparsed = CoreEngine.parseKml(fakePort.lastSavedBytes!);
      expect(reparsed.activity.title, 'KML Tempo Edit');
      expect(reparsed.activity.description, 'Updated description');

      final shareKmlBtn = find.text('Share KML');
      await tester.ensureVisible(shareKmlBtn);
      await tester.pumpAndSettle();
      await tester.tap(shareKmlBtn);
      await _settleIsolateWork(tester);
      expect(fakePort.lastSharedFileName, 'my_kml_export.kml');
      expect(fakePort.lastSharedBytes, isNotNull);
    },
  );

  testWidgets(
    'blocks KML export when GPS Position is stripped',
    (tester) async {
      final fakePort = _FakeKmlPlatformIoPort(
        nextPickedFile: PickedSourceFile(
          fileName: 'huawei_evening.kml',
          bytes: _utf8(_sampleHuaweiKml),
        ),
      );
      addTearDown(fakePort.dispose);

      await tester.pumpWidget(GpxLabApp(platformIoPort: fakePort));
      await tester.tap(find.byKey(const Key('import-source-button')));
      await _settleIsolateWork(tester);

      await tester.tap(find.text('Edit & Channels'));
      await tester.pumpAndSettle();

      final gpsToggle = find.byKey(
        Key('channel-toggle-${StrippableChannel.gps.name}'),
      );
      await tester.ensureVisible(gpsToggle);
      await tester.pumpAndSettle();
      await tester.tap(gpsToggle);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('KML'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('export-blocking-warning')), findsOneWidget);
      final saveKmlButton = tester.widget<ButtonStyleButton>(
        find.widgetWithText(FilledButton, 'Save KML'),
      );
      final shareKmlButton = tester.widget<ButtonStyleButton>(
        find.widgetWithText(OutlinedButton, 'Share KML'),
      );
      expect(saveKmlButton.onPressed, isNull);
      expect(shareKmlButton.onPressed, isNull);
    },
  );

  testWidgets(
    'surfaces actionable errors on Start screen for corrupted and untimestamped <LineString> KMLs',
    (tester) async {
      final fakePort = _FakeKmlPlatformIoPort(
        nextPickedFile: PickedSourceFile(
          fileName: 'route_only.kml',
          bytes: _utf8('''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <Placemark>
      <LineString>
        <coordinates>120.9840,14.6000,10 120.9840,14.6010,12</coordinates>
      </LineString>
    </Placemark>
  </Document>
</kml>'''),
        ),
      );
      addTearDown(fakePort.dispose);

      await tester.pumpWidget(GpxLabApp(platformIoPort: fakePort));
      await tester.tap(find.byKey(const Key('import-source-button')));
      await _settleIsolateWork(tester);

      expect(find.textContaining('<LineString>'), findsOneWidget);

      fakePort.nextPickedFile = PickedSourceFile(
        fileName: 'broken.kml',
        bytes: _utf8('<kml><Document><broken'),
      );
      await tester.tap(find.byKey(const Key('import-source-button')));
      await _settleIsolateWork(tester);

      expect(find.textContaining('Corrupted KML XML'), findsOneWidget);
    },
  );

  testWidgets(
    'handles cold-launch OS Open-With KML intent including extension-less XML content sniffing',
    (tester) async {
      final coldPort = _FakeKmlPlatformIoPort(
        initialBatch: IncomingSourceBatch(
          files: [
            PickedSourceFile(
              fileName: 'shared_workout',
              bytes: _utf8(_sampleHuaweiKml),
            ),
          ],
        ),
      );
      addTearDown(coldPort.dispose);

      await tester.pumpWidget(GpxLabApp(platformIoPort: coldPort));
      await _settleIsolateWork(tester);

      expect(find.text('Huawei Evening Run'), findsWidgets);
      expect(find.text('Overview'), findsOneWidget);
    },
  );

  testWidgets(
    'handles multi-file overlapping KML + TCX OS intent with Channel Blending',
    (tester) async {
      final multiPort = _FakeKmlPlatformIoPort(
        initialBatch: IncomingSourceBatch(
          files: [
            PickedSourceFile(
              fileName: 'route.kml',
              bytes: _utf8(_sampleHuaweiKml),
            ),
            PickedSourceFile(
              fileName: 'hr.tcx',
              bytes: _utf8(_overlappingTcx),
            ),
          ],
        ),
      );
      addTearDown(multiPort.dispose);

      await tester.pumpWidget(GpxLabApp(platformIoPort: multiPort));
      await _settleIsolateWork(tester);

      expect(find.byKey(const Key('multi-file-mode-dialog')), findsOneWidget);
      expect(
        find.byKey(const Key('recommended-mode-channelBlending')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('choose-blend-mode-button')));
      await _settleIsolateWork(tester);

      expect(find.text('Overview'), findsOneWidget);
      await tester.tap(find.text('Edit & Channels'));
      await tester.pumpAndSettle();
      expect(find.text('Channel Blending'), findsOneWidget);
    },
  );
}
