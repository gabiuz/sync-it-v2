import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_it/app/sync_it_app.dart';
import 'package:sync_it/core/core_engine.dart';
import 'package:sync_it/port/platform_io_port.dart';

class FakePlatformIoPort implements PlatformIoPort {
  FakePlatformIoPort({this.nextPickedFile});

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

Uint8List _utf8(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  testWidgets('end-to-end GPX import, diagnostic banner, edit, and save/share export', (tester) async {
    const quirkyGpx = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="TestWatch"
  xmlns="http://www.topografix.com/GPX/1/1"
  xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1">
  <trk>
    <name>Evening Jog</name>
    <desc>Original note</desc>
    <type>running</type>
    <trkseg>
      <trkpt lat="14.600000" lon="120.984000">
        <ele>10.0</ele>
        <time>2026-11-19T18:00:00Z</time>
        <extensions>
          <gpxtpx:TrackPointExtension>
            <gpxtpx:hr>0</gpxtpx:hr>
          </gpxtpx:TrackPointExtension>
        </extensions>
      </trkpt>
      <trkpt lat="14.600900" lon="120.984000">
        <ele>14.0</ele>
        <time>2026-11-19T18:01:00Z</time>
        <extensions>
          <gpxtpx:TrackPointExtension>
            <gpxtpx:hr>150</gpxtpx:hr>
          </gpxtpx:TrackPointExtension>
        </extensions>
      </trkpt>
    </trkseg>
  </trk>
</gpx>''';

    final fakePort = FakePlatformIoPort(
      nextPickedFile: PickedSourceFile(
        fileName: 'evening_jog.gpx',
        bytes: _utf8(quirkyGpx),
      ),
    );

    await tester.pumpWidget(SyncItApp(platformIoPort: fakePort));

    // Start screen
    expect(find.text('Sync-It'), findsOneWidget);
    await tester.tap(find.text('Import GPX Source File'));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();

    // Workbench: diagnostic banner & Overview tab
    expect(find.textContaining('zero-bpm heart rate dropout'), findsOneWidget);
    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('Edit & Channels'), findsOneWidget);
    expect(find.text('Export'), findsOneWidget);
    expect(find.text('Evening Jog'), findsWidgets);
    expect(find.text('150 bpm'), findsWidgets);

    // Edit & Channels tab
    await tester.tap(find.text('Edit & Channels'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('edit-title-field')),
      'Tempo Intervals',
    );
    await tester.enterText(
      find.byKey(const Key('edit-description-field')),
      'Negative split finish',
    );

    // Change sport type to Cycling
    await tester.tap(find.byKey(const Key('edit-sport-dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cycling').last);
    await tester.pumpAndSettle();

    // Export tab: Save & Share
    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save GPX'));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();

    expect(fakePort.lastSavedBytes, isNotNull);
    final savedParsed = CoreEngine.parseGpx(fakePort.lastSavedBytes!);
    expect(savedParsed.activity.title, 'Tempo Intervals');
    expect(savedParsed.activity.description, 'Negative split finish');
    expect(savedParsed.activity.sportType, SportType.cycling);

    await tester.tap(find.text('Share GPX'));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(fakePort.lastSharedBytes, isNotNull);
  });

  testWidgets('surfaces actionable error on Start screen when GPX is corrupted', (tester) async {
    final fakePort = FakePlatformIoPort(
      nextPickedFile: PickedSourceFile(
        fileName: 'broken.gpx',
        bytes: _utf8('<gpx><broken'),
      ),
    );

    await tester.pumpWidget(SyncItApp(platformIoPort: fakePort));
    await tester.tap(find.text('Import GPX Source File'));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();

    expect(find.textContaining('Corrupted GPX XML'), findsOneWidget);
  });
}
