import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../core/core_engine.dart';

/// Displays an interactive OpenStreetMap route map when online, an interactive
/// vector-canvas polyline fallback when offline, or a clean mapless state when
/// the Activity has no GPS Trackpoints.
class RouteMapCard extends StatelessWidget {
  const RouteMapCard({
    super.key,
    required this.routePoints,
    required this.isOnline,
  });

  final List<GeoPoint> routePoints;
  final bool? isOnline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    if (routePoints.isEmpty) {
      return Card(
        key: const Key('mapless-indoor-state'),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: colors.surfaceContainerHighest,
                foregroundColor: colors.onSurfaceVariant,
                child: const Icon(Icons.location_off_outlined),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'No GPS Route Data',
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Indoor or mapless Activity — GPS Trackpoints are not available.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: 240,
        child: isOnline == null
            ? const Center(child: CircularProgressIndicator())
            : isOnline!
                ? _buildOnlineMap(context, colors)
                : _buildOfflineCanvas(context, colors),
      ),
    );
  }

  Widget _buildOnlineMap(BuildContext context, ColorScheme colors) {
    final latLngs = [
      for (final pt in routePoints) LatLng(pt.latitude, pt.longitude),
    ];
    final bounds = LatLngBounds.fromPoints(latLngs);
    final hasArea =
        (bounds.north - bounds.south).abs() > 1e-6 ||
        (bounds.east - bounds.west).abs() > 1e-6;

    final options = hasArea
        ? MapOptions(
            initialCameraFit: CameraFit.bounds(
              bounds: bounds,
              padding: const EdgeInsets.all(28),
            ),
          )
        : MapOptions(
            initialCenter: latLngs.first,
            initialZoom: 15,
          );

    return Stack(
      children: [
        FlutterMap(
          key: const Key('osm-route-map'),
          options: options,
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.syncit.app',
              tileProvider: NetworkTileProvider(
                cachingProvider: const DisabledMapCachingProvider(),
              ),
            ),
            PolylineLayer(
              polylines: [
                Polyline(
                  points: latLngs,
                  strokeWidth: 4.0,
                  color: colors.primary,
                ),
              ],
            ),
            MarkerLayer(
              markers: [
                _endpointMarker(latLngs.first, Colors.green),
                if (latLngs.length > 1)
                  _endpointMarker(latLngs.last, colors.error),
              ],
            ),
          ],
        ),
        Positioned(
          right: 8,
          bottom: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: colors.surface.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '© OpenStreetMap',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        ),
      ],
    );
  }

  Marker _endpointMarker(LatLng point, Color color) {
    return Marker(
      point: point,
      width: 14,
      height: 14,
      child: Container(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
        ),
      ),
    );
  }

  Widget _buildOfflineCanvas(BuildContext context, ColorScheme colors) {
    return Stack(
      children: [
        Container(
          color: colors.surfaceContainerHighest,
          width: double.infinity,
          height: double.infinity,
          child: InteractiveViewer(
            minScale: 1.0,
            maxScale: 6.0,
            child: CustomPaint(
              key: const Key('offline-route-canvas'),
              painter: _OfflineRoutePainter(
                points: routePoints,
                lineColor: colors.primary,
                gridColor: colors.outlineVariant.withValues(alpha: 0.45),
                startColor: Colors.green,
                endColor: colors.error,
              ),
              size: Size.infinite,
            ),
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: colors.surface.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_off, size: 14, color: colors.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  'Offline Vector Map',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _OfflineRoutePainter extends CustomPainter {
  const _OfflineRoutePainter({
    required this.points,
    required this.lineColor,
    required this.gridColor,
    required this.startColor,
    required this.endColor,
  });

  final List<GeoPoint> points;
  final Color lineColor;
  final Color gridColor;
  final Color startColor;
  final Color endColor;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1.0;

    const gridSteps = 5;
    for (var i = 1; i < gridSteps; i++) {
      final dx = size.width * (i / gridSteps);
      final dy = size.height * (i / gridSteps);
      canvas.drawLine(Offset(dx, 0), Offset(dx, size.height), gridPaint);
      canvas.drawLine(Offset(0, dy), Offset(size.width, dy), gridPaint);
    }

    if (points.isEmpty) return;

    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLon = points.first.longitude;
    var maxLon = points.first.longitude;

    for (final pt in points) {
      if (pt.latitude < minLat) minLat = pt.latitude;
      if (pt.latitude > maxLat) maxLat = pt.latitude;
      if (pt.longitude < minLon) minLon = pt.longitude;
      if (pt.longitude > maxLon) maxLon = pt.longitude;
    }

    final midLatRad = ((minLat + maxLat) / 2.0) * (math.pi / 180.0);
    final cosLat = math.cos(midLatRad).abs().clamp(0.1, 1.0);

    final rawSpanX = (maxLon - minLon) * cosLat;
    final rawSpanY = maxLat - minLat;

    const padding = 28.0;
    final drawW = (size.width - padding * 2).clamp(1.0, double.infinity);
    final drawH = (size.height - padding * 2).clamp(1.0, double.infinity);

    Offset project(GeoPoint pt) {
      if (rawSpanX < 1e-9 && rawSpanY < 1e-9) {
        return Offset(size.width / 2, size.height / 2);
      }
      final scale = math.min(
        rawSpanX > 1e-9 ? drawW / rawSpanX : double.infinity,
        rawSpanY > 1e-9 ? drawH / rawSpanY : double.infinity,
      );
      final projectedW = rawSpanX * scale;
      final projectedH = rawSpanY * scale;
      final offsetX = (size.width - projectedW) / 2.0;
      final offsetY = (size.height - projectedH) / 2.0;

      final x = offsetX + ((pt.longitude - minLon) * cosLat) * scale;
      final y = offsetY + (maxLat - pt.latitude) * scale;
      return Offset(x, y);
    }

    final offsets = [for (final pt in points) project(pt)];

    if (offsets.length > 1) {
      final path = Path()..moveTo(offsets.first.dx, offsets.first.dy);
      for (var i = 1; i < offsets.length; i++) {
        path.lineTo(offsets[i].dx, offsets[i].dy);
      }
      final routePaint = Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(path, routePaint);
    }

    _drawEndpoint(canvas, offsets.first, startColor);
    if (offsets.length > 1) {
      _drawEndpoint(canvas, offsets.last, endColor);
    }
  }

  void _drawEndpoint(Canvas canvas, Offset center, Color color) {
    canvas.drawCircle(center, 6, Paint()..color = Colors.white);
    canvas.drawCircle(center, 4.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _OfflineRoutePainter oldDelegate) {
    return oldDelegate.points != points || oldDelegate.lineColor != lineColor;
  }
}
