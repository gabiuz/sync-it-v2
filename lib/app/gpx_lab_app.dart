import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/core_engine.dart';
import '../port/device_platform_io_port.dart';
import '../port/platform_io_port.dart';
import 'activity_formatters.dart';
import 'gpx_lab_theme.dart';
import 'start_screen.dart';
import 'workbench_screen.dart';

class GpxLabApp extends StatefulWidget {
  const GpxLabApp({
    super.key,
    this.platformIoPort,
  });

  final PlatformIoPort? platformIoPort;

  @override
  State<GpxLabApp> createState() => _GpxLabAppState();
}

class _GpxLabAppState extends State<GpxLabApp> {
  UnitSystem _unitSystem = UnitSystem.metric;
  ThemeMode _themeMode = ThemeMode.system;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: GpxLabTheme.appName,
      themeMode: _themeMode,
      theme: GpxLabTheme.light(),
      darkTheme: GpxLabTheme.dark(),
      home: _GpxLabShell(
        platformIoPort: widget.platformIoPort ?? const DevicePlatformIoPort(),
        unitSystem: _unitSystem,
        themeMode: _themeMode,
        onUnitSystemChanged: (units) => setState(() => _unitSystem = units),
        onThemeModeChanged: (mode) => setState(() => _themeMode = mode),
      ),
    );
  }
}

