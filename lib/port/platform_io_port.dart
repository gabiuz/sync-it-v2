import 'dart:typed_data';

/// A Source File selected by the user from the platform file picker.
class PickedSourceFile {
  const PickedSourceFile({
    required this.fileName,
    required this.bytes,
  });

  final String fileName;
  final Uint8List bytes;
}

/// A batch of Source Files or read errors delivered by an OS Open-With /
/// Share-To intent.
class IncomingSourceBatch {
  const IncomingSourceBatch({
    this.files = const [],
    this.errors = const [],
  });

  final List<PickedSourceFile> files;
  final List<String> errors;

  bool get isEmpty => files.isEmpty && errors.isEmpty;
}

/// Single outer Platform-I/O port for the Flutter App Shell.
abstract interface class PlatformIoPort {
  Future<PickedSourceFile?> pickSourceFile();

  Future<List<PickedSourceFile>> pickMultipleSourceFiles();

  Future<bool> saveExportFile({
    required String suggestedFileName,
    required Uint8List bytes,
  });

  Future<void> shareExportFile({
    required String fileName,
    required Uint8List bytes,
  });

  /// Returns whether online OpenStreetMap tiles are reachable.
  Future<bool> isMapTilesAvailable();

  /// Copies [text] to the system clipboard.
  Future<void> copyToClipboard(String text);

  /// Launches [url] in an external browser or app.
  Future<bool> launchExternalUrl(Uri url);

  /// Consumes any initial Source Files delivered when the app was cold-launched
  /// via an OS Open-With or Share-To intent, or null if launched normally.
  Future<IncomingSourceBatch?> consumeInitialIncomingSources();

  /// Stream of Source File batches delivered while the app is already running.
  Stream<IncomingSourceBatch> get incomingSourceBatches;
}
