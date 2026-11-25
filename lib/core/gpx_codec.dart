import 'dart:convert';
import 'dart:typed_data';

import 'package:xml/xml.dart';

import 'models.dart';
import 'summary_calculator.dart';

/// Pure-Dart GPX 1.1 parser and serializer.
class GpxCodec {
  const GpxCodec._();

  static const _gpxNamespace = 'http://www.topografix.com/GPX/1/1';
  static const _tpxNamespace =
      'http://www.garmin.com/xmlschemas/TrackPointExtension/v1';

  static const _knownExtensionTags = <String>{
    'trackpointextension',
    'hr',
    'heartrate',
    'cad',
    'cadence',
    'power',
    'watts',
  };

  static ParseResult parse(Uint8List bytes, {String? fileName}) {
    if (bytes.isEmpty) {
      throw const ActivityParseException(
        'The selected GPX file is empty. Choose a valid GPX activity file.',
      );
    }

    final String xmlString;
    try {
      xmlString = utf8.decode(bytes);
    } on FormatException {
      throw const ActivityParseException(
        'Could not read the file as UTF-8 text. Ensure the file is a valid GPX XML file.',
      );
    }

    final XmlDocument document;
    try {
      document = XmlDocument.parse(xmlString);
    } on XmlException catch (e) {
      throw ActivityParseException(
        'Corrupted GPX XML file: ${e.message}. Export a fresh GPX file from your watch or app and try again.',
      );
    }

    final root = document.rootElement;
    if (root.localName != 'gpx') {
      throw ActivityParseException(
        'Expected a <gpx> root element, found <${root.localName}>. Select a valid GPX file.',
      );
    }

    final metadata = _firstChildByLocalName(root, 'metadata');
    final tracks = _childrenByLocalName(root, 'trk').toList();
    if (tracks.isEmpty) {
      throw const ActivityParseException(
        'This GPX file contains no <trk> track data. Route-only or empty GPX files cannot be imported as an activity.',
      );
    }

    final firstTrack = tracks.first;
    final rawTitle = _childText(firstTrack, 'name') ??
        (metadata != null ? _childText(metadata, 'name') : null) ??
        _fallbackTitle(fileName);
    final rawDesc = _childText(firstTrack, 'desc') ??
        (metadata != null ? _childText(metadata, 'desc') : null) ??
        '';
    final rawType = _childText(firstTrack, 'type');
    final sportType = SportType.fromGpxType(rawType);
    final rawCreator = root.getAttribute('creator')?.trim();
    final deviceInfo =
        (rawCreator != null && rawCreator.isNotEmpty) ? rawCreator : null;

    double? recoveredTotalDistance;
    for (final trk in tracks) {
      final trkExt = _firstChildByLocalName(trk, 'extensions');
      if (trkExt == null) continue;
      for (final node in trkExt.descendants.whereType<XmlElement>()) {
        if (node.localName.toLowerCase() == 'totaldistance') {
          final dist = double.tryParse(node.innerText.trim());
          if (dist != null && dist.isFinite && dist > 0) {
            recoveredTotalDistance = (recoveredTotalDistance ?? 0.0) + dist;
            break;
          }
        }
      }
    }

    final rawPoints = <Trackpoint>[];
    var missingTimestampCount = 0;
    var zeroHrCount = 0;
    var unsupportedExtensionCount = 0;

    for (final trk in tracks) {
      for (final seg in _childrenByLocalName(trk, 'trkseg')) {
        for (final trkpt in _childrenByLocalName(seg, 'trkpt')) {
          final timeText = _childText(trkpt, 'time');
          if (timeText == null || timeText.trim().isEmpty) {
            missingTimestampCount++;
            continue;
          }
          final timestamp = DateTime.tryParse(timeText.trim())?.toUtc();
          if (timestamp == null) {
            throw ActivityParseException(
              'Invalid trackpoint timestamp "$timeText". GPX timestamps must be ISO-8601 date/time values.',
            );
          }

          final lat = double.tryParse(trkpt.getAttribute('lat') ?? '');
          final lon = double.tryParse(trkpt.getAttribute('lon') ?? '');
          final eleText = _childText(trkpt, 'ele');
          final ele = eleText != null ? double.tryParse(eleText.trim()) : null;

          final ext = _extractExtensions(trkpt);
          if (ext.droppedZeroHr) zeroHrCount++;
          if (ext.hasUnsupportedExtensions) unsupportedExtensionCount++;

          rawPoints.add(
            Trackpoint(
              timestamp: timestamp,
              latitude: lat,
              longitude: lon,
              elevationMeters: ele,
              heartRateBpm: ext.heartRate,
              cadenceRpm: ext.cadence,
              powerWatts: ext.power,
            ),
          );
        }
      }
    }

    if (rawPoints.isEmpty) {
      if (missingTimestampCount > 0) {
        throw const ActivityParseException(
          'This GPX file has trackpoints without <time> timestamps (likely a planned route). GPX Lab requires timestamped trackpoints.',
        );
      }
      throw const ActivityParseException(
        'This GPX file contains zero trackpoints. Select a recorded activity GPX file.',
      );
    }

    if (missingTimestampCount > 0) {
      throw const ActivityParseException(
        'Some trackpoints in this GPX file are missing <time> timestamps. All trackpoints must have valid timestamps.',
      );
    }

    final diagnostics = <Diagnostic>[];

    // Check and normalize chronological order.
    var outOfOrderCount = 0;
    for (var i = 1; i < rawPoints.length; i++) {
      if (rawPoints[i].timestamp.isBefore(rawPoints[i - 1].timestamp)) {
        outOfOrderCount++;
      }
    }

    final indexed = rawPoints.asMap().entries.toList();
    if (outOfOrderCount > 0) {
      indexed.sort((a, b) {
        final cmp = a.value.timestamp.compareTo(b.value.timestamp);
        return cmp != 0 ? cmp : a.key.compareTo(b.key);
      });
      diagnostics.add(
        Diagnostic(
          code: DiagnosticCode.outOfOrderTrackpointsSorted,
          severity: DiagnosticSeverity.warning,
          message:
              'Sorted out-of-order trackpoints chronologically ($outOfOrderCount timestamp inversion${outOfOrderCount == 1 ? '' : 's'}).',
          count: outOfOrderCount,
        ),
      );
    }

    // Deduplicate adjacent identical timestamps, preferring later non-null values.
    final normalizedPoints = <Trackpoint>[];
    var duplicateCount = 0;
    for (final entry in indexed) {
      final pt = entry.value;
      if (normalizedPoints.isNotEmpty &&
          normalizedPoints.last.timestamp == pt.timestamp) {
        duplicateCount++;
        final prev = normalizedPoints.removeLast();
        normalizedPoints.add(_mergeDuplicateTrackpoints(prev, pt));
      } else {
        normalizedPoints.add(pt);
      }
    }

    if (duplicateCount > 0) {
      diagnostics.add(
        Diagnostic(
          code: DiagnosticCode.duplicateTimestampsNormalized,
          severity: DiagnosticSeverity.warning,
          message:
              'Merged $duplicateCount duplicate timestamp${duplicateCount == 1 ? '' : 's'}.',
          count: duplicateCount,
        ),
      );
    }

    if (zeroHrCount > 0) {
      diagnostics.add(
        Diagnostic(
          code: DiagnosticCode.zeroHeartRateDropped,
          severity: DiagnosticSeverity.info,
          message:
              'Cleared $zeroHrCount zero-bpm heart rate dropout${zeroHrCount == 1 ? '' : 's'}.',
          count: zeroHrCount,
        ),
      );
    }

    if (unsupportedExtensionCount > 0) {
      diagnostics.add(
        Diagnostic(
          code: DiagnosticCode.unsupportedExtensionsDropped,
          severity: DiagnosticSeverity.info,
          message:
              'Ignored unsupported vendor extensions on $unsupportedExtensionCount trackpoint${unsupportedExtensionCount == 1 ? '' : 's'}; they will not be included on export.',
          count: unsupportedExtensionCount,
        ),
      );
    }

    final finalPoints =
        (recoveredTotalDistance != null && recoveredTotalDistance > 0)
            ? SummaryCalculator.distributeDistanceRange(
                normalizedPoints,
                spanMeters: recoveredTotalDistance,
              )
            : normalizedPoints;

    final channels = <Channel>{};
    for (final pt in finalPoints) {
      if (pt.latitude != null && pt.longitude != null) {
        channels.add(Channel.gps);
      }
      if (pt.elevationMeters != null) channels.add(Channel.elevation);
      if (pt.cumulativeDistanceMeters != null) channels.add(Channel.distance);
      if (pt.heartRateBpm != null) channels.add(Channel.heartRate);
      if (pt.cadenceRpm != null) channels.add(Channel.cadence);
      if (pt.powerWatts != null) channels.add(Channel.power);
    }

    final activity = Activity(
      title: rawTitle,
      description: rawDesc,
      sportType: sportType,
      trackpoints: finalPoints,
      laps: [
        Lap(
          startTime: finalPoints.first.timestamp,
          endTime: finalPoints.last.timestamp,
          distanceMeters: finalPoints.last.cumulativeDistanceMeters,
        ),
      ],
      availableChannels: channels,
      deviceInfo: deviceInfo,
    );

    return ParseResult(
      activity: activity,
      summary: SummaryCalculator.compute(activity),
      diagnostics: diagnostics,
    );
  }

