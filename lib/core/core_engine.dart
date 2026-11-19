import 'dart:isolate';
import 'dart:typed_data';

import 'fit_codec.dart';
import 'gpx_codec.dart';
import 'models.dart';

export 'models.dart';

/// Pure-Dart Core Engine Seam (zero Flutter imports).
class CoreEngine {
  const CoreEngine._();

  /// Parses GPX [bytes] into a canonical [Activity], [ActivitySummary], and
  /// defensive-parsing [Diagnostic]s.
  static ParseResult parseGpx(Uint8List bytes, {String? fileName}) {
    return GpxCodec.parse(bytes, fileName: fileName);
  }

  /// Parses binary FIT [bytes] into a canonical [Activity], [ActivitySummary],
  /// and defensive-parsing [Diagnostic]s.
  static ParseResult parseFit(Uint8List bytes, {String? fileName}) {
    return FitCodec.parse(bytes, fileName: fileName);
  }

  /// Applies [edit] to [activity] and serializes a clean GPX Export File.
  static ExportResult exportGpx(Activity activity, ActivityEdit edit) {
    return GpxCodec.export(activity, edit);
  }

  /// Applies [edit] to [activity] and serializes a clean binary FIT Export File.
  static ExportResult exportFit(Activity activity, ActivityEdit edit) {
    return FitCodec.export(activity, edit);
  }

  /// Runs [parseGpx] in a background Dart isolate.
  static Future<ParseResult> parseGpxInIsolate(
    Uint8List bytes, {
    String? fileName,
  }) {
    return Isolate.run(() => parseGpx(bytes, fileName: fileName));
  }

  /// Runs [parseFit] in a background Dart isolate.
  static Future<ParseResult> parseFitInIsolate(
    Uint8List bytes, {
    String? fileName,
  }) {
    return Isolate.run(() => parseFit(bytes, fileName: fileName));
  }

  /// Runs [exportGpx] in a background Dart isolate.
  static Future<ExportResult> exportGpxInIsolate(
    Activity activity,
    ActivityEdit edit,
  ) {
    return Isolate.run(() => exportGpx(activity, edit));
  }

  /// Runs [exportFit] in a background Dart isolate.
  static Future<ExportResult> exportFitInIsolate(
    Activity activity,
    ActivityEdit edit,
  ) {
    return Isolate.run(() => exportFit(activity, edit));
  }
}
