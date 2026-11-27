import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpx_lab/app/channel_charts_section.dart';
import 'package:gpx_lab/app/gpx_lab_app.dart';
import 'package:gpx_lab/app/gpx_lab_brand_header.dart';
import 'package:gpx_lab/app/gpx_lab_theme.dart';
import 'package:gpx_lab/core/core_engine.dart';
import 'package:gpx_lab/port/platform_io_port.dart';

class _IdleFakePort implements PlatformIoPort {
  const _IdleFakePort();

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

  @override
  Future<IncomingSourceBatch?> consumeInitialIncomingSources() async => null;

  @override
  Stream<IncomingSourceBatch> get incomingSourceBatches => const Stream.empty();
}

void main() {
  group('GpxLabTheme & GpxLabBrandColors', () {
    test('builds light and dark Material 3 themes seeded with #1D63ED and cool-slate surfaces', () {
      final light = GpxLabTheme.light();
      final dark = GpxLabTheme.dark();

      expect(light.useMaterial3, isTrue);
      expect(light.brightness, Brightness.light);
      expect(light.colorScheme.primary, const Color(0xFF1D63ED));
      expect(light.colorScheme.surface, const Color(0xFFF8FAFC));
      // Cool-slate tint: blue channel exceeds red channel on surfaces.
      expect(light.colorScheme.surface.b, greaterThan(light.colorScheme.surface.r));
      expect(
        light.colorScheme.surfaceContainerLow.b,
        greaterThan(light.colorScheme.surfaceContainerLow.r),
      );

      expect(dark.useMaterial3, isTrue);
      expect(dark.brightness, Brightness.dark);
      expect(dark.colorScheme.surface, const Color(0xFF0B1120));
      expect(dark.colorScheme.surface.b, greaterThan(dark.colorScheme.surface.r));

      // Custom seed hex can drop in cleanly via seedColor parameter.
      final reseeded = GpxLabTheme.light(seedColor: const Color(0xFF0EA5E9));
      expect(reseeded.colorScheme.primary, isNot(equals(const Color(0xFF1D63ED))));
    });

    test('exposes harmonized map and Channel chart accents across light and dark modes', () {
      final lightBrand = GpxLabTheme.light().extension<GpxLabBrandColors>()!;
      final darkBrand = GpxLabTheme.dark().extension<GpxLabBrandColors>()!;

      for (final palette in [lightBrand, darkBrand]) {
        // Coral-red heart rate
        expect(palette.heartRate.r, greaterThan(palette.heartRate.b));
        expect(palette.heartRate.r, greaterThan(palette.heartRate.g));

        // Cobalt / sky-blue route and pace
        expect(palette.routeLine.b, greaterThan(palette.routeLine.r));
        expect(palette.pace.b, greaterThan(palette.pace.r));

        // Teal elevation
        expect(palette.elevation.g, greaterThan(palette.elevation.r));
        expect(palette.elevation.b, greaterThan(palette.elevation.r));
      }

      // ThemeExtension copyWith and lerp round-trip cleanly.
      final mid = lightBrand.lerp(darkBrand, 0.5);
      expect(mid.routeLine, Color.lerp(lightBrand.routeLine, darkBrand.routeLine, 0.5));
      final overridden = lightBrand.copyWith(routeLine: const Color(0xFF2563EB));
      expect(overridden.routeLine, const Color(0xFF2563EB));
      expect(overridden.heartRate, lightBrand.heartRate);
    });

    testWidgets('ChannelChartsSection applies harmonized GpxLabBrandColors in light and dark themes', (tester) async {
      const geometry = ActivityDisplayGeometry(
        routePoints: [],
        heartRateSeries: [
          ChartSample(distanceMeters: 0, elapsedSeconds: 0, value: 145),
          ChartSample(distanceMeters: 500, elapsedSeconds: 150, value: 162),
        ],
        elevationSeries: [
          ChartSample(distanceMeters: 0, elapsedSeconds: 0, value: 12),
          ChartSample(distanceMeters: 500, elapsedSeconds: 150, value: 28),
        ],
        paceSeries: [
          ChartSample(distanceMeters: 0, elapsedSeconds: 0, value: 300),
          ChartSample(distanceMeters: 500, elapsedSeconds: 150, value: 285),
        ],
        sourceTrackpointCount: 2,
      );

      for (final theme in [GpxLabTheme.light(), GpxLabTheme.dark()]) {
        final expected = theme.extension<GpxLabBrandColors>()!;
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: const Scaffold(
              body: SingleChildScrollView(
                child: ChannelChartsSection(geometry: geometry),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final hrIcon = tester.widget<Icon>(
          find.descendant(
            of: find.byKey(const Key('chart-heart-rate')),
            matching: find.byIcon(Icons.favorite_outline),
          ),
        );
        final eleIcon = tester.widget<Icon>(
          find.descendant(
            of: find.byKey(const Key('chart-elevation')),
            matching: find.byIcon(Icons.terrain_outlined),
          ),
        );
        final paceIcon = tester.widget<Icon>(
          find.descendant(
            of: find.byKey(const Key('chart-pace')),
            matching: find.byIcon(Icons.speed_outlined),
          ),
        );

        expect(hrIcon.color, expected.heartRate);
        expect(eleIcon.color, expected.elevation);
        expect(paceIcon.color, expected.pace);
      }
    });
  });

  group('GpxLabApp & GpxLabBrandHeader', () {
    testWidgets('GpxLabApp applies GPX Lab title, centralized theme, and brand header on Start screen', (tester) async {
      await tester.pumpWidget(
        const GpxLabApp(platformIoPort: _IdleFakePort()),
      );
      await tester.pumpAndSettle();

      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.title, 'GPX Lab');
      expect(app.theme?.colorScheme.primary, const Color(0xFF1D63ED));
      expect(app.darkTheme?.colorScheme.surface, const Color(0xFF0B1120));

      expect(find.byType(GpxLabBrandHeader), findsOneWidget);
      expect(find.byKey(const Key('brand-header')), findsOneWidget);
      expect(find.byKey(const Key('brand-logo-slot')), findsOneWidget);
      expect(find.byKey(const Key('brand-persona-slot')), findsOneWidget);
      expect(find.text('GPX Lab'), findsOneWidget);
    });

    testWidgets('GpxLabBrandHeader provides drop-in slots for custom logo and character/persona', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: GpxLabTheme.light(),
          home: const Scaffold(
            body: GpxLabBrandHeader(),
          ),
        ),
      );

      expect(find.byKey(const Key('brand-logo-placeholder')), findsOneWidget);
      expect(find.byKey(const Key('brand-persona-placeholder')), findsOneWidget);

      await tester.pumpWidget(
        MaterialApp(
          theme: GpxLabTheme.light(),
          home: const Scaffold(
            body: GpxLabBrandHeader(
              logo: SizedBox(
                key: Key('custom-brand-logo'),
                width: 56,
                height: 56,
              ),
              persona: SizedBox(
                key: Key('custom-brand-persona'),
                width: 48,
                height: 48,
              ),
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('custom-brand-logo')), findsOneWidget);
      expect(find.byKey(const Key('custom-brand-persona')), findsOneWidget);
      expect(find.byKey(const Key('brand-logo-placeholder')), findsNothing);
      expect(find.byKey(const Key('brand-persona-placeholder')), findsNothing);
      expect(find.text('GPX Lab'), findsOneWidget);
    });
  });
}
