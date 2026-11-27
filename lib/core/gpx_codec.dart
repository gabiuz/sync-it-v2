import 'dart:convert';
import 'dart:typed_data';

import 'package:xml/xml.dart';

import 'models.dart';
import 'summary_calculator.dart';
import 'xml_track_codec_helpers.dart';

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
    final document = XmlTrackCodecHelpers.parseXmlDocument(
      bytes,
      formatLabel: 'GPX',
      expectedRootLocalName: 'gpx',
    );
    final root = document.rootElement;

    final metadata = XmlTrackCodecHelpers.firstChildByLocalName(root, 'metadata');
    final tracks = XmlTrackCodecHelpers.childrenByLocalName(root, 'trk').toList();
    if (tracks.isEmpty) {
      throw const ActivityParseException(
        'This GPX file contains no <trk> track data. Route-only or empty GPX files cannot be imported as an activity.',
      );
    }

    final firstTrack = tracks.first;
    final rawTitle = XmlTrackCodecHelpers.childText(firstTrack, 'name') ??
        (metadata != null
            ? XmlTrackCodecHelpers.childText(metadata, 'name')
            : null) ??
        XmlTrackCodecHelpers.fallbackTitle(fileName);
    final rawDesc = XmlTrackCodecHelpers.childText(firstTrack, 'desc') ??
        (metadata != null
            ? XmlTrackCodecHelpers.childText(metadata, 'desc')
            : null) ??
        '';
    final rawType = XmlTrackCodecHelpers.childText(firstTrack, 'type');
    final sportType = SportType.fromGpxType(rawType);
    final authorEl = metadata != null
        ? XmlTrackCodecHelpers.firstChildByLocalName(metadata, 'author')
        : null;
    final authorName =
        authorEl != null ? XmlTrackCodecHelpers.childText(authorEl, 'name') : null;
    final rootCreator = root.getAttribute('creator')?.trim();
    final deviceInfo = (authorName != null && authorName.isNotEmpty)
        ? authorName
        : (rootCreator != null && rootCreator.isNotEmpty ? rootCreator : null);

    final trackTotalDistances = <double?>[
      for (final trk in tracks) _extractTrackTotalDistance(trk),
    ];

    final rawPoints = <({int tag, Trackpoint point})>[];
    var missingTimestampCount = 0;
    var zeroHrCount = 0;
    var unsupportedExtensionCount = 0;

    for (var trackIndex = 0; trackIndex < tracks.length; trackIndex++) {
      final trk = tracks[trackIndex];
      for (final seg
          in XmlTrackCodecHelpers.childrenByLocalName(trk, 'trkseg')) {
        for (final trkpt
            in XmlTrackCodecHelpers.childrenByLocalName(seg, 'trkpt')) {
          final timeText = XmlTrackCodecHelpers.childText(trkpt, 'time');
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
          final eleText = XmlTrackCodecHelpers.childText(trkpt, 'ele');
          final ele = eleText != null ? double.tryParse(eleText.trim()) : null;

          final ext = _extractExtensions(trkpt);
          if (ext.droppedZeroHr) zeroHrCount++;
          if (ext.hasUnsupportedExtensions) unsupportedExtensionCount++;

          rawPoints.add((
            tag: trackIndex,
            point: Trackpoint(
              timestamp: timestamp,
              latitude: lat,
              longitude: lon,
              elevationMeters: ele,
              heartRateBpm: ext.heartRate,
              cadenceRpm: ext.cadence,
              powerWatts: ext.power,
            ),
          ));
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
    final normalizedEntries =
        XmlTrackCodecHelpers.normalizeTaggedTrackpoints<int>(
      rawPoints,
      diagnostics: diagnostics,
      zeroHrCount: zeroHrCount,
      unsupportedExtensionCount: unsupportedExtensionCount,
    );

    final hasTrackDistances = trackTotalDistances.any((d) => d != null);
    final finalPoints = hasTrackDistances
        ? _distributePerTrackDistances(normalizedEntries, trackTotalDistances)
        : [for (final entry in normalizedEntries) entry.point];

    final channels = XmlTrackCodecHelpers.detectAvailableChannels(finalPoints);

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

  static double? _extractTrackTotalDistance(XmlElement trk) {
    final trkExt = XmlTrackCodecHelpers.firstChildByLocalName(trk, 'extensions');
    if (trkExt == null) return null;
    for (final node in trkExt.descendants.whereType<XmlElement>()) {
      if (node.localName.toLowerCase() == 'totaldistance') {
        final dist = double.tryParse(node.innerText.trim());
        if (dist != null && dist.isFinite && dist > 0) {
          return dist;
        }
      }
    }
    return null;
  }

  static List<Trackpoint> _distributePerTrackDistances(
    List<({int tag, Trackpoint point})> entries,
    List<double?> trackTotalDistances,
  ) {
    final result = <Trackpoint>[];
    final usedTracks = <int>{};
    var runningDist = 0.0;
    Trackpoint? prevPoint;
    var i = 0;

    while (i < entries.length) {
      final trackIndex = entries[i].tag;
      final groupPoints = <Trackpoint>[];
      while (i < entries.length && entries[i].tag == trackIndex) {
        groupPoints.add(entries[i].point);
        i++;
      }

      final span =
          usedTracks.add(trackIndex) ? trackTotalDistances[trackIndex] : null;
      final scaled = SummaryCalculator.distributeDistanceRange(
        groupPoints,
        spanMeters: span,
        startDistanceMeters: runningDist,
        precedingPoint: prevPoint,
      );
      result.addAll(scaled);
      runningDist = scaled.last.cumulativeDistanceMeters ?? runningDist;
      prevPoint = groupPoints.last;
    }

    return result;
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
    final extensions =
        XmlTrackCodecHelpers.firstChildByLocalName(trkpt, 'extensions');
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
