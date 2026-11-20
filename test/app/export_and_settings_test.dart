import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_it/app/sync_it_app.dart';
import 'package:sync_it/port/platform_io_port.dart';

class _InMemoryPlatformIoPort implements PlatformIoPort {
  _InMemoryPlatformIoPort({this.nextPickedFile});

  PickedSourceFile? nextPickedFile;
  String? lastSavedFileName;
  Uint8List? lastSavedBytes;
  String? lastSharedFileName;
  Uint8List? lastSharedBytes;
  final List<String> copiedTexts = <String>[];
  final List<Uri> launchedUrls = <Uri>[];

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
  }) async {
    lastSharedFileName = fileName;
    lastSharedBytes = bytes;
  }

  @override
  Future<bool> isMapTilesAvailable() async => false;

  @override
  Future<void> copyToClipboard(String text) async {
    copiedTexts.add(text);
  }

  @override
  Future<bool> launchExternalUrl(Uri url) async {
    launchedUrls.add(url);
    return true;
  }

  @override
  Future<IncomingSourceBatch?> consumeInitialIncomingSources() async => null;

  @override
  Stream<IncomingSourceBatch> get incomingSourceBatches => const Stream.empty();
}

Uint8List _utf8(String s) => Uint8List.fromList(utf8.encode(s));

const _sampleGpx = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="TestWatch"
  xmlns="http://www.topografix.com/GPX/1/1"
  xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1">
  <trk>
    <name>Evening Jog: Hill / Repeats!</name>
    <desc>5x400m uphill efforts</desc>
    <type>running</type>
    <trkseg>
      <trkpt lat="14.600000" lon="120.984000">
        <ele>10.0</ele>
        <time>2026-11-19T18:00:00Z</time>
        <extensions>
          <gpxtpx:TrackPointExtension>
            <gpxtpx:hr>140</gpxtpx:hr>
          </gpxtpx:TrackPointExtension>
        </extensions>
      </trkpt>
      <trkpt lat="14.609000" lon="120.984000">
        <ele>40.0</ele>
        <time>2026-11-19T18:05:00Z</time>
        <extensions>
          <gpxtpx:TrackPointExtension>
            <gpxtpx:hr>165</gpxtpx:hr>
          </gpxtpx:TrackPointExtension>
        </extensions>
      </trkpt>
    </trkseg>
  </trk>
</gpx>''';

Future<void> _importSampleActivity(
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
    'Export tab generates smart default filename from Activity date and title with editable override',
    (tester) async {
      final port = _InMemoryPlatformIoPort(
        nextPickedFile: PickedSourceFile(
          fileName: 'raw_watch.gpx',
          bytes: _utf8(_sampleGpx),
        ),
      );

      await _importSampleActivity(tester, port);

      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();

      final filenameField = find.byKey(const Key('export-filename-field'));
      expect(filenameField, findsOneWidget);
      expect(
        tester.widget<TextField>(filenameField).controller?.text,
        '2026-11-19_evening_jog_hill_repeats.fit',
      );

      // Switching format updates the extension on the smart filename.
      await tester.tap(find.text('GPX'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(filenameField).controller?.text,
        '2026-11-19_evening_jog_hill_repeats.gpx',
      );

      // User can override the filename before saving or sharing.
      await tester.enterText(filenameField, 'my/custom:run');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save GPX'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();

      expect(port.lastSavedFileName, 'my_custom_run.gpx');

      await tester.tap(find.text('Share GPX'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();

      expect(port.lastSharedFileName, 'my_custom_run.gpx');
    },
  );

  testWidgets(
    'Post-export Strava Upload Helper copies title/description with confirmation and opens Strava upload URL',
    (tester) async {
      final port = _InMemoryPlatformIoPort(
        nextPickedFile: PickedSourceFile(
          fileName: 'raw_watch.gpx',
          bytes: _utf8(_sampleGpx),
        ),
      );

      await _importSampleActivity(tester, port);

      await tester.tap(find.text('Edit & Channels'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('edit-title-field')),
        'Edited Hill Repeats',
      );
      await tester.enterText(
        find.byKey(const Key('edit-description-field')),
        'Felt strong on reps 4-5',
      );

      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save FIT'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Strava Upload Helper'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('strava-upload-helper-card')));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('copy-title-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('copy-title-button')));
      await tester.pumpAndSettle();
      expect(port.copiedTexts, contains('Edited Hill Repeats'));
      expect(find.text('Title copied'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('copy-description-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('copy-description-button')));
      await tester.pumpAndSettle();
      expect(port.copiedTexts, contains('Felt strong on reps 4-5'));
      expect(find.text('Description copied'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('open-strava-upload-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-strava-upload-button')));
      await tester.pumpAndSettle();
      expect(
        port.launchedUrls,
        contains(Uri.parse('https://www.strava.com/upload/select')),
      );
    },
  );

  testWidgets(
    'Settings sheet switches display units between Metric (default) and Imperial across Workbench immediately',
    (tester) async {
      final port = _InMemoryPlatformIoPort(
        nextPickedFile: PickedSourceFile(
          fileName: 'raw_watch.gpx',
          bytes: _utf8(_sampleGpx),
        ),
      );

      await _importSampleActivity(tester, port);

      // Metric defaults on Overview
      expect(find.textContaining(' km'), findsWidgets);
      expect(find.textContaining('30 m'), findsWidgets);
      expect(find.textContaining('/km'), findsWidgets);
      expect(find.textContaining(' mi'), findsNothing);
      expect(find.textContaining(' ft'), findsNothing);
      expect(find.textContaining('/mi'), findsNothing);

      // Open Settings sheet from AppBar
      await tester.tap(find.byKey(const Key('settings-button')));
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Metric'), findsOneWidget);
      expect(find.text('Imperial'), findsOneWidget);

      await tester.tap(find.text('Imperial'));
      await tester.pumpAndSettle();

      // Dismiss sheet
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      // Imperial units updated across Overview, charts, and lap table
      expect(find.textContaining(' mi'), findsWidgets);
      expect(find.textContaining('98 ft'), findsWidgets);
      expect(find.textContaining('/mi'), findsWidgets);
      expect(find.textContaining(' km'), findsNothing);
      expect(find.textContaining('/km'), findsNothing);
    },
  );

  testWidgets(
    'Settings sheet switches app theme between System (default), Light, and Dark immediately',
    (tester) async {
      final port = _InMemoryPlatformIoPort(
        nextPickedFile: PickedSourceFile(
          fileName: 'raw_watch.gpx',
          bytes: _utf8(_sampleGpx),
        ),
      );

      await _importSampleActivity(tester, port);

      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.system,
      );

      await tester.tap(find.byKey(const Key('settings-button')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark,
      );
      expect(
        Theme.of(tester.element(find.byType(Scaffold).first)).brightness,
        Brightness.dark,
      );

      await tester.tap(find.text('Light'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.light,
      );
      expect(
        Theme.of(tester.element(find.byType(Scaffold).first)).brightness,
        Brightness.light,
      );

      await tester.tap(find.text('System'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.system,
      );
    },
  );
}
