import 'dart:convert';
import 'dart:typed_data';

import 'package:xml/xml.dart';

import 'models.dart';
import 'summary_calculator.dart';

/// Pure-Dart TCX 2.0 parser and serializer.
class TcxCodec {
  const TcxCodec._();

  static const _tcxNamespace =
      'http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2';
  static const _xsiNamespace = 'http://www.w3.org/2001/XMLSchema-instance';
  static const _axNamespace =
      'http://www.garmin.com/xmlschemas/ActivityExtension/v2';

  static const _knownTrackpointExtensionTags = <String>{
    'tpx',
    'speed',
    'runcadence',
    'watts',
  };

  static ParseResult parse(Uint8List bytes, {String? fileName}) {
    if (bytes.isEmpty) {
      throw const ActivityParseException(
        'The selected TCX file is empty. Choose a valid TCX activity file.',
      );
    }

    final String xmlString;
    try {
      xmlString = utf8.decode(bytes);
    } on FormatException {
      throw const ActivityParseException(
        'Could not read the file as UTF-8 text. Ensure the file is a valid TCX XML file.',
      );
    }

    final XmlDocument document;
    try {
      document = XmlDocument.parse(xmlString);
    } on XmlException catch (e) {
      throw ActivityParseException(
        'Corrupted TCX XML file: ${e.message}. Export a fresh TCX file from your watch or app and try again.',
      );
    }

    final root = document.rootElement;
    if (root.localName != 'TrainingCenterDatabase') {
      throw ActivityParseException(
        'Expected a <TrainingCenterDatabase> root element, found <${root.localName}>. Select a valid TCX file.',
      );
    }

    final activitiesEl = _firstChildByLocalName(root, 'Activities');
    final activityEls = activitiesEl != null
        ? _childrenByLocalName(activitiesEl, 'Activity').toList()
        : const <XmlElement>[];

    if (activityEls.isEmpty) {
      throw const ActivityParseException(
        'This TCX file contains no <Activity> entries. Select a recorded TCX activity file.',
      );
    }

    final firstActivity = activityEls.first;
    final rawSport = firstActivity.getAttribute('Sport');
    final sportType = SportType.fromTcxSport(rawSport);

    final notes = _childText(firstActivity, 'Notes');
    final (title, description) = _splitNotes(notes, fileName);

    final creatorEl = _firstChildByLocalName(firstActivity, 'Creator');
    final activityCreator =
        creatorEl != null ? _childText(creatorEl, 'Name') : null;
    final authorEl = _firstChildByLocalName(root, 'Author');
    final dbAuthor = authorEl != null ? _childText(authorEl, 'Name') : null;
    final rootCreator =
        (root.getAttribute('creator') ?? root.getAttribute('Creator'))?.trim();
    final deviceInfo = [activityCreator, dbAuthor, rootCreator]
        .whereType<String>()
        .map((s) => s.trim())
        .firstWhere((s) => s.isNotEmpty, orElse: () => '');
    final resolvedDeviceInfo = deviceInfo.isEmpty ? null : deviceInfo;

    final lapEls = _childrenByLocalName(firstActivity, 'Lap').toList();
    if (lapEls.isEmpty) {
      throw const ActivityParseException(
        'This TCX file contains no <Lap> data. Select a recorded TCX activity file.',
      );
    }

    final rawPoints = <Trackpoint>[];
    final parsedLaps = <_ParsedLapMeta>[];
    var zeroHrCount = 0;
    var unsupportedExtensionCount = 0;
    var totalCalories = 0;
    var hasCalories = false;

    for (final lapEl in lapEls) {
      final lapStartAttr = lapEl.getAttribute('StartTime');
      final lapStart = lapStartAttr != null
          ? DateTime.tryParse(lapStartAttr.trim())?.toUtc()
          : null;
      final lapDurationSec =
          double.tryParse(_childText(lapEl, 'TotalTimeSeconds') ?? '');
      final lapDist =
          double.tryParse(_childText(lapEl, 'DistanceMeters') ?? '');
      final lapCalories = int.tryParse(_childText(lapEl, 'Calories') ?? '');
      if (lapCalories != null) {
        totalCalories += lapCalories;
        hasCalories = true;
      }

      final lapAvgHr = _readHrValue(_firstChildByLocalName(lapEl, 'AverageHeartRateBpm'));
      final lapMaxHr = _readHrValue(_firstChildByLocalName(lapEl, 'MaximumHeartRateBpm'));

      final lapPoints = <Trackpoint>[];
      for (final trackEl in _childrenByLocalName(lapEl, 'Track')) {
        for (final tpEl in _childrenByLocalName(trackEl, 'Trackpoint')) {
          final timeText = _childText(tpEl, 'Time');
          if (timeText == null) {
            throw const ActivityParseException(
              'Some trackpoints in this TCX file are missing <Time> timestamps. All trackpoints must have valid timestamps.',
            );
          }
          final timestamp = DateTime.tryParse(timeText)?.toUtc();
          if (timestamp == null) {
            throw ActivityParseException(
              'Invalid trackpoint timestamp "$timeText". TCX timestamps must be ISO-8601 date/time values.',
            );
          }

          double? lat;
          double? lon;
          final posEl = _firstChildByLocalName(tpEl, 'Position');
          if (posEl != null) {
            lat = double.tryParse(_childText(posEl, 'LatitudeDegrees') ?? '');
            lon = double.tryParse(_childText(posEl, 'LongitudeDegrees') ?? '');
          }

          final ele =
              double.tryParse(_childText(tpEl, 'AltitudeMeters') ?? '');
          final dist =
              double.tryParse(_childText(tpEl, 'DistanceMeters') ?? '');

          int? hr = _readHrValue(
            _firstChildByLocalName(tpEl, 'HeartRateBpm'),
          );
          if (hr != null && hr <= 0) {
            hr = null;
            zeroHrCount++;
          }

          int? cad = int.tryParse(_childText(tpEl, 'Cadence') ?? '');
          final ext = _extractTrackpointExtensions(tpEl);
          cad ??= ext.runCadence;
          if (ext.hasUnsupportedExtensions) {
            unsupportedExtensionCount++;
          }

          final pt = Trackpoint(
            timestamp: timestamp,
            latitude: lat,
            longitude: lon,
            elevationMeters: ele,
            cumulativeDistanceMeters: dist,
            heartRateBpm: hr,
            cadenceRpm: cad,
            powerWatts: ext.watts,
          );
          lapPoints.add(pt);
          rawPoints.add(pt);
        }
      }

      if (lapPoints.isNotEmpty || lapStart != null) {
        final effectiveStart = lapStart ?? lapPoints.first.timestamp;
        final effectiveEnd = lapPoints.isNotEmpty
            ? lapPoints.last.timestamp
            : (lapDurationSec != null
                ? effectiveStart.add(
                    Duration(milliseconds: (lapDurationSec * 1000).round()),
                  )
                : effectiveStart);
        parsedLaps.add(
          _ParsedLapMeta(
            startTime: effectiveStart,
            endTime: effectiveEnd,
            distanceMeters: lapDist,
            avgHeartRateBpm: lapAvgHr,
            maxHeartRateBpm: lapMaxHr,
            calories: lapCalories,
          ),
        );
      }
    }

    if (rawPoints.isEmpty) {
      throw const ActivityParseException(
        'This TCX file contains zero trackpoints. Select a recorded activity TCX file.',
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

    // Normalize missing first-point cumulative distance when later points record distance.
    final hasAnyDistance =
        normalizedPoints.any((p) => p.cumulativeDistanceMeters != null);
    if (hasAnyDistance &&
        normalizedPoints.first.cumulativeDistanceMeters == null) {
      final first = normalizedPoints.first;
      normalizedPoints[0] = Trackpoint(
        timestamp: first.timestamp,
        latitude: first.latitude,
        longitude: first.longitude,
        elevationMeters: first.elevationMeters,
        cumulativeDistanceMeters: 0.0,
        heartRateBpm: first.heartRateBpm,
        cadenceRpm: first.cadenceRpm,
        powerWatts: first.powerWatts,
        temperatureCelsius: first.temperatureCelsius,
      );
      diagnostics.add(
        const Diagnostic(
          code: DiagnosticCode.missingFirstPointDistanceNormalized,
          severity: DiagnosticSeverity.info,
          message:
              'Normalized missing cumulative distance on the first trackpoint to 0.0 m.',
          count: 1,
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

    final finalPoints = (!hasAnyDistance &&
            parsedLaps.any(
              (l) => l.distanceMeters != null && l.distanceMeters! > 0,
            ))
        ? _distributeLapDistances(normalizedPoints, parsedLaps)
        : normalizedPoints;

    final channels = _detectChannels(finalPoints);
    final laps = _recomputeLaps(
      finalPoints,
      parsedLaps,
      hasCalories ? totalCalories : null,
    );

    final activity = Activity(
      title: title,
      description: description,
      sportType: sportType,
      trackpoints: finalPoints,
      laps: laps,
      availableChannels: channels,
      calories: hasCalories ? totalCalories : null,
      deviceInfo: resolvedDeviceInfo,
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
    final updatedMeta = SummaryCalculator.applyEdits(activity, edit);

    final finalPoints = _ensureCumulativeDistance(updatedMeta.trackpoints);
    final lapMetas = updatedMeta.laps.isEmpty
        ? [
            _ParsedLapMeta(
              startTime: finalPoints.isEmpty
                  ? DateTime.now().toUtc()
                  : finalPoints.first.timestamp,
              endTime: finalPoints.isEmpty
                  ? DateTime.now().toUtc()
                  : finalPoints.last.timestamp,
              calories: updatedMeta.calories,
            ),
          ]
        : updatedMeta.laps
            .map(
              (l) => _ParsedLapMeta(
                startTime: l.startTime,
                endTime: l.endTime,
                distanceMeters: l.distanceMeters,
                avgHeartRateBpm: l.avgHeartRateBpm,
                maxHeartRateBpm: l.maxHeartRateBpm,
                calories: l.calories,
              ),
            )
            .toList();

    final recomputedLaps = finalPoints.isEmpty
        ? updatedMeta.laps
        : _recomputeLaps(finalPoints, lapMetas, updatedMeta.calories);

    final channels = _detectChannels(finalPoints);
    final updated = updatedMeta.copyWith(
      trackpoints: finalPoints,
      laps: recomputedLaps,
      availableChannels: channels,
    );

    final builder = XmlBuilder();
    builder.processing('xml', 'version="1.0" encoding="UTF-8"');
    builder.element(
      'TrainingCenterDatabase',
      attributes: {
        'xmlns': _tcxNamespace,
        'xmlns:xsi': _xsiNamespace,
        'xmlns:ns3': _axNamespace,
      },
      nest: () {
        builder.element('Activities', nest: () {
          builder.element(
            'Activity',
            attributes: {'Sport': updated.sportType.tcxName},
            nest: () {
              final idTimestamp = finalPoints.isNotEmpty
                  ? finalPoints.first.timestamp.toUtc().toIso8601String()
                  : DateTime.now().toUtc().toIso8601String();
              builder.element('Id', nest: idTimestamp);

              final partitioned = _partitionPointsByLap(
                finalPoints,
                recomputedLaps,
              );

              for (var i = 0; i < recomputedLaps.length; i++) {
                final lap = recomputedLaps[i];
                final lapPoints = partitioned[i];
                builder.element(
                  'Lap',
                  attributes: {
                    'StartTime': lap.startTime.toUtc().toIso8601String(),
                  },
                  nest: () {
                    builder.element(
                      'TotalTimeSeconds',
                      nest: (lap.duration.inMilliseconds / 1000.0)
                          .toStringAsFixed(3),
                    );
                    builder.element(
                      'DistanceMeters',
                      nest: (lap.distanceMeters ?? 0.0).toStringAsFixed(2),
                    );
                    if (lap.calories != null) {
                      builder.element(
                        'Calories',
                        nest: lap.calories.toString(),
                      );
                    }
                    if (lap.avgHeartRateBpm != null) {
                      builder.element('AverageHeartRateBpm', nest: () {
                        builder.element(
                          'Value',
                          nest: lap.avgHeartRateBpm.toString(),
                        );
                      });
                    }
                    if (lap.maxHeartRateBpm != null) {
                      builder.element('MaximumHeartRateBpm', nest: () {
                        builder.element(
                          'Value',
                          nest: lap.maxHeartRateBpm.toString(),
                        );
                      });
                    }
                    builder.element('Intensity', nest: 'Active');
                    if (lap.avgCadenceRpm != null &&
                        updated.sportType == SportType.cycling) {
                      builder.element(
                        'Cadence',
                        nest: lap.avgCadenceRpm.toString(),
                      );
                    }
                    builder.element('TriggerMethod', nest: 'Manual');
                    if (lap.avgCadenceRpm != null || lap.maxCadenceRpm != null) {
                      builder.element('Extensions', nest: () {
                        builder.element('ns3:LX', nest: () {
                          if (lap.avgCadenceRpm != null) {
                            builder.element(
                              'ns3:AvgRunCadence',
                              nest: lap.avgCadenceRpm.toString(),
                            );
                          }
                          if (lap.maxCadenceRpm != null) {
                            builder.element(
                              'ns3:MaxRunCadence',
                              nest: lap.maxCadenceRpm.toString(),
                            );
                          }
                        });
                      });
                    }

                    builder.element('Track', nest: () {
                      for (final pt in lapPoints) {
                        builder.element('Trackpoint', nest: () {
                          builder.element(
                            'Time',
                            nest: pt.timestamp.toUtc().toIso8601String(),
                          );
                          if (pt.latitude != null && pt.longitude != null) {
                            builder.element('Position', nest: () {
                              builder.element(
                                'LatitudeDegrees',
                                nest: pt.latitude!.toStringAsFixed(6),
                              );
                              builder.element(
                                'LongitudeDegrees',
                                nest: pt.longitude!.toStringAsFixed(6),
                              );
                            });
                          }
                          if (pt.elevationMeters != null) {
                            builder.element(
                              'AltitudeMeters',
                              nest: pt.elevationMeters!.toStringAsFixed(1),
                            );
                          }
                          if (pt.cumulativeDistanceMeters != null) {
                            builder.element(
                              'DistanceMeters',
                              nest: pt.cumulativeDistanceMeters!
                                  .toStringAsFixed(2),
                            );
                          }
                          if (pt.heartRateBpm != null) {
                            builder.element('HeartRateBpm', nest: () {
                              builder.element(
                                'Value',
                                nest: pt.heartRateBpm.toString(),
                              );
                            });
                          }
                          if (pt.cadenceRpm != null &&
                              updated.sportType == SportType.cycling) {
                            builder.element(
                              'Cadence',
                              nest: pt.cadenceRpm.toString(),
                            );
                          }
                          if ((pt.cadenceRpm != null &&
                                  updated.sportType != SportType.cycling) ||
                              pt.powerWatts != null) {
                            builder.element('Extensions', nest: () {
                              builder.element('ns3:TPX', nest: () {
                                if (pt.cadenceRpm != null &&
                                    updated.sportType != SportType.cycling) {
                                  builder.element(
                                    'ns3:RunCadence',
                                    nest: pt.cadenceRpm.toString(),
                                  );
                                }
                                if (pt.powerWatts != null) {
                                  builder.element(
                                    'ns3:Watts',
                                    nest: pt.powerWatts.toString(),
                                  );
                                }
                              });
                            });
                          }
                        });
                      }
                    });
                  },
                );
              }

              final notesText = updated.description.isNotEmpty
                  ? '${updated.title} — ${updated.description}'
                  : updated.title;
              builder.element('Notes', nest: notesText);

              if (updated.deviceInfo != null &&
                  updated.deviceInfo!.trim().isNotEmpty) {
                builder.element(
                  'Creator',
                  attributes: {'xsi:type': 'Device_t'},
                  nest: () {
                    builder.element('Name', nest: updated.deviceInfo!.trim());
                  },
                );
              }
            },
          );
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

  static List<Trackpoint> _ensureCumulativeDistance(List<Trackpoint> points) {
    if (points.isEmpty) return points;
    final hasRecorded = points.any((p) => p.cumulativeDistanceMeters != null);

    final result = <Trackpoint>[];
    var runningDist = 0.0;
    Trackpoint? prevGps;

    for (var i = 0; i < points.length; i++) {
      final pt = points[i];
      if (hasRecorded) {
        if (pt.cumulativeDistanceMeters != null) {
          runningDist = pt.cumulativeDistanceMeters!;
        }
      } else {
        if (pt.latitude != null && pt.longitude != null) {
          if (prevGps != null) {
            runningDist += SummaryCalculator.haversineMeters(
              prevGps.latitude!,
              prevGps.longitude!,
              pt.latitude!,
              pt.longitude!,
            );
          }
          prevGps = pt;
        }
      }

      result.add(
        Trackpoint(
          timestamp: pt.timestamp,
          latitude: pt.latitude,
          longitude: pt.longitude,
          elevationMeters: pt.elevationMeters,
          cumulativeDistanceMeters:
              hasRecorded ? (pt.cumulativeDistanceMeters ?? runningDist) : runningDist,
          heartRateBpm: pt.heartRateBpm,
          cadenceRpm: pt.cadenceRpm,
          powerWatts: pt.powerWatts,
          temperatureCelsius: pt.temperatureCelsius,
        ),
      );
    }

    return result;
  }

  static List<List<Trackpoint>> _partitionPointsByLap(
    List<Trackpoint> points,
    List<Lap> laps,
  ) =>
      _partitionPointsByEndTimes(
        points,
        [for (final lap in laps) lap.endTime],
      );

  static List<List<Trackpoint>> _partitionPointsByEndTimes(
    List<Trackpoint> points,
    List<DateTime> endTimes,
  ) {
    final result = List.generate(endTimes.length, (_) => <Trackpoint>[]);
    var ptIdx = 0;
    for (var i = 0; i < endTimes.length; i++) {
      final endTime = endTimes[i];
      final isLast = i == endTimes.length - 1;
      while (ptIdx < points.length) {
        final pt = points[ptIdx];
        if (!isLast && pt.timestamp.isAfter(endTime)) {
          break;
        }
        result[i].add(pt);
        ptIdx++;
      }
    }
    return result;
  }

  static Set<Channel> _detectChannels(List<Trackpoint> points) {
    final channels = <Channel>{};
    for (final pt in points) {
      if (pt.latitude != null && pt.longitude != null) {
        channels.add(Channel.gps);
      }
      if (pt.elevationMeters != null) channels.add(Channel.elevation);
      if (pt.cumulativeDistanceMeters != null) channels.add(Channel.distance);
      if (pt.heartRateBpm != null) channels.add(Channel.heartRate);
      if (pt.cadenceRpm != null) channels.add(Channel.cadence);
      if (pt.powerWatts != null) channels.add(Channel.power);
      if (pt.temperatureCelsius != null) channels.add(Channel.temperature);
    }
    return channels;
  }

  static List<Trackpoint> _distributeLapDistances(
    List<Trackpoint> points,
    List<_ParsedLapMeta> metaLaps,
  ) {
    if (points.isEmpty || metaLaps.isEmpty) return points;
    final partitioned = _partitionPointsByEndTimes(
      points,
      [for (final meta in metaLaps) meta.endTime],
    );
    final distributed = <Trackpoint>[];
    var runningDist = 0.0;
    Trackpoint? prevPoint;

    for (var i = 0; i < metaLaps.length; i++) {
      final meta = metaLaps[i];
      final lapPoints = partitioned[i];
      if (lapPoints.isEmpty) {
        if (meta.distanceMeters != null && meta.distanceMeters! > 0) {
          runningDist += meta.distanceMeters!;
        }
        continue;
      }

      final scaled = SummaryCalculator.distributeDistanceRange(
        lapPoints,
        spanMeters: meta.distanceMeters,
        startDistanceMeters: runningDist,
        precedingPoint: prevPoint,
      );
      distributed.addAll(scaled);
      runningDist =
          scaled.last.cumulativeDistanceMeters ?? runningDist;
      prevPoint = lapPoints.last;
    }

    return distributed;
  }

  static List<Lap> _recomputeLaps(
    List<Trackpoint> points,
    List<_ParsedLapMeta> metaLaps,
    int? totalCalories,
  ) {
    if (metaLaps.isEmpty) {
      metaLaps = [
        _ParsedLapMeta(
          startTime: points.first.timestamp,
          endTime: points.last.timestamp,
          calories: totalCalories,
        ),
      ];
    }

    final partitioned = _partitionPointsByEndTimes(
      points,
      [for (final meta in metaLaps) meta.endTime],
    );
    final result = <Lap>[];
    var prevLapEndDist = 0.0;

    for (var i = 0; i < metaLaps.length; i++) {
      final meta = metaLaps[i];
      final lapPoints = partitioned[i];

      int hrSum = 0;
      int hrCount = 0;
      int hrMax = 0;
      int cadSum = 0;
      int cadCount = 0;
      int cadMax = 0;

      for (final pt in lapPoints) {
        final hr = pt.heartRateBpm;
        if (hr != null && hr > 0) {
          hrSum += hr;
          hrCount++;
          if (hr > hrMax) hrMax = hr;
        }
        final cad = pt.cadenceRpm;
        if (cad != null && cad >= 0) {
          cadSum += cad;
          cadCount++;
          if (cad > cadMax) cadMax = cad;
        }
      }

      double? lapDist = meta.distanceMeters;
      if (lapPoints.isNotEmpty &&
          lapPoints.last.cumulativeDistanceMeters != null) {
        final endDist = lapPoints.last.cumulativeDistanceMeters!;
        lapDist = (endDist - prevLapEndDist).clamp(0.0, double.infinity);
        prevLapEndDist = endDist;
      }

      result.add(
        Lap(
          startTime: meta.startTime,
          endTime: meta.endTime,
          distanceMeters: lapDist,
          avgHeartRateBpm:
              hrCount > 0 ? (hrSum / hrCount).round() : meta.avgHeartRateBpm,
          maxHeartRateBpm: hrCount > 0 ? hrMax : meta.maxHeartRateBpm,
          avgCadenceRpm: cadCount > 0 ? (cadSum / cadCount).round() : null,
          maxCadenceRpm: cadCount > 0 ? cadMax : null,
          calories: meta.calories,
        ),
      );
    }

    return result;
  }

  static (String, String) _splitNotes(String? notes, String? fileName) {
    if (notes == null || notes.trim().isEmpty) {
      return (_fallbackTitle(fileName), '');
    }
    const separator = ' — ';
    final idx = notes.indexOf(separator);
    if (idx > 0) {
      return (
        notes.substring(0, idx).trim(),
        notes.substring(idx + separator.length).trim(),
      );
    }
    return (notes.trim(), '');
  }

  static int? _readHrValue(XmlElement? hrEl) {
    if (hrEl == null) return null;
    final valText = _childText(hrEl, 'Value');
    if (valText != null) {
      return int.tryParse(valText) ?? double.tryParse(valText)?.round();
    }
    return int.tryParse(hrEl.innerText.trim());
  }

  static _TcxExtensionData _extractTrackpointExtensions(XmlElement tpEl) {
    final extensions = _firstChildByLocalName(tpEl, 'Extensions');
    if (extensions == null) return const _TcxExtensionData();

    int? runCadence;
    int? watts;
    var hasUnsupported = false;

    for (final node in extensions.descendants.whereType<XmlElement>()) {
      final name = node.localName.toLowerCase();
      if (!_knownTrackpointExtensionTags.contains(name)) {
        hasUnsupported = true;
        continue;
      }
      if (name == 'runcadence') {
        runCadence ??= int.tryParse(node.innerText.trim());
      } else if (name == 'watts') {
        watts ??= int.tryParse(node.innerText.trim());
      }
    }

    return _TcxExtensionData(
      runCadence: runCadence,
      watts: watts,
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

class _TcxExtensionData {
  const _TcxExtensionData({
    this.runCadence,
    this.watts,
    this.hasUnsupportedExtensions = false,
  });

  final int? runCadence;
  final int? watts;
  final bool hasUnsupportedExtensions;
}

class _ParsedLapMeta {
  const _ParsedLapMeta({
    required this.startTime,
    required this.endTime,
    this.distanceMeters,
    this.avgHeartRateBpm,
    this.maxHeartRateBpm,
    this.calories,
  });

  final DateTime startTime;
  final DateTime endTime;
  final double? distanceMeters;
  final int? avgHeartRateBpm;
  final int? maxHeartRateBpm;
  final int? calories;
}