class _GpxLabShell extends StatefulWidget {
  const _GpxLabShell({
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
  State<_GpxLabShell> createState() => _GpxLabShellState();
}

class _GpxLabShellState extends State<_GpxLabShell> {
  ParseResult? _parseResult;
  String? _sourceFileName;
  List<BlendSource>? _blendSources;
  BlendConfiguration? _blendConfig;
  List<StitchSource>? _stitchSources;
  List<StitchedPartInfo>? _stitchParts;
  StitchConfiguration? _stitchConfig;
  bool _isLoading = false;
  String? _errorMessage;
  StreamSubscription<IncomingSourceBatch>? _incomingSub;

  @override
  void initState() {
    super.initState();
    _incomingSub =
        widget.platformIoPort.incomingSourceBatches.listen(_handleIncomingBatch);
    _consumeInitialIncomingSources();
  }

  @override
  void didUpdateWidget(covariant _GpxLabShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.platformIoPort != widget.platformIoPort) {
      _incomingSub?.cancel();
      _incomingSub = widget.platformIoPort.incomingSourceBatches
          .listen(_handleIncomingBatch);
    }
  }

  @override
  void dispose() {
    _incomingSub?.cancel();
    super.dispose();
  }

  Future<void> _consumeInitialIncomingSources() async {
    final batch = await widget.platformIoPort.consumeInitialIncomingSources();
    if (!mounted || batch == null || batch.isEmpty) return;
    await _handleIncomingBatch(batch);
  }

  void _resetToStartWithError(String message) {
    setState(() {
      _parseResult = null;
      _sourceFileName = null;
      _blendSources = null;
      _blendConfig = null;
      _stitchSources = null;
      _stitchParts = null;
      _stitchConfig = null;
      _isLoading = false;
      _errorMessage = message;
    });
  }

  static void _validateIncomingFile(PickedSourceFile picked) {
    final lower = picked.fileName.toLowerCase();
    final dotIndex = lower.lastIndexOf('.');
    if (dotIndex != -1) {
      final ext = lower.substring(dotIndex);
      if (ext != '.gpx' && ext != '.tcx' && ext != '.fit' && ext != '.kml') {
        throw ActivityParseException(
          'Unsupported file type "${picked.fileName}". '
          'GPX Lab only supports .gpx, .tcx, .fit, and .kml files.',
        );
      }
    }
  }

  Future<void> _handleIncomingBatch(IncomingSourceBatch batch) async {
    if (!mounted || batch.isEmpty) return;
    if (batch.errors.isNotEmpty) {
      _resetToStartWithError(batch.errors.first);
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      for (final file in batch.files) {
        _validateIncomingFile(file);
      }

      if (batch.files.length == 1) {
        final picked = batch.files.single;
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
        return;
      }

      final parsedList = await Future.wait(
        batch.files.map(_parsePickedFile),
      );
      if (!mounted) return;
      final entries = [
        for (var i = 0; i < batch.files.length; i++)
          (file: batch.files[i], parsed: parsedList[i]),
      ];
      setState(() => _isLoading = false);

      final suggestion = CoreEngine.suggestMultiFileMode(
        entries.map((e) => e.parsed.activity).toList(),
      );
      final chosen = await _showMultiFileModeDialog(
        entries.map((e) => e.file.fileName).toList(),
        suggestion,
      );
      if (!mounted || chosen == null) return;

      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      if (chosen == MultiFileCombinationMode.channelBlending) {
        await _applyBlendEntries(entries);
      } else {
        await _applyStitchEntries(entries);
      }
    } on ActivityParseException catch (e) {
      if (!mounted) return;
      _resetToStartWithError(e.message);
    } catch (e) {
      if (!mounted) return;
      _resetToStartWithError('Failed to open shared Source File: $e');
    }
  }

  Future<MultiFileCombinationMode?> _showMultiFileModeDialog(
    List<String> fileNames,
    MultiFileModeSuggestion suggestion,
  ) {
    final recommendBlend =
        suggestion.recommendedMode == MultiFileCombinationMode.channelBlending;
    return showDialog<MultiFileCombinationMode>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final colors = theme.colorScheme;
        return AlertDialog(
          key: const Key('multi-file-mode-dialog'),
          title: Text('${fileNames.length} Source Files Received'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                recommendBlend
                    ? 'Timestamps overlap — Channel Blending is recommended to align sensors onto a Base Timeline.'
                    : 'Timestamps are sequential — Sequential Stitching is recommended to join parts into one Activity.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              _ModeChoiceCard(
                buttonKey: const Key('choose-blend-mode-button'),
                title: 'Channel Blending',
                subtitle: 'Combine overlapping sensors from the same workout.',
                icon: Icons.layers_outlined,
                isRecommended: recommendBlend,
                recommendationKey: recommendBlend
                    ? const Key('recommended-mode-channelBlending')
                    : null,
                colors: colors,
                onTap: () => Navigator.of(dialogContext)
                    .pop(MultiFileCombinationMode.channelBlending),
              ),
              const SizedBox(height: 10),
              _ModeChoiceCard(
                buttonKey: const Key('choose-stitch-mode-button'),
                title: 'Sequential Stitching',
                subtitle: 'Concatenate back-to-back parts chronologically.',
                icon: Icons.timeline,
                isRecommended: !recommendBlend,
                recommendationKey: !recommendBlend
                    ? const Key('recommended-mode-sequentialStitching')
                    : null,
                colors: colors,
                onTap: () => Navigator.of(dialogContext)
                    .pop(MultiFileCombinationMode.sequentialStitching),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

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
    if (_isKmlSource(picked.fileName, picked.bytes)) {
      return CoreEngine.parseKmlInIsolate(
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
    await _applyBlendEntries(entries);
  }

  Future<void> _applyBlendEntries(
    List<({PickedSourceFile file, ParseResult parsed})> entries,
  ) async {
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
    await _applyStitchEntries(entries);
  }

  Future<void> _applyStitchEntries(
    List<({PickedSourceFile file, ParseResult parsed})> entries,
  ) async {
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

  static bool _isKmlSource(String fileName, List<int> bytes) {
    if (fileName.toLowerCase().endsWith('.kml')) return true;
    final prefixLen = bytes.length < 1024 ? bytes.length : 1024;
    final head = utf8.decode(bytes.sublist(0, prefixLen), allowMalformed: true);
    return RegExp(
      r'<kml[\s>]|http://www\.opengis\.net/kml/|http://earth\.google\.com/kml/',
    ).hasMatch(head);
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
      key: ValueKey(result),
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

class _ModeChoiceCard extends StatelessWidget {
  const _ModeChoiceCard({
    required this.buttonKey,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isRecommended,
    required this.recommendationKey,
    required this.colors,
    required this.onTap,
  });

  final Key buttonKey;
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isRecommended;
  final Key? recommendationKey;
  final ColorScheme colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      color: isRecommended ? colors.primaryContainer : colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isRecommended ? colors.primary : colors.outlineVariant,
          width: isRecommended ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        key: buttonKey,
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(
                icon,
                color: isRecommended
                    ? colors.onPrimaryContainer
                    : colors.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (isRecommended) ...[
                          const SizedBox(width: 8),
                          Container(
                            key: recommendationKey,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: colors.primary,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              'Recommended',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colors.onPrimary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isRecommended
                            ? colors.onPrimaryContainer
                            : colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
