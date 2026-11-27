import 'dart:convert';
import 'dart:typed_data';

import 'package:xml/xml.dart';

import 'models.dart';

/// Shared XML parsing, traversal, and Trackpoint normalization helpers for
/// XML-based activity codecs ([GpxCodec] and [KmlCodec]).
class XmlTrackCodecHelpers {
  const XmlTrackCodecHelpers._();

  /// Decodes UTF-8 [bytes], parses XML, and verifies the root element
  /// matches [expectedRootLocalName], throwing [ActivityParseException] with
  /// actionable [formatLabel] messages on failure.
  static XmlDocument parseXmlDocument(
    Uint8List bytes, {
    required String formatLabel,
    required String expectedRootLocalName,
  }) {
    if (bytes.isEmpty) {
      throw ActivityParseException(
        'The selected $formatLabel file is empty. Choose a valid $formatLabel activity file.',
      );
    }

    final String xmlString;
    try {
      xmlString = utf8.decode(bytes);
    } on FormatException {
      throw ActivityParseException(
        'Could not read the file as UTF-8 text. Ensure the file is a valid $formatLabel XML file.',
      );
    }

    final XmlDocument document;
    try {
      document = XmlDocument.parse(xmlString);
    } on XmlException catch (e) {
      throw ActivityParseException(
        'Corrupted $formatLabel XML file: ${e.message}. Export a fresh $formatLabel file from your watch or app and try again.',
      );
    }

    final root = document.rootElement;
    if (root.localName != expectedRootLocalName) {
      throw ActivityParseException(
        'Expected a <$expectedRootLocalName> root element, found <${root.localName}>. Select a valid $formatLabel file.',
      );
    }

    return document;
  }

  static XmlElement? firstChildByLocalName(XmlElement parent, String name) {
    for (final child in parent.childElements) {
      if (child.localName == name) return child;
    }
    return null;
  }

  static Iterable<XmlElement> childrenByLocalName(
    XmlElement parent,
    String name,
  ) {
    return parent.childElements.where((c) => c.localName == name);
  }

  static String? childText(XmlElement parent, String localName) {
    final child = firstChildByLocalName(parent, localName);
    if (child == null) return null;
    final text = child.innerText.trim();
    return text.isEmpty ? null : text;
  }

  static String fallbackTitle(String? fileName) {
    if (fileName == null || fileName.trim().isEmpty) return 'Untitled Activity';
    final dot = fileName.lastIndexOf('.');
    return dot > 0 ? fileName.substring(0, dot) : fileName;
  }

  /// Chronologically sorts [rawPoints], merges adjacent duplicate timestamps,
  /// and records normalization/dropout/extension [Diagnostic]s.
  static List<Trackpoint> normalizeTrackpoints(
    List<Trackpoint> rawPoints, {
    required List<Diagnostic> diagnostics,
    required int zeroHrCount,
    required int unsupportedExtensionCount,
  }) {
    final tagged = [for (final pt in rawPoints) (tag: 0, point: pt)];
    final normalized = normalizeTaggedTrackpoints<int>(
      tagged,
      diagnostics: diagnostics,
      zeroHrCount: zeroHrCount,
      unsupportedExtensionCount: unsupportedExtensionCount,
    );
    return [for (final entry in normalized) entry.point];
  }

  /// Tag-preserving variant of [normalizeTrackpoints] for codecs that track
  /// per-track grouping alongside each [Trackpoint].
  static List<({T tag, Trackpoint point})> normalizeTaggedTrackpoints<T>(
    List<({T tag, Trackpoint point})> rawPoints, {
    required List<Diagnostic> diagnostics,
    required int zeroHrCount,
    required int unsupportedExtensionCount,
  }) {
    var outOfOrderCount = 0;
    for (var i = 1; i < rawPoints.length; i++) {
      if (rawPoints[i].point.timestamp.isBefore(rawPoints[i - 1].point.timestamp)) {
        outOfOrderCount++;
      }
    }

    final indexed = rawPoints.asMap().entries.toList();
    if (outOfOrderCount > 0) {
      indexed.sort((a, b) {
        final cmp = a.value.point.timestamp.compareTo(b.value.point.timestamp);
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
    final normalizedEntries = <({T tag, Trackpoint point})>[];
    var duplicateCount = 0;
    for (final entry in indexed) {
      final item = entry.value;
      if (normalizedEntries.isNotEmpty &&
          normalizedEntries.last.point.timestamp == item.point.timestamp) {
        duplicateCount++;
        final prev = normalizedEntries.removeLast();
        normalizedEntries.add((
          tag: item.tag,
          point: mergeDuplicateTrackpoints(prev.point, item.point),
        ));
      } else {
        normalizedEntries.add(item);
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

    return normalizedEntries;
  }

  static Trackpoint mergeDuplicateTrackpoints(
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

  static Set<Channel> detectAvailableChannels(List<Trackpoint> points) {
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
}
