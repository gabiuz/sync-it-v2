import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_it/app/sync_it_app.dart';
import 'package:sync_it/core/core_engine.dart';
import 'package:sync_it/port/platform_io_port.dart';

// 1x1 transparent PNG bytes.
final _transparentPng = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

class _FakeTileHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _FakeTileHttpClient();
}

class _FakeTileHttpClient implements HttpClient {
  @override
  bool autoUncompress = true;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _FakeTileHttpRequest();

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _FakeTileHttpRequest();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeTileHttpRequest implements HttpClientRequest {
  @override
  final HttpHeaders headers = _FakeHttpHeaders();

  @override
  bool followRedirects = true;

  @override
  int maxRedirects = 5;

  @override
  bool persistentConnection = true;

  @override
  int contentLength = -1;

  @override
  Future<void> addStream(Stream<List<int>> stream) async {}

  @override
  Future<HttpClientResponse> close() async => _FakeTileHttpResponse();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeHttpHeaders implements HttpHeaders {
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  void forEach(void Function(String name, List<String> values) action) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeTileHttpResponse extends Stream<List<int>>
    implements HttpClientResponse {
  @override
  int get statusCode => 200;

  @override
  String get reasonPhrase => 'OK';

  @override
  int get contentLength => _transparentPng.length;

  @override
  bool get isRedirect => false;

  @override
  List<RedirectInfo> get redirects => const [];

  @override
  bool get persistentConnection => false;

  @override
  HttpHeaders get headers => _FakeHttpHeaders();

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.value(_transparentPng).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

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

  @override
  Future<void> copyToClipboard(String text) async {}

  @override
  Future<bool> launchExternalUrl(Uri url) async => true;
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
      await HttpOverrides.runZoned(() async {
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
      }, createHttpClient: (ctx) => _FakeTileHttpOverrides().createHttpClient(ctx));
    },
  );

  testWidgets(
    'Overview falls back to offline vector-canvas when online check passes but tile loading fails at runtime',
    (tester) async {
      PaintingBinding.instance.imageCache.clear();
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
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(seconds: 1));
        if (find.byKey(const Key('offline-route-canvas')).evaluate().isNotEmpty) {
          break;
        }
      }

      expect(find.byKey(const Key('offline-route-canvas')), findsOneWidget);
      expect(find.byType(FlutterMap), findsNothing);
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
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(seconds: 1));
        if (find.byKey(const Key('offline-route-canvas')).evaluate().isNotEmpty) {
          break;
        }
      }

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