  static Trackpoint _mergeDuplicateTrackpoints(Trackpoint prev, Trackpoint next) {
    return Trackpoint(
      timestamp: next.timestamp,
      latitude: next.latitude ?? prev.latitude,
      longitude: next.longitude ?? prev.longitude,
      elevationMeters: next.elevationMeters ?? prev.elevationMeters,
      cumulativeDistanceMeters:
          next.cumulativeDistanceMeters ?? prev.cumulativeDistanceMeters,
      heartRateBpm: next.heartRateBpm ?? prev.heartRateBpm,
      cadenceRpm: next.cadenceRpm ?? prev.cadenceRpm,
      powerWatts: next.powerWatts ?? prev.powerWatts,
    );
  }

  static ExportResult export(Activity activity, ActivityEdit edit) {
    if (edit.strippedChannels.contains(StrippableChannel.gps)) {
      throw StateError(
        'GPX 1.1 export requires GPS Position. Choose FIT or TCX for a mapless Export File.',
      );
    }
    final updated = SummaryCalculator.applyEdits(activity, edit);
    if (!updated.availableChannels.contains(Channel.gps)) {
      throw StateError(
        'GPX 1.1 export requires GPS coordinates. Choose FIT or TCX for a mapless Export File.',
      );
    }

    final builder = XmlBuilder();
    builder.processing('xml', 'version="1.0" encoding="UTF-8"');
    builder.element(
      'gpx',
      attributes: {
        'version': '1.1',
        'creator': 'GPX Lab',
        'xmlns': _gpxNamespace,
        'xmlns:gpxtpx': _tpxNamespace,
      },
      nest: () {
        builder.element('metadata', nest: () {
          builder.element('name', nest: updated.title);
          if (updated.description.isNotEmpty) {
            builder.element('desc', nest: updated.description);
          }
          if (updated.trackpoints.isNotEmpty) {
            builder.element(
              'time',
              nest: updated.trackpoints.first.timestamp.toUtc().toIso8601String(),
            );
          }
        });

        builder.element('trk', nest: () {
          builder.element('name', nest: updated.title);
          if (updated.description.isNotEmpty) {
            builder.element('desc', nest: updated.description);
          }
          builder.element('type', nest: updated.sportType.gpxName);

          builder.element('trkseg', nest: () {
            for (final pt in updated.trackpoints) {
              final attrs = <String, String>{};
              if (pt.latitude != null && pt.longitude != null) {
                attrs['lat'] = pt.latitude!.toStringAsFixed(6);
                attrs['lon'] = pt.longitude!.toStringAsFixed(6);
              }
              builder.element('trkpt', attributes: attrs, nest: () {
                if (pt.elevationMeters != null) {
                  builder.element(
                    'ele',
                    nest: pt.elevationMeters!.toStringAsFixed(1),
                  );
                }
                builder.element(
                  'time',
                  nest: pt.timestamp.toUtc().toIso8601String(),
                );
                if (pt.heartRateBpm != null || pt.cadenceRpm != null) {
                  builder.element('extensions', nest: () {
                    builder.element('gpxtpx:TrackPointExtension', nest: () {
                      if (pt.heartRateBpm != null) {
                        builder.element(
                          'gpxtpx:hr',
                          nest: pt.heartRateBpm.toString(),
                        );
                      }
                      if (pt.cadenceRpm != null) {
                        builder.element(
                          'gpxtpx:cad',
                          nest: pt.cadenceRpm.toString(),
                        );
                      }
                    });
                  });
                }
              });
            }
          });
        });
      },
    );

    final xmlString = builder.buildDocument().toXmlString(pretty: true);
    final bytes = Uint8List.fromList(utf8.encode(xmlString));
    return ExportResult(
      bytes: bytes,
      activity: updated,
      summary: SummaryCalculator.compute(updated),
      diagnostics: const [],
    );
  }

