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

/// Single outer Platform-I/O port for the Flutter App Shell.
abstract interface class PlatformIoPort {
  Future<PickedSourceFile?> pickSourceFile();

  Future<bool> saveExportFile({
    required String suggestedFileName,
    required Uint8List bytes,
  });

  Future<void> shareExportFile({
    required String fileName,
    required Uint8List bytes,
  });
}
