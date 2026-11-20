import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'platform_io_port.dart';

/// Production [PlatformIoPort] backed by file_picker, path_provider, and share_plus.
class DevicePlatformIoPort implements PlatformIoPort {
  const DevicePlatformIoPort();

  @override
  Future<PickedSourceFile?> pickSourceFile() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['gpx', 'tcx', 'fit'],
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    return PickedSourceFile(
      fileName: file.name,
      bytes: bytes,
    );
  }

  @override
  Future<List<PickedSourceFile>> pickMultipleSourceFiles() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['gpx', 'tcx', 'fit'],
    );
    if (files.isEmpty) return const [];
    final picked = <PickedSourceFile>[];
    for (final file in files) {
      final bytes = await file.readAsBytes();
      picked.add(
        PickedSourceFile(
          fileName: file.name,
          bytes: bytes,
        ),
      );
    }
    return picked;
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
      mimeType: _mimeTypeForFileName(suggestedFileName),
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
        files: [
          XFile(tempFile.path, mimeType: _mimeTypeForFileName(fileName)),
        ],
        subject: fileName,
      ),
    );
  }

  @override
  Future<bool> isMapTilesAvailable() async {
    try {
      final result = await InternetAddress.lookup('tile.openstreetmap.org')
          .timeout(const Duration(seconds: 2));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> copyToClipboard(String text) {
    return Clipboard.setData(ClipboardData(text: text));
  }

  @override
  Future<bool> launchExternalUrl(Uri url) {
    return launchUrl(url, mode: LaunchMode.externalApplication);
  }

  static String _mimeTypeForFileName(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.fit')) {
      return 'application/octet-stream';
    }
    if (lower.endsWith('.tcx')) {
      return 'application/vnd.garmin.tcx+xml';
    }
    return 'application/gpx+xml';
  }
}
