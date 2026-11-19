import 'package:flutter/material.dart';

import '../core/core_engine.dart';
import '../port/device_platform_io_port.dart';
import '../port/platform_io_port.dart';
import 'start_screen.dart';
import 'workbench_screen.dart';

class SyncItApp extends StatelessWidget {
  const SyncItApp({
    super.key,
    this.platformIoPort,
  });

  final PlatformIoPort? platformIoPort;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sync-It',
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.deepOrange,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.deepOrange,
        brightness: Brightness.dark,
      ),
      home: _SyncItShell(
        platformIoPort: platformIoPort ?? const DevicePlatformIoPort(),
      ),
    );
  }
}

class _SyncItShell extends StatefulWidget {
  const _SyncItShell({required this.platformIoPort});

  final PlatformIoPort platformIoPort;

  @override
  State<_SyncItShell> createState() => _SyncItShellState();
}

class _SyncItShellState extends State<_SyncItShell> {
  ParseResult? _parseResult;
  String? _sourceFileName;
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _importSourceFile() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final picked = await widget.platformIoPort.pickSourceFile();
      if (picked == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final result = await CoreEngine.parseGpxInIsolate(
        picked.bytes,
        fileName: picked.fileName,
      );
      if (!mounted) return;
      setState(() {
        _parseResult = result;
        _sourceFileName = picked.fileName;
        _isLoading = false;
      });
    } on ActivityParseException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.message;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to import GPX file: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _parseResult;
    if (result == null) {
      return StartScreen(
        onImportTap: _importSourceFile,
        isLoading: _isLoading,
        errorMessage: _errorMessage,
      );
    }

    return WorkbenchScreen(
      initialResult: result,
      sourceFileName: _sourceFileName ?? 'activity.gpx',
      platformIoPort: widget.platformIoPort,
      onClose: () => setState(() {
        _parseResult = null;
        _sourceFileName = null;
        _errorMessage = null;
      }),
    );
  }
}
