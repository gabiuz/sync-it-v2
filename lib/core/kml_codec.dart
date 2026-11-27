import 'dart:convert';
import 'dart:typed_data';

import 'package:xml/xml.dart';

import 'models.dart';
import 'summary_calculator.dart';
import 'xml_track_codec_helpers.dart';

/// Pure-Dart KML 2.2 (`<gx:Track>` and timestamped `<Placemark>`) parser and
/// serializer.
class KmlCodec {
  const KmlCodec._();

  static const _kmlNamespace = 'http://www.opengis.net/kml/2.2';
  static const _gxNamespace = 'http://www.google.com/kml/ext/2.2';

  static int? _readHeartRate(Trackpoint pt) => pt.heartRateBpm;
  static int? _readCadence(Trackpoint pt) => pt.cadenceRpm;
  static int? _readPower(Trackpoint pt) => pt.powerWatts;
  static int? _readTemperature(Trackpoint pt) => pt.temperatureCelsius;

  static const _sensorSpecs = <_KmlSensorChannelSpec>[
    _KmlSensorChannelSpec(
      channel: Channel.heartRate,
      fieldName: 'heartrate',
      displayName: 'Heart Rate',
      aliases: {'heartrate', 'heart_rate', 'hr', 'bpm', 'heart rate'},
      extractValue: _readHeartRate,
    ),
    _KmlSensorChannelSpec(
      channel: Channel.cadence,
      fieldName: 'cadence',
      displayName: 'Cadence',
      aliases: {
        'cadence',
        'cad',
        'runcadence',
        'run_cadence',
        'rpm',
        'spm',
        'step_rate',
      },
      extractValue: _readCadence,
    ),
    _KmlSensorChannelSpec(
      channel: Channel.power,
      fieldName: 'power',
      displayName: 'Power',
      aliases: {'power', 'watts', 'watt'},
      extractValue: _readPower,
    ),
    _KmlSensorChannelSpec(
      channel: Channel.temperature,
      fieldName: 'temperature',
      displayName: 'Temperature',
      aliases: {'temperature', 'temp', 'atemp', 'airtemp', 'air_temp'},
      extractValue: _readTemperature,
    ),
  ];

  static const _metadataKeys = <String>{
    'sport',
    'sporttype',
    'activitytype',
    'creator',
    'device',
    'deviceinfo',
  };