  static _TrackpointExtensionData _extractExtensions(XmlElement trkpt) {
    final extensions = _firstChildByLocalName(trkpt, 'extensions');
    if (extensions == null) return const _TrackpointExtensionData();

    int? hr;
    int? cad;
    int? power;
    var droppedZeroHr = false;
    var hasUnsupported = false;

    for (final node in extensions.descendants.whereType<XmlElement>()) {
      final name = node.localName.toLowerCase();
      if (!_knownExtensionTags.contains(name)) {
        hasUnsupported = true;
        continue;
      }
      final value = int.tryParse(node.innerText.trim());
      if (value == null) continue;
      if (name == 'hr' || name == 'heartrate') {
        if (value <= 0) {
          droppedZeroHr = true;
        } else {
          hr ??= value;
        }
      } else if (name == 'cad' || name == 'cadence') {
        cad ??= value;
      } else if (name == 'power' || name == 'watts') {
        power ??= value;
      }
    }

    return _TrackpointExtensionData(
      heartRate: hr,
      cadence: cad,
      power: power,
      droppedZeroHr: droppedZeroHr,
      hasUnsupportedExtensions: hasUnsupported,
    );
  }

  static XmlElement? _firstChildByLocalName(XmlElement parent, String name) {
    for (final child in parent.childElements) {
      if (child.localName == name) return child;
    }
    return null;
  }

  static Iterable<XmlElement> _childrenByLocalName(
    XmlElement parent,
    String name,
  ) {
    return parent.childElements.where((c) => c.localName == name);
  }

  static String? _childText(XmlElement parent, String localName) {
    final child = _firstChildByLocalName(parent, localName);
    if (child == null) return null;
    final text = child.innerText.trim();
    return text.isEmpty ? null : text;
  }

  static String _fallbackTitle(String? fileName) {
    if (fileName == null || fileName.trim().isEmpty) return 'Untitled Activity';
    final dot = fileName.lastIndexOf('.');
    return dot > 0 ? fileName.substring(0, dot) : fileName;
  }
}

class _TrackpointExtensionData {
  const _TrackpointExtensionData({
    this.heartRate,
    this.cadence,
    this.power,
    this.droppedZeroHr = false,
    this.hasUnsupportedExtensions = false,
  });

  final int? heartRate;
  final int? cadence;
  final int? power;
  final bool droppedZeroHr;
  final bool hasUnsupportedExtensions;
}
