import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_it/app/sync_it_app.dart';
import 'package:sync_it/core/core_engine.dart';
import 'package:sync_it/port/platform_io_port.dart';

class _InspectorFakePort implements PlatformIoPort {
  _InspectorFakePort({
    required this.nextPickedFile,
    required this.online,
  });

  final PickedSourceFile nextPickedFile;
  final bool online;

  @override
  Future<PickedSourceFile?> pickSourceFile() async => nextPickedFile;

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
  Future<bool> isMapTilesAvailable() async => online;
}

Future<void> _pumpUntilSettledAsync(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }
}

Uint8List _buildOutdoorTcx() {
  const tcx = '''<?xml version="1.0" encoding="UTF-8"?>
<TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2">
  <Activities>
    <Activity Sport="Running">
      <Id>2026-11-19T06:00:00Z</Id>
      <Lap StartTime="2026-11-19T06:00:00Z">
        <TotalTimeSeconds>300</TotalTimeSeconds>
        <DistanceMeters>1000</DistanceMeters>
        <AverageHeartRateBpm><Value>152</Value></AverageHeartRateBpm>
        <Track>
          <Trackpoint>
            <Time>2026-11-19T06:00:00Z</Time>
            <Position><LatitudeDegrees>14.5500</LatitudeDegrees><LongitudeDegrees>121.0200</LongitudeDegrees></Position>
            <AltitudeMeters>15.0</AltitudeMeters>
            <DistanceMeters>0.0</DistanceMeters>
            <HeartRateBpm><Value>145</Value></HeartRateBpm>
          </Trackpoint>
          <Trackpoint>
            <Time>2026-11-19T06:02:30Z</Time>
            <Position><LatitudeDegrees>14.5545</LatitudeDegrees><LongitudeDegrees>121.0210</LongitudeDegrees></Position>
            <AltitudeMeters>22.0</AltitudeMeters>
            <DistanceMeters>500.0</DistanceMeters>
            <HeartRateBpm><Value>152</Value></HeartRateBpm>
          </Trackpoint>
          <Trackpoint>
            <Time>2026-11-19T06:05:00Z</Time>
            <Position><LatitudeDegrees>14.5590</LatitudeDegrees><LongitudeDegrees>121.0220</LongitudeDegrees></Position>
            <AltitudeMeters>18.0</AltitudeMeters>
            <DistanceMeters>1000.0</DistanceMeters>
            <HeartRateBpm><Value>159</Value></HeartRateBpm>
          </Trackpoint>
        </Track>
      </Lap>
      <Lap StartTime="2026-11-19T06:05:00Z">
        <TotalTimeSeconds>300</TotalTimeSeconds>
        <DistanceMeters>1000</DistanceMeters>
        <AverageHeartRateBpm><Value>162</Value></AverageHeartRateBpm>
        <Track>
          <Trackpoint>
            <Time>2026-11-19T06:05:01Z</Time>
            <Position><LatitudeDegrees>14.5590</LatitudeDegrees><LongitudeDegrees>121.0220</LongitudeDegrees></Position>
            <AltitudeMeters>18.0</AltitudeMeters>
            <DistanceMeters>1000.0</DistanceMeters>
            <HeartRateBpm><Value>159</Value></HeartRateBpm>
          </Trackpoint>
          <Trackpoint>
            <Time>2026-11-19T06:10:00Z</Time>
            <Position><LatitudeDegrees>14.5680</LatitudeDegrees><LongitudeDegrees>121.0240</LongitudeDegrees></Position>
            <AltitudeMeters>25.0</AltitudeMeters>
            <DistanceMeters>2000.0</DistanceMeters>
            <HeartRateBpm><Value>165</Value></HeartRateBpm>
          </Trackpoint>
        </Track>
      </Lap>
    </Activity>
  </Activities>
</TrainingCenterDatabase>''';
  return Uint8List.fromList(utf8.encode(tcx));
}