  static ParseResult parse(Uint8List bytes, {String? fileName}) {
    final document = XmlTrackCodecHelpers.parseXmlDocument(
      bytes,
      formatLabel: 'KML',
      expectedRootLocalName: 'kml',
    );
    final root = document.rootElement;

    final documentEl =
        XmlTrackCodecHelpers.firstChildByLocalName(root, 'Document');
    final placemarks = root.descendants
        .whereType<XmlElement>()
        .where((e) => e.localName == 'Placemark')
        .toList();
    final firstPlacemark = placemarks.isNotEmpty ? placemarks.first : null;

    final rawTitle = (documentEl != null
            ? XmlTrackCodecHelpers.childText(documentEl, 'name')
            : null) ??
        (firstPlacemark != null
            ? XmlTrackCodecHelpers.childText(firstPlacemark, 'name')
            : null) ??
        XmlTrackCodecHelpers.fallbackTitle(fileName);
    final rawDesc = (documentEl != null
            ? XmlTrackCodecHelpers.childText(documentEl, 'description')
            : null) ??
        (firstPlacemark != null
            ? XmlTrackCodecHelpers.childText(firstPlacemark, 'description')
            : null) ??
        '';

    final docMeta = _extractDocumentMetadata(documentEl, firstPlacemark);
    final sportType = docMeta.sportType;
    final deviceInfo = docMeta.deviceInfo;

    final trackEls = root.descendants
        .whereType<XmlElement>()
        .where((e) => e.localName == 'Track')
        .toList();
    final hasGxTrack = trackEls.isNotEmpty;
    final hasLineString = root.descendants
        .whereType<XmlElement>()
        .any((e) => e.localName == 'LineString');

    final rawPoints = <Trackpoint>[];
    var trackMissingTimestampCount = 0;
    var pointMissingTimestampCount = 0;
    var zeroHrCount = 0;
    var unsupportedExtensionCount = 0;

    for (final trackEl in trackEls) {
      final whenEls =
          XmlTrackCodecHelpers.childrenByLocalName(trackEl, 'when').toList();
      final coordEls =
          XmlTrackCodecHelpers.childrenByLocalName(trackEl, 'coord').toList();

      if (whenEls.isEmpty && coordEls.isNotEmpty) {
        trackMissingTimestampCount += coordEls.length;
        continue;
      }
      if (coordEls.length > whenEls.length) {
        trackMissingTimestampCount += coordEls.length - whenEls.length;
      }

      final arrays = _extractSimpleArrayData(trackEl);
      if (arrays.hasUnsupported && whenEls.isNotEmpty) {
        unsupportedExtensionCount += whenEls.length;
      }

      final heartRates = arrays.valuesByChannel[Channel.heartRate] ?? const [];
      final cadences = arrays.valuesByChannel[Channel.cadence] ?? const [];
      final powers = arrays.valuesByChannel[Channel.power] ?? const [];
      final temperatures =
          arrays.valuesByChannel[Channel.temperature] ?? const [];

      for (var i = 0; i < whenEls.length; i++) {
        final timeText = whenEls[i].innerText.trim();
        if (timeText.isEmpty) {
          trackMissingTimestampCount++;
          continue;
        }
        final timestamp = DateTime.tryParse(timeText)?.toUtc();
        if (timestamp == null) {
          throw ActivityParseException(
            'Invalid trackpoint timestamp "$timeText". KML timestamps must be ISO-8601 date/time values.',
          );
        }

        double? lat;
        double? lon;
        double? ele;
        if (i < coordEls.length) {
          (lat, lon, ele) = _parseGxCoord(coordEls[i].innerText);
        }

        var hr = i < heartRates.length ? heartRates[i] : null;
        if (hr != null && hr <= 0) {
          hr = null;
          zeroHrCount++;
        }
        final cad = i < cadences.length ? cadences[i] : null;
        final pwr = i < powers.length ? powers[i] : null;
        final temp = i < temperatures.length ? temperatures[i] : null;

        rawPoints.add(
          Trackpoint(
            timestamp: timestamp,
            latitude: lat,
            longitude: lon,
            elevationMeters: ele,
            heartRateBpm: hr,
            cadenceRpm: cad,
            powerWatts: pwr,
            temperatureCelsius: temp,
          ),
        );
      }
    }

    // Parse timestamped <Placemark> points (skipping placemarks that already
    // host a <gx:Track> so we never double-count).
    for (final placemark in placemarks) {
      final containsTrack = placemark.descendants
          .whereType<XmlElement>()
          .any((e) => e.localName == 'Track');
      if (containsTrack) continue;

      XmlElement? pointEl;
      for (final node in placemark.descendants.whereType<XmlElement>()) {
        if (node.localName == 'Point') {
          pointEl = node;
          break;
        }
      }
      if (pointEl == null) continue;

      final timeText = _extractPlacemarkTimestamp(placemark);
      if (timeText == null || timeText.isEmpty) {
        pointMissingTimestampCount++;
        continue;
      }
      final timestamp = DateTime.tryParse(timeText)?.toUtc();
      if (timestamp == null) {
        throw ActivityParseException(
          'Invalid placemark timestamp "$timeText". KML timestamps must be ISO-8601 date/time values.',
        );
      }

      final coordsText = XmlTrackCodecHelpers.childText(pointEl, 'coordinates');
      final (lat, lon, ele) = coordsText != null
          ? _parsePointCoordinates(coordsText)
          : (null, null, null);

      final ext = _extractPlacemarkExtensions(placemark);
      if (ext.droppedZeroHr) zeroHrCount++;
      if (ext.hasUnsupportedExtensions) unsupportedExtensionCount++;

      rawPoints.add(
        Trackpoint(
          timestamp: timestamp,
          latitude: lat,
          longitude: lon,
          elevationMeters: ele,
          heartRateBpm: ext.valuesByChannel[Channel.heartRate],
          cadenceRpm: ext.valuesByChannel[Channel.cadence],
          powerWatts: ext.valuesByChannel[Channel.power],
          temperatureCelsius: ext.valuesByChannel[Channel.temperature],
        ),
      );
    }

    if (trackMissingTimestampCount > 0) {
      if (rawPoints.isEmpty) {
        throw const ActivityParseException(
          'This KML file has <gx:Track> coordinates without <when> timestamps (likely a planned route). GPX Lab requires timestamped trackpoints.',
        );
      }
      throw const ActivityParseException(
        'Some trackpoints in this KML <gx:Track> are missing <when> timestamps. All trackpoints must have valid timestamps.',
      );
    }

    if (rawPoints.isEmpty) {
      if (hasLineString) {
        throw const ActivityParseException(
          'This KML file contains untimestamped <LineString> route geometry (likely a planned route). GPX Lab requires timestamped <gx:Track> or timestamped placemark data.',
        );
      }
      if (pointMissingTimestampCount > 0) {
        throw const ActivityParseException(
          'This KML file has placemarks without <TimeStamp> timestamps (likely a planned route). GPX Lab requires timestamped trackpoints.',
        );
      }
      throw const ActivityParseException(
        'This KML file contains zero timestamped trackpoints. Select a recorded activity KML file.',
      );
    }

    if (!hasGxTrack && pointMissingTimestampCount > 0) {
      throw const ActivityParseException(
        'Some placemarks in this KML file are missing <TimeStamp> timestamps. All trackpoints must have valid timestamps.',
      );
    }

    final diagnostics = <Diagnostic>[];
    final normalizedPoints = XmlTrackCodecHelpers.normalizeTrackpoints(
      rawPoints,
      diagnostics: diagnostics,
      zeroHrCount: zeroHrCount,
      unsupportedExtensionCount: unsupportedExtensionCount,
    );
    final channels =
        XmlTrackCodecHelpers.detectAvailableChannels(normalizedPoints);

    final activity = Activity(
      title: rawTitle,
      description: rawDesc,
      sportType: sportType,
      trackpoints: normalizedPoints,
      laps: [
        Lap(
          startTime: normalizedPoints.first.timestamp,
          endTime: normalizedPoints.last.timestamp,
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

  static ExportResult export(Activity activity, ActivityEdit edit) {
    if (edit.strippedChannels.contains(StrippableChannel.gps)) {
      throw StateError(
        'KML export requires GPS Position. Choose FIT or TCX for a mapless Export File.',
      );
    }
    final updated = SummaryCalculator.applyEdits(activity, edit);
    if (!updated.availableChannels.contains(Channel.gps)) {
      throw StateError(
        'KML export requires GPS coordinates. Choose FIT or TCX for a mapless Export File.',
      );
    }

    final activeSpecs = _sensorSpecs
        .where((spec) => updated.availableChannels.contains(spec.channel))
        .toList();
    final hasTelemetryArrays = activeSpecs.isNotEmpty;
    final hasElevation =
        updated.trackpoints.any((pt) => pt.elevationMeters != null);

    final builder = XmlBuilder();
    builder.processing('xml', 'version="1.0" encoding="UTF-8"');
    builder.element(
      'kml',
      attributes: {
        'xmlns': _kmlNamespace,
        'xmlns:gx': _gxNamespace,
      },
      nest: () {
        builder.element('Document', nest: () {
          builder.element('name', nest: updated.title);
          if (updated.description.isNotEmpty) {
            builder.element('description', nest: updated.description);
          }

          builder.element('ExtendedData', nest: () {
            builder.element(
              'Data',
              attributes: {'name': 'sport'},
              nest: () {
                builder.element('value', nest: updated.sportType.gpxName);
              },
            );
            if (updated.deviceInfo != null &&
                updated.deviceInfo!.trim().isNotEmpty) {
              builder.element(
                'Data',
                attributes: {'name': 'creator'},
                nest: () {
                  builder.element('value', nest: updated.deviceInfo!.trim());
                },
              );
            }
          });

          if (hasTelemetryArrays) {
            builder.element(
              'Schema',
              attributes: {'id': 'gpx_lab_schema'},
              nest: () {
                for (final spec in activeSpecs) {
                  _writeSimpleArrayField(
                    builder,
                    name: spec.fieldName,
                    displayName: spec.displayName,
                  );
                }
              },
            );
          }

          builder.element('Placemark', nest: () {
            builder.element('name', nest: updated.title);
            if (updated.description.isNotEmpty) {
              builder.element('description', nest: updated.description);
            }
            builder.element('gx:Track', nest: () {
              builder.element(
                'altitudeMode',
                nest: hasElevation ? 'absolute' : 'clampToGround',
              );
              for (final pt in updated.trackpoints) {
                builder.element(
                  'when',
                  nest: pt.timestamp.toUtc().toIso8601String(),
                );
              }
              for (final pt in updated.trackpoints) {
                if (pt.latitude != null && pt.longitude != null) {
                  final lonStr = pt.longitude!.toStringAsFixed(6);
                  final latStr = pt.latitude!.toStringAsFixed(6);
                  final coordText = pt.elevationMeters != null
                      ? '$lonStr $latStr ${pt.elevationMeters!.toStringAsFixed(1)}'
                      : '$lonStr $latStr';
                  builder.element('gx:coord', nest: coordText);
                } else {
                  builder.element('gx:coord');
                }
              }

              if (hasTelemetryArrays) {
                builder.element('ExtendedData', nest: () {
                  builder.element(
                    'SchemaData',
                    attributes: {'schemaUrl': '#gpx_lab_schema'},
                    nest: () {
                      for (final spec in activeSpecs) {
                        _writeSimpleArrayData(
                          builder,
                          name: spec.fieldName,
                          values:
                              updated.trackpoints.map(spec.extractValue).toList(),
                        );
                      }
                    },
                  );
                });
              }
            });
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

  static void _writeSimpleArrayField(
    XmlBuilder builder, {
    required String name,
    required String displayName,
  }) {
    builder.element(
      'gx:SimpleArrayField',
      attributes: {'name': name, 'type': 'int'},
      nest: () {
        builder.element('displayName', nest: displayName);
      },
    );
  }

  static void _writeSimpleArrayData(
    XmlBuilder builder, {
    required String name,
    required List<int?> values,
  }) {
    builder.element(
      'gx:SimpleArrayData',
      attributes: {'name': name},
      nest: () {
        for (final v in values) {
          if (v != null) {
            builder.element('gx:value', nest: v.toString());
          } else {
            builder.element('gx:value');
          }
        }
      },
    );
  }

  static (double?, double?, double?) _parseGxCoord(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return (null, null, null);
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length < 2) return (null, null, null);
    return _validateLatLonEle(
      latRaw: parts[1],
      lonRaw: parts[0],
      eleRaw: parts.length >= 3 ? parts[2] : null,
    );
  }

  static (double?, double?, double?) _parsePointCoordinates(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return (null, null, null);
    final firstTuple = trimmed.split(RegExp(r'\s+')).first;
    final parts = firstTuple.split(',');
    if (parts.length < 2) return (null, null, null);
    return _validateLatLonEle(
      latRaw: parts[1].trim(),
      lonRaw: parts[0].trim(),
      eleRaw: parts.length >= 3 ? parts[2].trim() : null,
    );
  }

  static (double?, double?, double?) _validateLatLonEle({
    required String latRaw,
    required String lonRaw,
    String? eleRaw,
  }) {
    final lat = double.tryParse(latRaw);
    final lon = double.tryParse(lonRaw);
    final validGps = lat != null &&
        lon != null &&
        lat.isFinite &&
        lon.isFinite &&
        lat >= -90.0 &&
        lat <= 90.0 &&
        lon >= -180.0 &&
        lon <= 180.0;
    final ele = eleRaw != null ? double.tryParse(eleRaw) : null;
    final validEle = ele != null && ele.isFinite ? ele : null;
    return validGps ? (lat, lon, validEle) : (null, null, validEle);
  }

  static _KmlSensorChannelSpec? _findSensorSpec(String rawName) {
    for (final spec in _sensorSpecs) {
      if (spec.aliases.contains(rawName)) return spec;
    }
    return null;
  }

  static _SimpleArrayDataResult _extractSimpleArrayData(XmlElement trackEl) {
    final extContainers = <XmlElement>[
      ...XmlTrackCodecHelpers.childrenByLocalName(trackEl, 'ExtendedData'),
    ];
    if (extContainers.isEmpty) {
      final parent = trackEl.parentElement;
      if (parent != null && parent.localName == 'Placemark') {
        extContainers.addAll(
          XmlTrackCodecHelpers.childrenByLocalName(parent, 'ExtendedData'),
        );
      }
    }
    if (extContainers.isEmpty) {
      return const _SimpleArrayDataResult();
    }

    final valuesByChannel = <Channel, List<int?>>{};
    var hasUnsupported = false;

    for (final ext in extContainers) {
      for (final node in ext.descendants.whereType<XmlElement>()) {
        if (node.localName.toLowerCase() != 'simplearraydata') continue;
        final name = (node.getAttribute('name') ?? '').trim().toLowerCase();
        final values = node.childElements
            .where((c) => c.localName.toLowerCase() == 'value')
            .map((v) => _parseOptionalInt(v.innerText))
            .toList();

        final spec = _findSensorSpec(name);
        if (spec != null) {
          valuesByChannel.putIfAbsent(spec.channel, () => values);
        } else {
          hasUnsupported = true;
        }
      }
    }

    return _SimpleArrayDataResult(
      valuesByChannel: valuesByChannel,
      hasUnsupported: hasUnsupported,
    );
  }

  static String? _extractPlacemarkTimestamp(XmlElement placemark) {
    final timeStampEl =
        XmlTrackCodecHelpers.firstChildByLocalName(placemark, 'TimeStamp');
    if (timeStampEl != null) {
      final when = XmlTrackCodecHelpers.childText(timeStampEl, 'when');
      if (when != null) return when;
    }
    final directWhen = XmlTrackCodecHelpers.childText(placemark, 'when');
    if (directWhen != null) return directWhen;
    final timeSpanEl =
        XmlTrackCodecHelpers.firstChildByLocalName(placemark, 'TimeSpan');
    if (timeSpanEl != null) {
      return XmlTrackCodecHelpers.childText(timeSpanEl, 'begin');
    }
    return null;
  }

  static _KmlDocumentMetadata _extractDocumentMetadata(
    XmlElement? documentEl,
    XmlElement? firstPlacemark,
  ) {
    SportType? sportType;
    String? deviceInfo;

    for (final container in [documentEl, firstPlacemark]) {
      if (container == null) continue;
      final ext =
          XmlTrackCodecHelpers.firstChildByLocalName(container, 'ExtendedData');
      if (ext == null) continue;
      for (final entry in _readNamedDataPairs(ext)) {
        final key = entry.key;
        if (key == 'sport' || key == 'sporttype' || key == 'activitytype') {
          sportType ??= SportType.fromGpxType(entry.value);
        } else if (key == 'creator' ||
            key == 'device' ||
            key == 'deviceinfo') {
          if (entry.value.isNotEmpty) {
            deviceInfo ??= entry.value;
          }
        }
      }
    }

    return _KmlDocumentMetadata(
      sportType: sportType ?? SportType.other,
      deviceInfo: deviceInfo,
    );
  }

  static _KmlPlacemarkExtensionData _extractPlacemarkExtensions(
    XmlElement placemark,
  ) {
    final ext =
        XmlTrackCodecHelpers.firstChildByLocalName(placemark, 'ExtendedData');
    if (ext == null) return const _KmlPlacemarkExtensionData();

    final valuesByChannel = <Channel, int>{};
    var droppedZeroHr = false;
    var hasUnsupported = false;

    for (final entry in _readNamedDataPairs(ext)) {
      final key = entry.key;
      if (_metadataKeys.contains(key)) continue;

      final spec = _findSensorSpec(key);
      if (spec == null) {
        hasUnsupported = true;
        continue;
      }

      final parsed = _parseOptionalInt(entry.value);
      if (parsed == null) continue;
      if (spec.channel == Channel.heartRate && parsed <= 0) {
        droppedZeroHr = true;
      } else {
        valuesByChannel.putIfAbsent(spec.channel, () => parsed);
      }
    }

    return _KmlPlacemarkExtensionData(
      valuesByChannel: valuesByChannel,
      droppedZeroHr: droppedZeroHr,
      hasUnsupportedExtensions: hasUnsupported,
    );
  }

  static List<MapEntry<String, String>> _readNamedDataPairs(XmlElement ext) {
    final pairs = <MapEntry<String, String>>[];
    for (final node in ext.descendants.whereType<XmlElement>()) {
      final local = node.localName.toLowerCase();
      if (local == 'data') {
        final name = (node.getAttribute('name') ?? '').trim().toLowerCase();
        final value = XmlTrackCodecHelpers.childText(node, 'value') ?? '';
        if (name.isNotEmpty && value.isNotEmpty) {
          pairs.add(MapEntry(name, value));
        }
      } else if (local == 'simpledata') {
        final name = (node.getAttribute('name') ?? '').trim().toLowerCase();
        final value = node.innerText.trim();
        if (name.isNotEmpty && value.isNotEmpty) {
          pairs.add(MapEntry(name, value));
        }
      }
    }
    return pairs;
  }

  static int? _parseOptionalInt(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final asInt = int.tryParse(trimmed);
    if (asInt != null) return asInt;
    final asDouble = double.tryParse(trimmed);
    if (asDouble != null && asDouble.isFinite) return asDouble.round();
    return null;
  }
}

class _KmlSensorChannelSpec {
  const _KmlSensorChannelSpec({
    required this.channel,
    required this.fieldName,
    required this.displayName,
    required this.aliases,
    required this.extractValue,
  });

  final Channel channel;
  final String fieldName;
  final String displayName;
  final Set<String> aliases;
  final int? Function(Trackpoint pt) extractValue;
}

class _SimpleArrayDataResult {
  const _SimpleArrayDataResult({
    this.valuesByChannel = const {},
    this.hasUnsupported = false,
  });

  final Map<Channel, List<int?>> valuesByChannel;
  final bool hasUnsupported;
}

class _KmlDocumentMetadata {
  const _KmlDocumentMetadata({
    required this.sportType,
    this.deviceInfo,
  });

  final SportType sportType;
  final String? deviceInfo;
}

class _KmlPlacemarkExtensionData {
  const _KmlPlacemarkExtensionData({
    this.valuesByChannel = const {},
    this.droppedZeroHr = false,
    this.hasUnsupportedExtensions = false,
  });

  final Map<Channel, int> valuesByChannel;
  final bool droppedZeroHr;
  final bool hasUnsupportedExtensions;
}
