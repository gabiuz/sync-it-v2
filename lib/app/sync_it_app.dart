import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/core_engine.dart';
import '../port/device_platform_io_port.dart';
import '../port/platform_io_port.dart';
import 'activity_formatters.dart';
import 'start_screen.dart';
import 'workbench_screen.dart';

class SyncItApp extends StatefulWidget {
  const SyncItApp({
    super.key,
    this.platformIoPort,
  });

  final PlatformIoPort? platformIoPort;

  @override
  State<SyncItApp> createState() => _SyncItAppState();
}

class _SyncItAppState extends State<SyncItApp> {
  UnitSystem _unitSystem = UnitSystem.metric;
  ThemeMode _themeMode = ThemeMode.system;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sync-It',
      themeMode: _themeMode,
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
        platformIoPort: widget.platformIoPort ?? const DevicePlatformIoPort(),
        unitSystem: _unitSystem,
        themeMode: _themeMode,
        onUnitSystemChanged: (units) => setState(() => _unitSystem = units),
        onThemeModeChanged: (mode) => setState(() => _themeMode = mode),
      ),
    );
  }
}

class _SyncItShell extends StatefulWidget {
  const _SyncItShell({
    required this.platformIoPort,
    required this.unitSystem,
    required this.themeMode,
    required this.onUnitSystemChanged,
    required this.onThemeModeChanged,
  });

  final PlatformIoPort platformIoPort;
  final UnitSystem unitSystem;
  final ThemeMode themeMode;
  final ValueChanged<UnitSystem> onUnitSystemChanged;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  @override
  State<_SyncItShell> createState() => _SyncItShellState();
}

class _SyncItShellState extends State<_SyncItShell> {
  ParseResult? _parseResult;
  String? _sourceFileName;
  List<BlendSource>? _blendSources;
  BlendConfiguration? _blendConfig;
  bool _isLoading = false;
  String? _errorMessage;

  Future<ParseResult> _parsePickedFile(PickedSourceFile picked) {
    if (_isFitSource(picked.fileName, picked.bytes)) {
      return CoreEngine.parseFitInIsolate(
        picked.bytes,
        fileName: picked.fileName,
      );
    }
    if (_isTcxSource(picked.fileName, picked.bytes)) {
      return CoreEngine.parseTcxInIsolate(
        picked.bytes,
        fileName: picked.fileName,
      );
    }
    return CoreEngine.parseGpxInIsolate(
      picked.bytes,
      fileName: picked.fileName,
    );
  }

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

      final result = await _parsePickedFile(picked);
      if (!mounted) return;
      setState(() {
        _parseResult = result;
        _sourceFileName = picked.fileName;
        _blendSources = null;
        _blendConfig = null;
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
        _errorMessage = 'Failed to import Source File: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _importBlendSources() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final pickedList = await widget.platformIoPort.pickMultipleSourceFiles();
      if (pickedList.isEmpty) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      if (pickedList.length < 2) {
        if (!mounted) return;
        setState(() {
          _errorMessage = 'Select 2 or more Source Files to blend channels.';
          _isLoading = false;
        });
        return;
      }

      final parsedList = await Future.wait(
        pickedList.map(_parsePickedFile),
      );
      final sources = <BlendSource>[
        for (var i = 0; i < pickedList.length; i++)
          BlendSource(
            id: 'source-$i',
            fileName: pickedList[i].fileName,
            activity: parsedList[i].activity,
            diagnostics: parsedList[i].diagnostics,
          ),
      ];
      final config = CoreEngine.defaultBlendConfiguration(sources);
      final blended = await CoreEngine.blendActivitiesInIsolate(sources, config);
      if (!mounted) return;
      setState(() {
        _parseResult = blended;
        _sourceFileName = '${sources.length} Blended Files';
        _blendSources = sources;
        _blendConfig = config;
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
        _errorMessage = 'Failed to blend Source Files: $e';
        _isLoading = false;
      });
    }
  }

  static bool _isFitSource(String fileName, List<int> bytes) {
    if (fileName.toLowerCase().endsWith('.fit')) return true;
    return bytes.length >= 12 &&
        bytes[8] == 0x2E &&
        bytes[9] == 0x46 &&
        bytes[10] == 0x49 &&
        bytes[11] == 0x54;
  }

  static bool _isTcxSource(String fileName, List<int> bytes) {
    if (fileName.toLowerCase().endsWith('.tcx')) return true;
    final prefixLen = bytes.length < 512 ? bytes.length : 512;
    final head = utf8.decode(bytes.sublist(0, prefixLen), allowMalformed: true);
    return head.contains('<TrainingCenterDatabase');
  }

  @override
  Widget build(BuildContext context) {
    final result = _parseResult;
    if (result == null) {
      return StartScreen(
        onImportTap: _importSourceFile,
        onBlendTap: _importBlendSources,
        isLoading: _isLoading,
        errorMessage: _errorMessage,
      );
    }

    return WorkbenchScreen(
      initialResult: result,
      sourceFileName: _sourceFileName ?? 'activity.gpx',
      blendSources: _blendSources,
      initialBlendConfig: _blendConfig,
      platformIoPort: widget.platformIoPort,
      unitSystem: widget.unitSystem,
      themeMode: widget.themeMode,
      onUnitSystemChanged: widget.onUnitSystemChanged,
      onThemeModeChanged: widget.onThemeModeChanged,
      onClose: () => setState(() {
        _parseResult = null;
        _sourceFileName = null;
        _blendSources = null;
        _blendConfig = null;
        _errorMessage = null;
      }),
    );
  }
}
