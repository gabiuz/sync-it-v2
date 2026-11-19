import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'platform_io_port.dart';

/// Production [PlatformIoPort] backed by file_picker, path_provider, and share_plus.
class DevicePlatformIoPort implements PlatformIoPort {
  const DevicePlatformIoPort();

  @override
  Future<PickedSourceFile?> pickSourceFile() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['gpx'],
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    return PickedSourceFile(
      fileName: file.name,
      bytes: bytes,
    );
  }

  @override
  Future<bool> saveExportFile({
    required String suggestedFileName,
    required Uint8List bytes,
  }) async {
    final savedUri = await FilePicker.saveFile(
      dialogTitle: 'Save Export File',
      fileName: suggestedFileName,
      bytes: bytes,
      mimeType: 'application/gpx+xml',
    );
    return savedUri != null;
  }

  @override
  Future<void> shareExportFile({
    required String fileName,
    required Uint8List bytes,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final tempFile = File('${tempDir.path}${Platform.pathSeparator}$fileName');
    await tempFile.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(tempFile.path, mimeType: 'application/gpx+xml')],
        subject: fileName,
      ),
    );
  }
}
