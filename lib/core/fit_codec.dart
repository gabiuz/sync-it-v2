import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'models.dart';
import 'summary_calculator.dart';

/// Pure-Dart FIT binary parser and serializer.
class FitCodec {
  const FitCodec._();

  static const int _fitEpochUnixSeconds = 631065600; // 1989-12-31T00:00:00Z
  static const double _semicirclesPerDegree = 2147483648.0 / 180.0;

  // Global FIT message numbers.
  static const int _mesgFileId = 0;
  static const int _mesgSport = 12;
  static const int _mesgSession = 18;
  static const int _mesgLap = 19;
  static const int _mesgRecord = 20;
  static const int _mesgEvent = 21;
  static const int _mesgDeviceInfo = 23;
  static const int _mesgActivity = 34;
  static const int _mesgFileCreator = 49;
  static const int _mesgFieldDescription = 206;
  static const int _mesgDeveloperDataId = 207;

  static const Set<int> _knownGlobalMessages = {
    _mesgFileId,
    _mesgSport,
    _mesgSession,
    _mesgLap,
    _mesgRecord,
    _mesgEvent,
    _mesgDeviceInfo,
    _mesgActivity,
    _mesgFileCreator,
    72, // training_file
    104, // battery
    140, // device_settings / aux
  };

  static const Set<int> _knownRecordFields = {
    253, // timestamp
    0, // position_lat
    1, // position_long
    2, // altitude
    3, // heart_rate
    4, // cadence
    5, // distance
    6, // speed
    7, // power
    8, // compressed_speed_distance
    9, // grade
    10, // resistance
    11, // time_from_course
    12, // cycle_length
    13, // temperature
    31, // gps_accuracy
    33, // calories
    53, // fractional_cadence
    73, // enhanced_speed
    78, // enhanced_altitude
  };

  static const Set<int> _knownLapFields = {
    253, // timestamp
    254, // message_index
    0, // event
    1, // event_type
    2, // start_time
    3, // start_position_lat
    4, // start_position_long
    5, // end_position_lat
    6, // end_position_long
    7, // total_elapsed_time
    8, // total_timer_time
    9, // total_distance
    10, // total_cycles
    11, // total_calories
    13, // avg_speed
    14, // max_speed
    15, // avg_heart_rate
    16, // max_heart_rate
    17, // avg_cadence
    18, // max_cadence
    19, // avg_power
    20, // max_power
    21, // total_ascent
    22, // total_descent
    24, // lap_trigger
    25, // sport
    39, // sub_sport
    110, // enhanced_avg_speed
    111, // enhanced_max_speed
  };

  static const Set<int> _knownSessionFields = {
    253, // timestamp
    254, // message_index
    0, // event
    1, // event_type
    2, // start_time
    3, // start_position_lat
    4, // start_position_long
    5, // sport
    6, // sub_sport
    7, // total_elapsed_time
    8, // total_timer_time
    9, // total_distance
    10, // total_cycles
    11, // total_calories
    14, // avg_speed
    15, // max_speed
    16, // avg_heart_rate
    17, // max_heart_rate
    18, // avg_cadence
    19, // max_cadence
    20, // avg_power
    21, // max_power
    22, // total_ascent
    23, // total_descent
    25, // first_lap_index
    26, // num_laps
    28, // trigger
    124, // enhanced_avg_speed
    125, // enhanced_max_speed
  };

  static const _crcTable = <int>[
    0x0000,
    0xCC01,
    0xD801,
    0x1400,
    0xF001,
    0x3C00,
    0x2800,
    0xE401,
    0xA001,
    0x6C00,
    0x7800,
    0xB401,
    0x5000,
    0x9C01,
    0x8801,
    0x4400,
  ];

  /// Computes the standard FIT CRC-16 checksum over [bytes] from [start] to [end].
  static int computeCrc(Uint8List bytes, [int start = 0, int? end]) {
    var crc = 0;
    final limit = end ?? bytes.length;
    for (var i = start; i < limit; i++) {
      final byte = bytes[i];
      var tmp = _crcTable[crc & 0x0F];
      crc = (crc >> 4) & 0x0FFF;
      crc = crc ^ tmp ^ _crcTable[byte & 0x0F];
      tmp = _crcTable[crc & 0x0F];
      crc = (crc >> 4) & 0x0FFF;
      crc = crc ^ tmp ^ _crcTable[(byte >> 4) & 0x0F];
    }
    return crc;
  }

