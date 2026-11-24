import 'dart:convert';
import 'dart:typed_data';

import 'package:xml/xml.dart';

import 'models.dart';
import 'summary_calculator.dart';

/// Pure-Dart KML 2.2 (`<gx:Track>` and timestamped `<Placemark>`) parser and
/// serializer.
class KmlCodec {
  const KmlCodec._();

  static const _kmlNamespace = 'http://www.opengis.net/kml/2.2';
  static const _gxNamespace = 'http://www.google.com/kml/ext/2.2';

  static const _hrAliases = <String>{
    'heartrate',
    'heart_rate',
    'hr',
    'bpm',
    'heart rate',
  };
  static const _cadenceAliases = <String>{
    'cadence',
    'cad',
    'runcadence',
    'run_cadence',
    'rpm',
    'spm',
    'step_rate',
  };
  static const _powerAliases = <String>{
    'power',
    'watts',
    'watt',
  };
  static const _tempAliases = <String>{
    'temperature',
    'temp',
    'atemp',
    'airtemp',
    'air_temp',
  };
  static const _metadataKeys = <String>{
    'sport',
    'sporttype',
    'activitytype',
    'creator',
    'device',
    'deviceinfo',
  };

  static ParseResult parse(Uint8List bytes, {String? fileName}) {
    if (bytes.isEmpty) {
      throw const ActivityParseException(
        'The selected KML file is empty. Choose a valid KML activity file.',
      );
    }

    final String xmlString;
    try {
      xmlString = utf8.decode(bytes);
    } on FormatException {
      throw const ActivityParseException(
        'Could not read the file as UTF-8 text. Ensure the file is a valid KML XML file.',
      );
    }

    final XmlDocument document;
    try {
      document = XmlDocument.parse(xmlString);
    } on XmlException catch (e) {
      throw ActivityParseException(
        'Corrupted KML XML file: ${e.message}. Export a fresh KML file from your watch or app and try again.',
      );
    }

    final root = document.rootElement;
    if (root.localName != 'kml') {
      throw ActivityParseException(
        'Expected a <kml> root element, found <${root.localName}>. Select a valid KML file.',
      );
    }

    final documentEl = _firstChildByLocalName(root, 'Document');
    final placemarks = root.descendants
        .whereType<XmlElement>()
        .where((e) => e.localName == 'Placemark')
        .toList();
    final firstPlacemark = placemarks.isNotEmpty ? placemarks.first : null;

    final rawTitle = (documentEl != null ? _childText(documentEl, 'name') : null) ??
        (firstPlacemark != null ? _childText(firstPlacemark, 'name') : null) ??
        _fallbackTitle(fileName);
    final rawDesc =
        (documentEl != null ? _childText(documentEl, 'description') : null) ??
            (firstPlacemark != null
                ? _childText(firstPlacemark, 'description')
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
      final whenEls = _childrenByLocalName(trackEl, 'when').toList();
      final coordEls = _childrenByLocalName(trackEl, 'coord').toList();

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

        var hr = i < arrays.heartRates.length ? arrays.heartRates[i] : null;
        if (hr != null && hr <= 0) {
          hr = null;
          zeroHrCount++;
        }
        final cad = i < arrays.cadences.length ? arrays.cadences[i] : null;
        final pwr = i < arrays.powers.length ? arrays.powers[i] : null;
        final temp =
            i < arrays.temperatures.length ? arrays.temperatures[i] : null;

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

      final coordsText = _childText(pointEl, 'coordinates');
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
          heartRateBpm: ext.heartRate,
          cadenceRpm: ext.cadence,
          powerWatts: ext.power,
          temperatureCelsius: ext.temperature,
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

    final channels = <Channel>{};
    for (final pt in normalizedPoints) {
      if (pt.latitude != null && pt.longitude != null) {
        channels.add(Channel.gps);
      }
      if (pt.elevationMeters != null) channels.add(Channel.elevation);
      if (pt.heartRateBpm != null) channels.add(Channel.heartRate);
      if (pt.cadenceRpm != null) channels.add(Channel.cadence);
      if (pt.powerWatts != null) channels.add(Channel.power);
      if (pt.temperatureCelsius != null) channels.add(Channel.temperature);
    }

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
      temperatureCelsius: next.temperatureCelsius ?? prev.temperatureCelsius,
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

    final hasHr = updated.availableChannels.contains(Channel.heartRate);
    final hasCadence = updated.availableChannels.contains(Channel.cadence);
    final hasPower = updated.availableChannels.contains(Channel.power);
    final hasTemperature = updated.availableChannels.contains(Channel.temperature);
    final hasTelemetryArrays =
        hasHr || hasCadence || hasPower || hasTemperature;

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
                if (hasHr) {
                  _writeSimpleArrayField(
                    builder,
                    name: 'heartrate',
                    displayName: 'Heart Rate',
                  );
                }
                if (hasCadence) {
                  _writeSimpleArrayField(
                    builder,
                    name: 'cadence',
                    displayName: 'Cadence',
                  );
                }
                if (hasPower) {
                  _writeSimpleArrayField(
                    builder,
                    name: 'power',
                    displayName: 'Power',
                  );
                }
                if (hasTemperature) {
                  _writeSimpleArrayField(
                    builder,
                    name: 'temperature',
                    displayName: 'Temperature',
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
              builder.element('altitudeMode', nest: 'clampToGround');
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
                      if (hasHr) {
                        _writeSimpleArrayData(
                          builder,
                          name: 'heartrate',
                          values: updated.trackpoints
                              .map((pt) => pt.heartRateBpm)
                              .toList(),
                        );
                      }
                      if (hasCadence) {
                        _writeSimpleArrayData(
                          builder,
                          name: 'cadence',
                          values: updated.trackpoints
                              .map((pt) => pt.cadenceRpm)
                              .toList(),
                        );
                      }
                      if (hasPower) {
                        _writeSimpleArrayData(
                          builder,
                          name: 'power',
                          values: updated.trackpoints
                              .map((pt) => pt.powerWatts)
                              .toList(),
                        );
                      }
                      if (hasTemperature) {
                        _writeSimpleArrayData(
                          builder,
                          name: 'temperature',
                          values: updated.trackpoints
                              .map((pt) => pt.temperatureCelsius)
                              .toList(),
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

  static _SimpleArrayDataResult _extractSimpleArrayData(XmlElement trackEl) {
    final extContainers = <XmlElement>[
      ..._childrenByLocalName(trackEl, 'ExtendedData'),
    ];
    if (extContainers.isEmpty) {
      final parent = trackEl.parentElement;
      if (parent != null && parent.localName == 'Placemark') {
        extContainers.addAll(_childrenByLocalName(parent, 'ExtendedData'));
      }
    }
    if (extContainers.isEmpty) {
      return const _SimpleArrayDataResult();
    }

    var heartRates = const <int?>[];
    var cadences = const <int?>[];
    var powers = const <int?>[];
    var temperatures = const <int?>[];
    var hasUnsupported = false;

    for (final ext in extContainers) {
      for (final node in ext.descendants.whereType<XmlElement>()) {
        if (node.localName.toLowerCase() != 'simplearraydata') continue;
        final name = (node.getAttribute('name') ?? '').trim().toLowerCase();
        final values = node.childElements
            .where((c) => c.localName.toLowerCase() == 'value')
            .map((v) => _parseOptionalInt(v.innerText))
            .toList();

        if (_hrAliases.contains(name)) {
          if (heartRates.isEmpty) heartRates = values;
        } else if (_cadenceAliases.contains(name)) {
          if (cadences.isEmpty) cadences = values;
        } else if (_powerAliases.contains(name)) {
          if (powers.isEmpty) powers = values;
        } else if (_tempAliases.contains(name)) {
          if (temperatures.isEmpty) temperatures = values;
        } else {
          hasUnsupported = true;
        }
      }
    }

    return _SimpleArrayDataResult(
      heartRates: heartRates,
      cadences: cadences,
      powers: powers,
      temperatures: temperatures,
      hasUnsupported: hasUnsupported,
    );
  }

  static String? _extractPlacemarkTimestamp(XmlElement placemark) {
    final timeStampEl = _firstChildByLocalName(placemark, 'TimeStamp');
    if (timeStampEl != null) {
      final when = _childText(timeStampEl, 'when');
      if (when != null) return when;
    }
    final directWhen = _childText(placemark, 'when');
    if (directWhen != null) return directWhen;
    final timeSpanEl = _firstChildByLocalName(placemark, 'TimeSpan');
    if (timeSpanEl != null) {
      return _childText(timeSpanEl, 'begin');
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
      final ext = _firstChildByLocalName(container, 'ExtendedData');
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
    final ext = _firstChildByLocalName(placemark, 'ExtendedData');
    if (ext == null) return const _KmlPlacemarkExtensionData();

    int? hr;
    int? cad;
    int? power;
    int? temp;
    var droppedZeroHr = false;
    var hasUnsupported = false;

    for (final entry in _readNamedDataPairs(ext)) {
      final key = entry.key;
      if (_metadataKeys.contains(key)) continue;

      final parsed = _parseOptionalInt(entry.value);
      if (_hrAliases.contains(key)) {
        if (parsed != null) {
          if (parsed <= 0) {
            droppedZeroHr = true;
          } else {
            hr ??= parsed;
          }
        }
      } else if (_cadenceAliases.contains(key)) {
        if (parsed != null) cad ??= parsed;
      } else if (_powerAliases.contains(key)) {
        if (parsed != null) power ??= parsed;
      } else if (_tempAliases.contains(key)) {
        if (parsed != null) temp ??= parsed;
      } else {
        hasUnsupported = true;
      }
    }

    return _KmlPlacemarkExtensionData(
      heartRate: hr,
      cadence: cad,
      power: power,
      temperature: temp,
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
        final value = _childText(node, 'value') ?? '';
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

class _SimpleArrayDataResult {
  const _SimpleArrayDataResult({
    this.heartRates = const [],
    this.cadences = const [],
    this.powers = const [],
    this.temperatures = const [],
    this.hasUnsupported = false,
  });

  final List<int?> heartRates;
  final List<int?> cadences;
  final List<int?> powers;
  final List<int?> temperatures;
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
    this.heartRate,
    this.cadence,
    this.power,
    this.temperature,
    this.droppedZeroHr = false,
    this.hasUnsupportedExtensions = false,
  });

  final int? heartRate;
  final int? cadence;
  final int? power;
  final int? temperature;
  final bool droppedZeroHr;
  final bool hasUnsupportedExtensions;
}