Uint8List _buildIndoorFit() {
  final start = DateTime.utc(2026, 11, 19, 7, 0, 0);
  final activity = Activity(
    title: 'Indoor Treadmill',
    description: '',
    sportType: SportType.running,
    trackpoints: [
      Trackpoint(
        timestamp: start,
        cumulativeDistanceMeters: 0,
        heartRateBpm: 138,
      ),
      Trackpoint(
        timestamp: start.add(const Duration(minutes: 5)),
        cumulativeDistanceMeters: 1000,
        heartRateBpm: 148,
      ),
    ],
    laps: [
      Lap(
        startTime: start,
        endTime: start.add(const Duration(minutes: 5)),
        distanceMeters: 1000,
        avgHeartRateBpm: 143,
      ),
    ],
    availableChannels: const {Channel.distance, Channel.heartRate},
  );
  return CoreEngine.exportFit(
    activity,
    const ActivityEdit(title: 'Indoor Treadmill'),
  ).bytes;
}

void main() {
  testWidgets(
    'Overview renders interactive OpenStreetMap route map, channel charts, and structured lap table when online',
    (tester) async {
      final port = _InspectorFakePort(
        nextPickedFile: PickedSourceFile(
          fileName: 'morning_run.tcx',
          bytes: _buildOutdoorTcx(),
        ),
        online: true,
      );

      await tester.pumpWidget(SyncItApp(platformIoPort: port));
      await tester.tap(find.byKey(const Key('import-source-button')));
      await _pumpUntilSettledAsync(tester);

      expect(find.byType(FlutterMap), findsOneWidget);
      expect(find.byKey(const Key('osm-route-map')), findsOneWidget);
      expect(find.byKey(const Key('offline-route-canvas')), findsNothing);

      // Scroll down from the title card (above the interactive map) to verify
      // charts, scrubbing, and lap breakdown table.
      await tester.dragFrom(const Offset(100, 120), const Offset(0, -400));
      await tester.pump();
      await tester.dragFrom(const Offset(100, 120), const Offset(0, -400));
      await tester.pump();
      expect(find.byKey(const Key('chart-heart-rate')), findsOneWidget);

      await tester.dragFrom(const Offset(100, 120), const Offset(0, -300));
      await tester.pump();
      expect(find.byKey(const Key('chart-elevation')), findsOneWidget);
      expect(find.byKey(const Key('chart-pace')), findsOneWidget);

      await tester.dragFrom(const Offset(100, 120), const Offset(0, -450));
      await tester.pump();
      expect(find.byKey(const Key('lap-breakdown-table')), findsOneWidget);
      expect(find.text('152 bpm'), findsOneWidget);
      expect(find.text('162 bpm'), findsOneWidget);
    },
  );

  testWidgets(
    'Overview falls back to offline vector-canvas polyline when offline',
    (tester) async {
      final port = _InspectorFakePort(
        nextPickedFile: PickedSourceFile(
          fileName: 'morning_run.tcx',
          bytes: _buildOutdoorTcx(),
        ),
        online: false,
      );

      await tester.pumpWidget(SyncItApp(platformIoPort: port));
      await tester.tap(find.byKey(const Key('import-source-button')));
      await _pumpUntilSettledAsync(tester);

      expect(find.byKey(const Key('offline-route-canvas')), findsOneWidget);
      expect(find.byType(FlutterMap), findsNothing);
      expect(find.text('Offline Vector Map'), findsOneWidget);
    },
  );

  testWidgets(
    'Overview displays clean mapless/indoor state and marks unavailable channels cleanly when GPS/elevation are absent',
    (tester) async {
      final port = _InspectorFakePort(
        nextPickedFile: PickedSourceFile(
          fileName: 'indoor.fit',
          bytes: _buildIndoorFit(),
        ),
        online: true,
      );

      await tester.pumpWidget(SyncItApp(platformIoPort: port));
      await tester.tap(find.byKey(const Key('import-source-button')));
      await _pumpUntilSettledAsync(tester);

      expect(find.byKey(const Key('mapless-indoor-state')), findsOneWidget);
      expect(find.byType(FlutterMap), findsNothing);
      expect(find.byKey(const Key('offline-route-canvas')), findsNothing);

      final overviewScrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.byKey(const Key('chart-heart-rate')),
        300,
        scrollable: overviewScrollable,
      );
      expect(find.byKey(const Key('chart-heart-rate')), findsOneWidget);

      await tester.scrollUntilVisible(
        find.byKey(const Key('chart-elevation-unavailable')),
        300,
        scrollable: overviewScrollable,
      );
      expect(find.byKey(const Key('chart-elevation-unavailable')), findsOneWidget);
    },
  );
}