  static ParseResult parse(Uint8List bytes, {String? fileName}) {
    if (bytes.isEmpty) {
      throw const ActivityParseException(
        'The selected FIT file is empty. Choose a valid FIT activity file.',
      );
    }

    if (bytes.length < 14) {
      throw const ActivityParseException(
        'Truncated FIT file: header is incomplete. Export a fresh FIT file from your watch or app and try again.',
      );
    }

    final headerSize = bytes[0];
    if (headerSize != 12 && headerSize != 14) {
      throw ActivityParseException(
        'Unsupported or corrupted FIT header size ($headerSize). Ensure the file is a valid FIT activity file.',
      );
    }

    if (bytes.length < headerSize + 2) {
      throw const ActivityParseException(
        'Truncated FIT file: missing data or checksum. Export a fresh FIT file and try again.',
      );
    }

    if (bytes[8] != 0x2E ||
        bytes[9] != 0x46 ||
        bytes[10] != 0x49 ||
        bytes[11] != 0x54) {
      throw const ActivityParseException(
        'Not a valid FIT file (missing ".FIT" signature). Choose a valid FIT activity file.',
      );
    }

    final bd = ByteData.sublistView(bytes);
    if (headerSize == 14) {
      final headerCrc = bd.getUint16(12, Endian.little);
      if (headerCrc != 0) {
        final expectedHeaderCrc = computeCrc(bytes, 0, 12);
        if (headerCrc != expectedHeaderCrc) {
          throw const ActivityParseException(
            'Corrupted FIT file: header checksum mismatch. Export a fresh FIT file and try again.',
          );
        }
      }
    }

    final dataSize = bd.getUint32(4, Endian.little);
    final expectedTotalLength = headerSize + dataSize + 2;
    if (bytes.length < expectedTotalLength) {
      throw ActivityParseException(
        'Truncated FIT file: expected $expectedTotalLength bytes but found ${bytes.length} bytes.',
      );
    }

    final fileCrcOffset = headerSize + dataSize;
    final fileCrc = bd.getUint16(fileCrcOffset, Endian.little);
    final expectedFileCrc = computeCrc(bytes, 0, fileCrcOffset);
    if (fileCrc != expectedFileCrc) {
      throw const ActivityParseException(
        'Corrupted FIT file: file CRC-16 checksum mismatch. Export a fresh FIT file and try again.',
      );
    }

    final definitions = <int, _FitMessageDef>{};
    final rawPoints = <Trackpoint>[];
    final parsedLaps = <Lap>[];
    SportType? sessionSport;
    String? sportName;
    int? sessionCalories;
    int? fileManufacturer;
    int? fileProduct;
    String? fileProductName;
    int? deviceManufacturer;
    int? deviceProduct;
    String? deviceProductName;

    var zeroHrCount = 0;
    var unsupportedExtensionCount = 0;
    int? lastTimestampSec;

    var offset = headerSize;
    final dataEnd = headerSize + dataSize;

    while (offset < dataEnd) {
      final recordHeader = bytes[offset++];
      final isCompressedTimestamp = (recordHeader & 0x80) != 0;

      if (isCompressedTimestamp) {
        final localMsgType = (recordHeader >> 5) & 0x03;
        final timeOffset = recordHeader & 0x1F;
        final def = definitions[localMsgType];
        if (def == null) {
          throw ActivityParseException(
            'Corrupted FIT file: compressed data message references undefined local type $localMsgType.',
          );
        }
        final prevTs = lastTimestampSec;
        if (prevTs != null) {
          final prevLow5 = prevTs & 0x1F;
          var ts = (prevTs & ~0x1F) | timeOffset;
          if (timeOffset < prevLow5) {
            ts += 0x20;
          }
          lastTimestampSec = ts;
        }
        offset = _readDataMessage(
          bytes: bytes,
          bd: bd,
          offset: offset,
          dataEnd: dataEnd,
          def: def,
          compressedTimestampSec: lastTimestampSec,
          onTimestamp: (ts) => lastTimestampSec = ts,
          onRecord: (pt, droppedZeroHr, unknownFields) {
            rawPoints.add(pt);
            if (droppedZeroHr) zeroHrCount++;
            unsupportedExtensionCount += unknownFields;
          },
          onLap: (lap, unknownFields) {
            parsedLaps.add(lap);
            unsupportedExtensionCount += unknownFields;
          },
          onSession: (sport, cals, unknownFields) {
            sessionSport ??= sport;
            sessionCalories ??= cals;
            unsupportedExtensionCount += unknownFields;
          },
          onSport: (sport, name) {
            sessionSport ??= sport;
            if (name != null && name.isNotEmpty) sportName ??= name;
          },
          onFileId: (mfg, prod, prodName) {
            fileManufacturer ??= mfg;
            fileProduct ??= prod;
            if (prodName != null && prodName.isNotEmpty) {
              fileProductName ??= prodName;
            }
          },
          onDeviceInfo: (mfg, prod, prodName) {
            deviceManufacturer ??= mfg;
            deviceProduct ??= prod;
            if (prodName != null && prodName.isNotEmpty) {
              deviceProductName ??= prodName;
            }
          },
          onUnsupportedExtension: (count) {
            unsupportedExtensionCount += count;
          },
        );
        continue;
      }

      final isDefinition = (recordHeader & 0x40) != 0;
      final hasDevData = (recordHeader & 0x20) != 0;
      final localMsgType = recordHeader & 0x0F;

      if (isDefinition) {
        if (offset + 5 > dataEnd) {
          throw const ActivityParseException(
            'Truncated FIT file: incomplete message definition.',
          );
        }
        offset++; // reserved
        final arch = bytes[offset++];
        final endian = arch == 1 ? Endian.big : Endian.little;
        final globalMsgNum = bd.getUint16(offset, endian);
        offset += 2;
        final numFields = bytes[offset++];

        if (offset + numFields * 3 > dataEnd) {
          throw const ActivityParseException(
            'Truncated FIT file: incomplete field definitions.',
          );
        }

        final fields = <_FitFieldDef>[];
        for (var i = 0; i < numFields; i++) {
          final fieldNum = bytes[offset++];
          final size = bytes[offset++];
          final baseType = bytes[offset++];
          fields.add(_FitFieldDef(fieldNum, size, baseType));
        }

        final devFields = <_FitDevFieldDef>[];
        if (hasDevData) {
          if (offset >= dataEnd) {
            throw const ActivityParseException(
              'Truncated FIT file: missing developer field count.',
            );
          }
          final numDevFields = bytes[offset++];
          if (offset + numDevFields * 3 > dataEnd) {
            throw const ActivityParseException(
              'Truncated FIT file: incomplete developer field definitions.',
            );
          }
          for (var i = 0; i < numDevFields; i++) {
            final fieldNum = bytes[offset++];
            final size = bytes[offset++];
            final devIdx = bytes[offset++];
            devFields.add(_FitDevFieldDef(fieldNum, size, devIdx));
          }
        }

        definitions[localMsgType] = _FitMessageDef(
          globalMsgNum: globalMsgNum,
          endian: endian,
          fields: fields,
          devFields: devFields,
        );
      } else {
        final def = definitions[localMsgType];
        if (def == null) {
          throw ActivityParseException(
            'Corrupted FIT file: data message references undefined local type $localMsgType.',
          );
        }
        offset = _readDataMessage(
          bytes: bytes,
          bd: bd,
          offset: offset,
          dataEnd: dataEnd,
          def: def,
          compressedTimestampSec: null,
          onTimestamp: (ts) => lastTimestampSec = ts,
          onRecord: (pt, droppedZeroHr, unknownFields) {
            rawPoints.add(pt);
            if (droppedZeroHr) zeroHrCount++;
            unsupportedExtensionCount += unknownFields;
          },
          onLap: (lap, unknownFields) {
            parsedLaps.add(lap);
            unsupportedExtensionCount += unknownFields;
          },
          onSession: (sport, cals, unknownFields) {
            sessionSport ??= sport;
            sessionCalories ??= cals;
            unsupportedExtensionCount += unknownFields;
          },
          onSport: (sport, name) {
            sessionSport ??= sport;
            if (name != null && name.isNotEmpty) sportName ??= name;
          },
          onFileId: (mfg, prod, prodName) {
            fileManufacturer ??= mfg;
            fileProduct ??= prod;
            if (prodName != null && prodName.isNotEmpty) {
              fileProductName ??= prodName;
            }
          },
          onDeviceInfo: (mfg, prod, prodName) {
            deviceManufacturer ??= mfg;
            deviceProduct ??= prod;
            if (prodName != null && prodName.isNotEmpty) {
              deviceProductName ??= prodName;
            }
          },
          onUnsupportedExtension: (count) {
            unsupportedExtensionCount += count;
          },
        );
      }
    }

    if (rawPoints.isEmpty) {
      throw const ActivityParseException(
        'This FIT file contains zero activity trackpoints.',
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

    // Deduplicate adjacent identical timestamps.
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
              'Ignored $unsupportedExtensionCount proprietary vendor or developer extension field${unsupportedExtensionCount == 1 ? '' : 's'}; they will not be included on export.',
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
      if (pt.cumulativeDistanceMeters != null) channels.add(Channel.distance);
      if (pt.heartRateBpm != null) channels.add(Channel.heartRate);
      if (pt.cadenceRpm != null) channels.add(Channel.cadence);
      if (pt.powerWatts != null) channels.add(Channel.power);
      if (pt.temperatureCelsius != null) channels.add(Channel.temperature);
    }

    final resolvedSport = sessionSport ?? SportType.other;
    final resolvedTitle = (sportName != null && sportName!.trim().isNotEmpty)
        ? sportName!.trim()
        : _fallbackTitle(fileName, resolvedSport);

    final resolvedDeviceInfo = _formatDeviceInfo(
      deviceProductName ?? fileProductName,
      deviceManufacturer ?? fileManufacturer,
      deviceProduct ?? fileProduct,
    );

    final laps = parsedLaps.isNotEmpty
        ? parsedLaps
        : [
            Lap(
              startTime: normalizedPoints.first.timestamp,
              endTime: normalizedPoints.last.timestamp,
              distanceMeters: normalizedPoints.last.cumulativeDistanceMeters,
            ),
          ];

    final activity = Activity(
      title: resolvedTitle,
      description: '',
      sportType: resolvedSport,
      trackpoints: normalizedPoints,
      laps: laps,
      availableChannels: channels,
      calories: sessionCalories,
      deviceInfo: resolvedDeviceInfo,
    );

    return ParseResult(
      activity: activity,
      summary: SummaryCalculator.compute(activity),
      diagnostics: diagnostics,
    );
  }

  static int _readDataMessage({
    required Uint8List bytes,
    required ByteData bd,
    required int offset,
    required int dataEnd,
    required _FitMessageDef def,
    required int? compressedTimestampSec,
    required void Function(int ts) onTimestamp,
    required void Function(Trackpoint pt, bool droppedZeroHr, int unknownFields)
        onRecord,
    required void Function(Lap lap, int unknownFields) onLap,
    required void Function(SportType sport, int? calories, int unknownFields)
        onSession,
    required void Function(SportType sport, String? name) onSport,
    required void Function(int? mfg, int? prod, String? prodName) onFileId,
    required void Function(int? mfg, int? prod, String? prodName) onDeviceInfo,
    required void Function(int count) onUnsupportedExtension,
  }) {
    final isCompressed = compressedTimestampSec != null;
    final expectedSize = isCompressed
        ? def.totalByteSizeWithoutField(253)
        : def.totalByteSize;
    if (offset + expectedSize > dataEnd) {
      throw const ActivityParseException(
        'Truncated FIT file: incomplete data message.',
      );
    }

    final values = <int, Object?>{};
    var cursor = offset;
    for (final f in def.fields) {
      if (isCompressed && f.fieldNum == 253) {
        continue;
      }
      final val = _readFieldValue(bytes, bd, cursor, f, def.endian);
      if (val != null) {
        values[f.fieldNum] = val;
      }
      cursor += f.size;
    }

    final devCount = def.devFields.length;
    for (final df in def.devFields) {
      cursor += df.size;
    }

    final tsRaw = (values[253] as int?) ?? compressedTimestampSec;
    if (tsRaw != null && values.containsKey(253)) {
      onTimestamp(tsRaw);
    }

    if (devCount > 0) {
      onUnsupportedExtension(devCount);
    }

    switch (def.globalMsgNum) {
      case _mesgRecord:
        if (tsRaw == null) break;
        final latRaw = values[0] as int?;
        final lonRaw = values[1] as int?;
        final altRaw = values[78] as int? ?? values[2] as int?;
        final hrRaw = values[3] as int?;
        final cadRaw = values[4] as int?;
        final distRaw = values[5] as int?;
        final powerRaw = values[7] as int?;
        final tempRaw = values[13] as int?;

        var droppedZeroHr = false;
        int? hr;
        if (hrRaw != null) {
          if (hrRaw == 0) {
            droppedZeroHr = true;
          } else {
            hr = hrRaw;
          }
        }

        var unknownFields = 0;
        for (final key in values.keys) {
          if (!_knownRecordFields.contains(key)) {
            unknownFields++;
          }
        }

        onRecord(
          Trackpoint(
            timestamp: _fitTimeToDateTime(tsRaw),
            latitude: latRaw != null ? latRaw / _semicirclesPerDegree : null,
            longitude: lonRaw != null ? lonRaw / _semicirclesPerDegree : null,
            elevationMeters: altRaw != null ? (altRaw / 5.0) - 500.0 : null,
            cumulativeDistanceMeters: distRaw != null ? distRaw / 100.0 : null,
            heartRateBpm: hr,
            cadenceRpm: cadRaw,
            powerWatts: powerRaw,
            temperatureCelsius: tempRaw,
          ),
          droppedZeroHr,
          unknownFields,
        );
        break;

      case _mesgLap:
        final endRaw = tsRaw;
        final startRaw = values[2] as int?;
        final elapsedMs = values[7] as int?;
        final distRaw = values[9] as int?;

        DateTime? startTime;
        DateTime? endTime;
        if (startRaw != null) {
          startTime = _fitTimeToDateTime(startRaw);
          if (endRaw != null) {
            endTime = _fitTimeToDateTime(endRaw);
          } else if (elapsedMs != null) {
            endTime = startTime.add(Duration(milliseconds: elapsedMs));
          } else {
            endTime = startTime;
          }
        } else if (endRaw != null) {
          endTime = _fitTimeToDateTime(endRaw);
          startTime = elapsedMs != null
              ? endTime.subtract(Duration(milliseconds: elapsedMs))
              : endTime;
        }

        var unknownFields = 0;
        for (final key in values.keys) {
          if (!_knownLapFields.contains(key)) {
            unknownFields++;
          }
        }

        final avgHr = values[15] as int?;
        final maxHr = values[16] as int?;
        if (startTime != null && endTime != null) {
          onLap(
            Lap(
              startTime: startTime,
              endTime: endTime,
              distanceMeters: distRaw != null ? distRaw / 100.0 : null,
              avgHeartRateBpm: avgHr != null && avgHr > 0 ? avgHr : null,
              maxHeartRateBpm: maxHr != null && maxHr > 0 ? maxHr : null,
            ),
            unknownFields,
          );
        } else if (unknownFields > 0) {
          onUnsupportedExtension(unknownFields);
        }
        break;

      case _mesgSession:
        final sportRaw = values[5] as int?;
        final cals = values[11] as int?;
        var unknownFields = 0;
        for (final key in values.keys) {
          if (!_knownSessionFields.contains(key)) {
            unknownFields++;
          }
        }
        onSession(
          _fitSportToSportType(sportRaw),
          cals,
          unknownFields,
        );
        break;

      case _mesgSport:
        final sportRaw = values[0] as int?;
        final name = values[3] as String?;
        onSport(_fitSportToSportType(sportRaw), name);
        break;

      case _mesgFileId:
        onFileId(
          values[1] as int?,
          values[2] as int?,
          values[8] as String?,
        );
        break;

      case _mesgDeviceInfo:
        onDeviceInfo(
          values[2] as int?,
          values[4] as int?,
          values[27] as String?,
        );
        break;

      case _mesgFieldDescription:
      case _mesgDeveloperDataId:
        onUnsupportedExtension(1);
        break;

      default:
        if (!_knownGlobalMessages.contains(def.globalMsgNum)) {
          onUnsupportedExtension(1);
        }
        break;
    }

    return cursor;
  }

  static Object? _readFieldValue(
    Uint8List bytes,
    ByteData bd,
    int offset,
    _FitFieldDef f,
    Endian endian,
  ) {
    final baseType = f.baseType;
    final size = f.size;

    switch (baseType) {
      case 0x00: // enum
      case 0x02: // uint8
      case 0x0D: // byte
        if (size < 1) return null;
        final v = bytes[offset];
        return v == 0xFF ? null : v;
      case 0x0A: // uint8z
        if (size < 1) return null;
        final v = bytes[offset];
        return v == 0x00 ? null : v;
      case 0x01: // sint8
        if (size < 1) return null;
        final v = bd.getInt8(offset);
        return v == 0x7F ? null : v;
      case 0x83: // sint16
        if (size < 2) return null;
        final v = bd.getInt16(offset, endian);
        return v == 0x7FFF ? null : v;
      case 0x84: // uint16
        if (size < 2) return null;
        final v = bd.getUint16(offset, endian);
        return v == 0xFFFF ? null : v;
      case 0x8B: // uint16z
        if (size < 2) return null;
        final v = bd.getUint16(offset, endian);
        return v == 0x0000 ? null : v;
      case 0x85: // sint32
        if (size < 4) return null;
        final v = bd.getInt32(offset, endian);
        return v == 0x7FFFFFFF ? null : v;
      case 0x86: // uint32
        if (size < 4) return null;
        final v = bd.getUint32(offset, endian);
        return v == 0xFFFFFFFF ? null : v;
      case 0x8C: // uint32z
        if (size < 4) return null;
        final v = bd.getUint32(offset, endian);
        return v == 0x00000000 ? null : v;
      case 0x07: // string
        final slice = bytes.sublist(offset, offset + size);
        final nullIdx = slice.indexOf(0);
        final trimmed = nullIdx >= 0 ? slice.sublist(0, nullIdx) : slice;
        if (trimmed.isEmpty) return null;
        return utf8.decode(trimmed, allowMalformed: true).trim();
      default:
        return null;
    }
  }

  static ExportResult export(Activity activity, ActivityEdit edit) {
    final updated = activity.copyWith(
      title: edit.title ?? activity.title,
      description: edit.description ?? activity.description,
      sportType: edit.sportType ?? activity.sportType,
    );

    final points = _ensureCumulativeDistances(updated.trackpoints);
    final updatedActivity = updated.copyWith(
      trackpoints: points,
      availableChannels: {
        ...updated.availableChannels,
        if (points.any((p) => p.cumulativeDistanceMeters != null))
          Channel.distance,
      },
    );

    final summary = SummaryCalculator.compute(updatedActivity);
    final dataBuilder = BytesBuilder(copy: false);

    final startTime = points.isNotEmpty
        ? points.first.timestamp
        : DateTime.now().toUtc();
    final endTime = points.isNotEmpty ? points.last.timestamp : startTime;
    final startFit = _dateTimeToFitTime(startTime);
    final endFit = _dateTimeToFitTime(endTime);

    final hasDeviceInfo =
        updatedActivity.deviceInfo != null &&
        updatedActivity.deviceInfo!.trim().isNotEmpty;
    final deviceNameBytes = _encodeFixedString(
      updatedActivity.deviceInfo ?? 'Sync-It',
      32,
    );
    final sportNameBytes = _encodeFixedString(updatedActivity.title, 32);

    // 1. file_id (local 0, global 0)
    _writeDefinition(
      dataBuilder,
      localType: 0,
      globalMsgNum: _mesgFileId,
      fields: [
        const _FitFieldDef(0, 1, 0x00), // type = 4 (activity)
        const _FitFieldDef(1, 2, 0x84), // manufacturer
        const _FitFieldDef(2, 2, 0x84), // product
        const _FitFieldDef(3, 4, 0x8C), // serial_number
        const _FitFieldDef(4, 4, 0x86), // time_created
        if (hasDeviceInfo) const _FitFieldDef(8, 32, 0x07), // product_name
      ],
    );
    _writeDataHeader(dataBuilder, localType: 0);
    dataBuilder.addByte(4); // file_type = activity
    _writeUint16(
      dataBuilder,
      _inferManufacturerId(updatedActivity.deviceInfo),
    );
    _writeUint16(dataBuilder, 1); // product
    _writeUint32(dataBuilder, 10001); // serial_number
    _writeUint32(dataBuilder, startFit);
    if (hasDeviceInfo) {
      dataBuilder.add(deviceNameBytes);
    }

    // 2. file_creator (local 1, global 49)
    _writeDefinition(
      dataBuilder,
      localType: 1,
      globalMsgNum: _mesgFileCreator,
      fields: const [
        _FitFieldDef(0, 2, 0x84), // software_version
      ],
    );
    _writeDataHeader(dataBuilder, localType: 1);
    _writeUint16(dataBuilder, 100);

    // 3. device_info (local 2, global 23)
    _writeDefinition(
      dataBuilder,
      localType: 2,
      globalMsgNum: _mesgDeviceInfo,
      fields: [
        const _FitFieldDef(253, 4, 0x86), // timestamp
        const _FitFieldDef(2, 2, 0x84), // manufacturer
        const _FitFieldDef(4, 2, 0x84), // product
        if (hasDeviceInfo) const _FitFieldDef(27, 32, 0x07), // product_name
      ],
    );
    _writeDataHeader(dataBuilder, localType: 2);
    _writeUint32(dataBuilder, startFit);
    _writeUint16(
      dataBuilder,
      _inferManufacturerId(updatedActivity.deviceInfo),
    );
    _writeUint16(dataBuilder, 1);
    if (hasDeviceInfo) {
      dataBuilder.add(deviceNameBytes);
    }

    // 4. sport (local 3, global 12)
    final fitSport = _sportTypeToFitSport(updatedActivity.sportType);
    _writeDefinition(
      dataBuilder,
      localType: 3,
      globalMsgNum: _mesgSport,
      fields: const [
        _FitFieldDef(0, 1, 0x00), // sport
        _FitFieldDef(1, 1, 0x00), // sub_sport
        _FitFieldDef(3, 32, 0x07), // name
      ],
    );
    _writeDataHeader(dataBuilder, localType: 3);
    dataBuilder.addByte(fitSport);
    dataBuilder.addByte(0); // generic sub_sport
    dataBuilder.add(sportNameBytes);

    // 5. record (local 4, global 20)
    _writeDefinition(
      dataBuilder,
      localType: 4,
      globalMsgNum: _mesgRecord,
      fields: const [
        _FitFieldDef(253, 4, 0x86), // timestamp
        _FitFieldDef(0, 4, 0x85), // position_lat
        _FitFieldDef(1, 4, 0x85), // position_long
        _FitFieldDef(2, 2, 0x84), // altitude
        _FitFieldDef(3, 1, 0x02), // heart_rate
        _FitFieldDef(4, 1, 0x02), // cadence
        _FitFieldDef(5, 4, 0x86), // distance
        _FitFieldDef(7, 2, 0x84), // power
        _FitFieldDef(13, 1, 0x01), // temperature
      ],
    );
    for (final pt in points) {
      _writeDataHeader(dataBuilder, localType: 4);
      _writeUint32(dataBuilder, _dateTimeToFitTime(pt.timestamp));
      _writeInt32(
        dataBuilder,
        pt.latitude != null
            ? (pt.latitude! * _semicirclesPerDegree).round()
            : 0x7FFFFFFF,
      );
      _writeInt32(
        dataBuilder,
        pt.longitude != null
            ? (pt.longitude! * _semicirclesPerDegree).round()
            : 0x7FFFFFFF,
      );
      final altEncoded = pt.elevationMeters != null
          ? ((pt.elevationMeters! + 500.0) * 5.0).round().clamp(0, 0xFFFE)
          : 0xFFFF;
      _writeUint16(dataBuilder, altEncoded);
      dataBuilder.addByte(
        pt.heartRateBpm != null ? pt.heartRateBpm!.clamp(0, 254) : 0xFF,
      );
      dataBuilder.addByte(
        pt.cadenceRpm != null ? pt.cadenceRpm!.clamp(0, 254) : 0xFF,
      );
      _writeUint32(
        dataBuilder,
        pt.cumulativeDistanceMeters != null
            ? (pt.cumulativeDistanceMeters! * 100.0).round()
            : 0xFFFFFFFF,
      );
      _writeUint16(
        dataBuilder,
        pt.powerWatts != null ? pt.powerWatts!.clamp(0, 0xFFFE) : 0xFFFF,
      );
      dataBuilder.addByte(
        pt.temperatureCelsius != null
            ? pt.temperatureCelsius!.clamp(-128, 126) & 0xFF
            : 0x7F,
      );
    }

    // 6. lap (local 5, global 19)
    final laps = updatedActivity.laps.isNotEmpty
        ? updatedActivity.laps
        : [
            Lap(
              startTime: startTime,
              endTime: endTime,
              distanceMeters: points.isNotEmpty
                  ? points.last.cumulativeDistanceMeters
                  : 0.0,
            ),
          ];

    _writeDefinition(
      dataBuilder,
      localType: 5,
      globalMsgNum: _mesgLap,
      fields: const [
        _FitFieldDef(253, 4, 0x86), // timestamp (end)
        _FitFieldDef(2, 4, 0x86), // start_time
        _FitFieldDef(7, 4, 0x86), // total_elapsed_time (ms)
        _FitFieldDef(8, 4, 0x86), // total_timer_time (ms)
        _FitFieldDef(9, 4, 0x86), // total_distance (cm)
        _FitFieldDef(11, 2, 0x84), // total_calories
        _FitFieldDef(15, 1, 0x02), // avg_heart_rate
        _FitFieldDef(16, 1, 0x02), // max_heart_rate
        _FitFieldDef(25, 1, 0x00), // sport
      ],
    );

    final totalDurationMs = summary.duration.inMilliseconds;
    for (final lap in laps) {
      final lapElapsedMs = lap.endTime.isAfter(lap.startTime)
          ? lap.endTime.difference(lap.startTime).inMilliseconds
          : 0;
      final lapDistance =
          lap.distanceMeters ?? _computeLapDistance(points, lap);
      final lapCalories = (updatedActivity.calories != null &&
              totalDurationMs > 0)
          ? (updatedActivity.calories! * (lapElapsedMs / totalDurationMs))
              .round()
          : (laps.length == 1 ? updatedActivity.calories : null);

      final lapHr = _computeLapHeartRate(points, lap);

      _writeDataHeader(dataBuilder, localType: 5);
      _writeUint32(dataBuilder, _dateTimeToFitTime(lap.endTime));
      _writeUint32(dataBuilder, _dateTimeToFitTime(lap.startTime));
      _writeUint32(dataBuilder, lapElapsedMs);
      _writeUint32(dataBuilder, lapElapsedMs);
      _writeUint32(dataBuilder, (lapDistance * 100.0).round());
      _writeUint16(dataBuilder, lapCalories ?? 0xFFFF);
      dataBuilder.addByte(lapHr.$1 ?? lap.avgHeartRateBpm ?? 0xFF);
      dataBuilder.addByte(lapHr.$2 ?? lap.maxHeartRateBpm ?? 0xFF);
      dataBuilder.addByte(fitSport);
    }

    // 7. session (local 6, global 18)
    final terminalDistanceMeters = points.isNotEmpty
        ? (points.last.cumulativeDistanceMeters ?? summary.gpsDistanceMeters)
        : 0.0;
    _writeDefinition(
      dataBuilder,
      localType: 6,
      globalMsgNum: _mesgSession,
      fields: const [
        _FitFieldDef(253, 4, 0x86), // timestamp
        _FitFieldDef(2, 4, 0x86), // start_time
        _FitFieldDef(5, 1, 0x00), // sport
        _FitFieldDef(6, 1, 0x00), // sub_sport
        _FitFieldDef(7, 4, 0x86), // total_elapsed_time (ms)
        _FitFieldDef(8, 4, 0x86), // total_timer_time (ms)
        _FitFieldDef(9, 4, 0x86), // total_distance (cm)
        _FitFieldDef(11, 2, 0x84), // total_calories
        _FitFieldDef(16, 1, 0x02), // avg_heart_rate
        _FitFieldDef(17, 1, 0x02), // max_heart_rate
        _FitFieldDef(22, 2, 0x84), // total_ascent (m)
        _FitFieldDef(25, 2, 0x84), // first_lap_index
        _FitFieldDef(26, 2, 0x84), // num_laps
      ],
    );
    _writeDataHeader(dataBuilder, localType: 6);
    _writeUint32(dataBuilder, endFit);
    _writeUint32(dataBuilder, startFit);
    dataBuilder.addByte(fitSport);
    dataBuilder.addByte(0); // generic sub_sport
    _writeUint32(dataBuilder, totalDurationMs);
    _writeUint32(dataBuilder, totalDurationMs);
    _writeUint32(dataBuilder, (terminalDistanceMeters * 100.0).round());
    _writeUint16(dataBuilder, updatedActivity.calories ?? 0xFFFF);
    dataBuilder.addByte(summary.avgHeartRateBpm ?? 0xFF);
    dataBuilder.addByte(summary.maxHeartRateBpm ?? 0xFF);
    _writeUint16(dataBuilder, summary.elevationGainMeters.round());
    _writeUint16(dataBuilder, 0); // first_lap_index
    _writeUint16(dataBuilder, laps.length);

    // 8. activity (local 7, global 34)
    _writeDefinition(
      dataBuilder,
      localType: 7,
      globalMsgNum: _mesgActivity,
      fields: const [
        _FitFieldDef(253, 4, 0x86), // timestamp
        _FitFieldDef(0, 4, 0x86), // total_timer_time (ms)
        _FitFieldDef(1, 2, 0x84), // num_sessions
        _FitFieldDef(2, 1, 0x00), // type (0 = manual)
        _FitFieldDef(3, 1, 0x00), // event (26 = activity)
        _FitFieldDef(4, 1, 0x00), // event_type (1 = stop)
      ],
    );
    _writeDataHeader(dataBuilder, localType: 7);
    _writeUint32(dataBuilder, endFit);
    _writeUint32(dataBuilder, totalDurationMs);
    _writeUint16(dataBuilder, 1);
    dataBuilder.addByte(0);
    dataBuilder.addByte(26);
    dataBuilder.addByte(1);

    final dataBytes = dataBuilder.toBytes();
    final totalBytes = Uint8List(14 + dataBytes.length + 2);
    final headerBd = ByteData.sublistView(totalBytes);

    totalBytes[0] = 14; // header size
    totalBytes[1] = 0x20; // protocol 2.0
    headerBd.setUint16(2, 2132, Endian.little); // profile version 21.32
    headerBd.setUint32(4, dataBytes.length, Endian.little);
    totalBytes[8] = 0x2E; // '.'
    totalBytes[9] = 0x46; // 'F'
    totalBytes[10] = 0x49; // 'I'
    totalBytes[11] = 0x54; // 'T'
    final headerCrc = computeCrc(totalBytes, 0, 12);
    headerBd.setUint16(12, headerCrc, Endian.little);

    totalBytes.setRange(14, 14 + dataBytes.length, dataBytes);
    final fileCrc = computeCrc(totalBytes, 0, 14 + dataBytes.length);
    headerBd.setUint16(14 + dataBytes.length, fileCrc, Endian.little);

    return ExportResult(
      bytes: totalBytes,
      activity: updatedActivity,
      summary: summary,
      diagnostics: const [],
    );
  }

  static List<Trackpoint> _ensureCumulativeDistances(
    List<Trackpoint> points,
  ) {
    if (points.isEmpty) return points;
    if (points.every((p) => p.cumulativeDistanceMeters != null)) {
      return points;
    }

    final result = <Trackpoint>[];
    var cumulative = 0.0;
    Trackpoint? prevGps;

    for (final pt in points) {
      if (pt.latitude != null && pt.longitude != null) {
        if (prevGps != null) {
          cumulative += SummaryCalculator.haversineMeters(
            prevGps.latitude!,
            prevGps.longitude!,
            pt.latitude!,
            pt.longitude!,
          );
        }
        prevGps = pt;
      }

      final effectiveDist = pt.cumulativeDistanceMeters ?? cumulative;
      if (pt.cumulativeDistanceMeters != null) {
        cumulative = math.max(cumulative, pt.cumulativeDistanceMeters!);
      }

      result.add(
        Trackpoint(
          timestamp: pt.timestamp,
          latitude: pt.latitude,
          longitude: pt.longitude,
          elevationMeters: pt.elevationMeters,
          cumulativeDistanceMeters: effectiveDist,
          heartRateBpm: pt.heartRateBpm,
          cadenceRpm: pt.cadenceRpm,
          powerWatts: pt.powerWatts,
          temperatureCelsius: pt.temperatureCelsius,
        ),
      );
    }
    return result;
  }

  static double _computeLapDistance(List<Trackpoint> points, Lap lap) {
    Trackpoint? first;
    Trackpoint? last;
    for (final pt in points) {
      if (!pt.timestamp.isBefore(lap.startTime) &&
          !pt.timestamp.isAfter(lap.endTime)) {
        first ??= pt;
        last = pt;
      }
    }
    if (first == null || last == null) return 0.0;
    final d1 = first.cumulativeDistanceMeters ?? 0.0;
    final d2 = last.cumulativeDistanceMeters ?? d1;
    return math.max(0.0, d2 - d1);
  }

  static (int?, int?) _computeLapHeartRate(List<Trackpoint> points, Lap lap) {
    var sum = 0;
    var count = 0;
    var maxHr = 0;
    for (final pt in points) {
      if (pt.timestamp.isBefore(lap.startTime) ||
          pt.timestamp.isAfter(lap.endTime)) {
        continue;
      }
      final hr = pt.heartRateBpm;
      if (hr != null && hr > 0) {
        sum += hr;
        count++;
        if (hr > maxHr) maxHr = hr;
      }
    }
    if (count == 0) return (null, null);
    return ((sum / count).round(), maxHr);
  }

  static Trackpoint _mergeDuplicateTrackpoints(
    Trackpoint prev,
    Trackpoint next,
  ) {
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

  static DateTime _fitTimeToDateTime(int fitSeconds) {
    return DateTime.fromMillisecondsSinceEpoch(
      (fitSeconds + _fitEpochUnixSeconds) * 1000,
      isUtc: true,
    );
  }

  static int _dateTimeToFitTime(DateTime dt) {
    return (dt.toUtc().millisecondsSinceEpoch ~/ 1000) - _fitEpochUnixSeconds;
  }

  static SportType _fitSportToSportType(int? sport) {
    switch (sport) {
      case 1:
        return SportType.running;
      case 2:
        return SportType.cycling;
      case 5:
        return SportType.swimming;
      case 11:
        return SportType.walking;
      case 17:
        return SportType.hiking;
      default:
        return SportType.other;
    }
  }

  static int _sportTypeToFitSport(SportType sport) {
    switch (sport) {
      case SportType.running:
        return 1;
      case SportType.cycling:
        return 2;
      case SportType.swimming:
        return 5;
      case SportType.walking:
        return 11;
      case SportType.hiking:
        return 17;
      case SportType.other:
        return 0;
    }
  }

  static String? _formatDeviceInfo(
    String? productName,
    int? manufacturerId,
    int? productId,
  ) {
    final mfgName = _manufacturerName(manufacturerId);
    if (productName != null && productName.isNotEmpty) {
      if (mfgName != null &&
          !productName.toLowerCase().contains(mfgName.toLowerCase())) {
        return '$mfgName $productName';
      }
      return productName;
    }
    if (mfgName != null) {
      return productId != null ? '$mfgName (#$productId)' : mfgName;
    }
    if (manufacturerId != null) {
      return 'Device ($manufacturerId${productId != null ? ':#$productId' : ''})';
    }
    return null;
  }

  static String? _manufacturerName(int? id) {
    switch (id) {
      case 1:
        return 'Garmin';
      case 15:
        return 'Dynastream';
      case 32:
        return 'Wahoo';
      case 89:
        return 'Tacx';
      case 260:
        return 'Zwift';
      case 267:
        return 'Bryton';
      case 281:
        return 'Hammerhead';
      case 294:
        return 'COROS';
      default:
        return null;
    }
  }

  static int _inferManufacturerId(String? deviceInfo) {
    if (deviceInfo == null) return 255;
    final lower = deviceInfo.toLowerCase();
    if (lower.contains('garmin')) return 1;
    if (lower.contains('wahoo')) return 32;
    if (lower.contains('coros')) return 294;
    if (lower.contains('hammerhead')) return 281;
    if (lower.contains('zwift')) return 260;
    if (lower.contains('bryton')) return 267;
    return 255;
  }

  static String _fallbackTitle(String? fileName, SportType sport) {
    if (fileName != null && fileName.trim().isNotEmpty) {
      final base = fileName
          .trim()
          .replaceAll(RegExp(r'\.fit$', caseSensitive: false), '');
      if (base.isNotEmpty) return base;
    }
    return '${sport.displayName} Activity';
  }

  static Uint8List _encodeFixedString(String value, int length) {
    final out = Uint8List(length);
    final encoded = utf8.encode(value);
    final copyLen = math.min(encoded.length, length - 1);
    out.setRange(0, copyLen, encoded);
    return out;
  }

  static void _writeDefinition(
    BytesBuilder builder, {
    required int localType,
    required int globalMsgNum,
    required List<_FitFieldDef> fields,
  }) {
    builder.addByte(0x40 | (localType & 0x0F));
    builder.addByte(0); // reserved
    builder.addByte(0); // little-endian
    _writeUint16(builder, globalMsgNum);
    builder.addByte(fields.length);
    for (final f in fields) {
      builder.addByte(f.fieldNum);
      builder.addByte(f.size);
      builder.addByte(f.baseType);
    }
  }

  static void _writeDataHeader(BytesBuilder builder, {required int localType}) {
    builder.addByte(localType & 0x0F);
  }

  static void _writeUint16(BytesBuilder builder, int value) {
    builder.addByte(value & 0xFF);
    builder.addByte((value >> 8) & 0xFF);
  }

  static void _writeUint32(BytesBuilder builder, int value) {
    builder.addByte(value & 0xFF);
    builder.addByte((value >> 8) & 0xFF);
    builder.addByte((value >> 16) & 0xFF);
    builder.addByte((value >> 24) & 0xFF);
  }

  static void _writeInt32(BytesBuilder builder, int value) {
    _writeUint32(builder, value & 0xFFFFFFFF);
  }
}

class _FitFieldDef {
  const _FitFieldDef(this.fieldNum, this.size, this.baseType);

  final int fieldNum;
  final int size;
  final int baseType;
}

class _FitDevFieldDef {
  const _FitDevFieldDef(this.fieldNum, this.size, this.devIndex);

  final int fieldNum;
  final int size;
  final int devIndex;
}

class _FitMessageDef {
  const _FitMessageDef({
    required this.globalMsgNum,
    required this.endian,
    required this.fields,
    required this.devFields,
  });

  final int globalMsgNum;
  final Endian endian;
  final List<_FitFieldDef> fields;
  final List<_FitDevFieldDef> devFields;

  int get totalByteSize {
    var total = 0;
    for (final f in fields) {
      total += f.size;
    }
    for (final df in devFields) {
      total += df.size;
    }
    return total;
  }

  int totalByteSizeWithoutField(int fieldNum) {
    var total = 0;
    for (final f in fields) {
      if (f.fieldNum != fieldNum) total += f.size;
    }
    for (final df in devFields) {
      total += df.size;
    }
    return total;
  }
}
