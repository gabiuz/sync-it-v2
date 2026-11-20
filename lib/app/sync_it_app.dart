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
  List<StitchSource>? _stitchSources;
  List<StitchedPartInfo>? _stitchParts;
  StitchConfiguration? _stitchConfig;
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
        _stitchSources = null;
        _stitchParts = null;
        _stitchConfig = null;
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

  Future<List<({PickedSourceFile file, ParseResult parsed})>?>
      _pickAndParseMultipleSources({
    required String minCountError,
    required String failureAction,
  }) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final pickedList = await widget.platformIoPort.pickMultipleSourceFiles();
      if (pickedList.isEmpty) {
        if (mounted) setState(() => _isLoading = false);
        return null;
      }
      if (pickedList.length < 2) {
        if (!mounted) return null;
        setState(() {
          _errorMessage = minCountError;
          _isLoading = false;
        });
        return null;
      }

      final parsedList = await Future.wait(
        pickedList.map(_parsePickedFile),
      );
      return [
        for (var i = 0; i < pickedList.length; i++)
          (file: pickedList[i], parsed: parsedList[i]),
      ];
    } on ActivityParseException catch (e) {
      if (!mounted) return null;
      setState(() {
        _errorMessage = e.message;
        _isLoading = false;
      });
      return null;
    } catch (e) {
      if (!mounted) return null;
      setState(() {
        _errorMessage = 'Failed to $failureAction Source Files: $e';
        _isLoading = false;
      });
      return null;
    }
  }

  Future<void> _importBlendSources() async {
    final entries = await _pickAndParseMultipleSources(
      minCountError: 'Select 2 or more Source Files to blend channels.',
      failureAction: 'blend',
    );
    if (entries == null || !mounted) return;

    try {
      final sources = <BlendSource>[
        for (var i = 0; i < entries.length; i++)
          BlendSource(
            id: 'source-$i',
            fileName: entries[i].file.fileName,
            activity: entries[i].parsed.activity,
            diagnostics: entries[i].parsed.diagnostics,
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
        _stitchSources = null;
        _stitchParts = null;
        _stitchConfig = null;
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

  Future<void> _importStitchSources() async {
    final entries = await _pickAndParseMultipleSources(
      minCountError: 'Select 2 or more Source Files to stitch parts.',
      failureAction: 'stitch',
    );
    if (entries == null || !mounted) return;

    try {
      final sources = <StitchSource>[
        for (var i = 0; i < entries.length; i++)
          StitchSource(
            id: 'part-$i',
            fileName: entries[i].file.fileName,
            activity: entries[i].parsed.activity,
            diagnostics: entries[i].parsed.diagnostics,
          ),
      ];
      const config = StitchConfiguration();
      final stitched = await CoreEngine.stitchActivitiesInIsolate(
        sources,
        config,
      );
      if (!mounted) return;
      setState(() {
        _parseResult = stitched.asParseResult;
        _sourceFileName = '${stitched.parts.length} Stitched Parts';
        _blendSources = null;
        _blendConfig = null;
        _stitchSources = sources;
        _stitchParts = stitched.parts;
        _stitchConfig = config;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to stitch Source Files: $e';
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
        onStitchTap: _importStitchSources,
        isLoading: _isLoading,
        errorMessage: _errorMessage,
      );
    }

    return WorkbenchScreen(
      initialResult: result,
      sourceFileName: _sourceFileName ?? 'activity.gpx',
      blendSources: _blendSources,
      initialBlendConfig: _blendConfig,
      stitchSources: _stitchSources,
      initialStitchParts: _stitchParts,
      initialStitchConfig: _stitchConfig,
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
        _stitchSources = null;
        _stitchParts = null;
        _stitchConfig = null;
        _errorMessage = null;
      }),
    );
  }
}
