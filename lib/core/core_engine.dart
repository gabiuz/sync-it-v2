import 'dart:isolate';
import 'dart:typed_data';

import 'channel_blender.dart';
import 'display_geometry.dart';
import 'fit_codec.dart';
import 'gpx_codec.dart';
import 'models.dart';
import 'sequential_stitcher.dart';
import 'summary_calculator.dart';
import 'tcx_codec.dart';

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

  /// Parses TCX [bytes] into a canonical [Activity], [ActivitySummary], and
  /// defensive-parsing [Diagnostic]s.
  static ParseResult parseTcx(Uint8List bytes, {String? fileName}) {
    return TcxCodec.parse(bytes, fileName: fileName);
  }

  /// Applies [edit] to [activity] and serializes a clean GPX Export File.
  static ExportResult exportGpx(Activity activity, ActivityEdit edit) {
    return GpxCodec.export(activity, edit);
  }

  /// Applies [edit] to [activity] and serializes a clean binary FIT Export File.
  static ExportResult exportFit(Activity activity, ActivityEdit edit) {
    return FitCodec.export(activity, edit);
  }

  /// Applies [edit] to [activity] and serializes a clean TCX Export File.
  static ExportResult exportTcx(Activity activity, ActivityEdit edit) {
    return TcxCodec.export(activity, edit);
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

  /// Runs [parseTcx] in a background Dart isolate.
  static Future<ParseResult> parseTcxInIsolate(
    Uint8List bytes, {
    String? fileName,
  }) {
    return Isolate.run(() => parseTcx(bytes, fileName: fileName));
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

  /// Runs [exportTcx] in a background Dart isolate.
  static Future<ExportResult> exportTcxInIsolate(
    Activity activity,
    ActivityEdit edit,
  ) {
    return Isolate.run(() => exportTcx(activity, edit));
  }

  /// Builds downsampled display geometry for map and Channel charts without
  /// mutating canonical [Activity.trackpoints].
  static ActivityDisplayGeometry buildDisplayGeometry(
    Activity activity, {
    int maxPoints = DisplayGeometryBuilder.defaultMaxPoints,
  }) {
    return DisplayGeometryBuilder.build(activity, maxPoints: maxPoints);
  }

  /// Runs [buildDisplayGeometry] in a background Dart isolate.
  static Future<ActivityDisplayGeometry> buildDisplayGeometryInIsolate(
    Activity activity, {
    int maxPoints = DisplayGeometryBuilder.defaultMaxPoints,
  }) {
    return Isolate.run(
      () => buildDisplayGeometry(activity, maxPoints: maxPoints),
    );
  }

  /// Computes Strava Tax and floor-truncation diagnostics for [activity].
  static DistanceDiagnostics analyzeDistance(
    Activity activity, {
    required bool isImperial,
    double? distanceOverrideMeters,
  }) {
    return SummaryCalculator.analyzeDistance(
      activity,
      isImperial: isImperial,
      distanceOverrideMeters: distanceOverrideMeters,
    );
  }

  /// Proportionally scales cumulative distance across [activity]'s
  /// trackpoints and recomputes all [Lap] distances without mutating [activity].
  static Activity applyDistanceOverride(
    Activity activity,
    double? targetDistanceMeters,
  ) {
    return SummaryCalculator.applyDistanceOverride(
      activity,
      targetDistanceMeters,
    );
  }

  /// Evaluates format-specific lossy-export and blocking warnings for
  /// [activity] with [edit] applied under [format].
  static List<ExportWarning> analyzeExportWarnings(
    Activity activity,
    ActivityEdit edit,
    ExportFormat format,
  ) {
    return SummaryCalculator.analyzeExportWarnings(activity, edit, format);
  }

  /// Builds a default [BlendConfiguration] from [sources], defaulting
  /// metadata and present Channels to [baseSourceId] (or the first source) and
  /// filling missing Channels from the first source that supplies them.
  static BlendConfiguration defaultBlendConfiguration(
    List<BlendSource> sources, {
    String? baseSourceId,
  }) {
    return ChannelBlender.defaultConfiguration(
      sources,
      baseSourceId: baseSourceId,
    );
  }

  /// Blends [sources] according to [config] on the Base Timeline, aligning
  /// secondary Channels via ±5s linear interpolation and recomputing summaries.
  static ParseResult blendActivities(
    List<BlendSource> sources,
    BlendConfiguration config,
  ) {
    return ChannelBlender.blend(sources, config);
  }

  /// Runs [blendActivities] in a background Dart isolate.
  static Future<ParseResult> blendActivitiesInIsolate(
    List<BlendSource> sources,
    BlendConfiguration config,
  ) {
    return Isolate.run(() => blendActivities(sources, config));
  }

  /// Concatenates 2 or more [sources] chronologically into one continuous
  /// [Activity] with continuous cumulative distance, Channel unions, Lap
  /// boundaries, optional gap removal, and overlap head-trimming.
  static StitchResult stitchActivities(
    List<StitchSource> sources, [
    StitchConfiguration config = const StitchConfiguration(),
  ]) {
    return SequentialStitcher.stitch(sources, config);
  }

  /// Runs [stitchActivities] in a background Dart isolate.
  static Future<StitchResult> stitchActivitiesInIsolate(
    List<StitchSource> sources, [
    StitchConfiguration config = const StitchConfiguration(),
  ]) {
    return Isolate.run(() => stitchActivities(sources, config));
  }
}
