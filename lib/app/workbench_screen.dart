import 'package:flutter/material.dart';

import '../core/core_engine.dart';
import '../port/platform_io_port.dart';
import 'activity_formatters.dart';
import 'channel_charts_section.dart';
import 'lap_table_card.dart';
import 'route_map_card.dart';
import 'settings_sheet.dart';

class WorkbenchScreen extends StatefulWidget {
  const WorkbenchScreen({
    super.key,
    required this.initialResult,
    required this.sourceFileName,
    required this.platformIoPort,
    required this.onClose,
    this.blendSources,
    this.initialBlendConfig,
    this.stitchSources,
    this.initialStitchParts,
    this.initialStitchConfig,
    this.unitSystem = UnitSystem.metric,
    this.themeMode = ThemeMode.system,
    this.onUnitSystemChanged,
    this.onThemeModeChanged,
  });

  final ParseResult initialResult;
  final String sourceFileName;
  final PlatformIoPort platformIoPort;
  final VoidCallback onClose;
  final List<BlendSource>? blendSources;
  final BlendConfiguration? initialBlendConfig;
  final List<StitchSource>? stitchSources;
  final List<StitchedPartInfo>? initialStitchParts;
  final StitchConfiguration? initialStitchConfig;
  final UnitSystem unitSystem;
  final ThemeMode themeMode;
  final ValueChanged<UnitSystem>? onUnitSystemChanged;
  final ValueChanged<ThemeMode>? onThemeModeChanged;

  @override
  State<WorkbenchScreen> createState() => _WorkbenchScreenState();
}

class _WorkbenchScreenState extends State<WorkbenchScreen> {
  int _selectedTab = 0;
  late ParseResult _activeResult;
  BlendConfiguration? _blendConfig;
  List<StitchedPartInfo>? _stitchParts;
  StitchConfiguration? _stitchConfig;
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  late TextEditingController _fileNameController;
  late TextEditingController _distanceOverrideController;
  bool _hasCustomFileName = false;
  late SportType _sportType;
  double? _distanceOverrideMeters;
  ExportFormat _exportFormat = ExportFormat.fit;
  final Set<StrippableChannel> _strippedChannels = <StrippableChannel>{};
  bool _isExporting = false;
  String? _exportStatusMessage;
  bool _titleCopied = false;
  bool _descriptionCopied = false;
  ActivityDisplayGeometry? _displayGeometry;
  bool? _isMapTilesAvailable;

  @override
  void initState() {
    super.initState();
    _activeResult = widget.initialResult;
    _blendConfig = widget.initialBlendConfig;
    _stitchParts = widget.initialStitchParts;
    _stitchConfig = widget.initialStitchConfig;
    final activity = _activeResult.activity;
    _titleController = TextEditingController(text: activity.title);
    _descriptionController = TextEditingController(text: activity.description);
    _sportType = activity.sportType;
    _fileNameController = TextEditingController(text: _smartDefaultFileName);
    _distanceOverrideController = TextEditingController();
    _titleController.addListener(_onTitleChanged);
    _loadVisualInspectorData();
  }

  @override
  void didUpdateWidget(covariant WorkbenchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.unitSystem != widget.unitSystem &&
        _distanceOverrideMeters != null) {
      _distanceOverrideController.text = formatDistanceInput(
        _distanceOverrideMeters!,
        units: widget.unitSystem,
      );
    }
  }

  void _onTitleChanged() {
    if (!_hasCustomFileName) {
      _fileNameController.text = _smartDefaultFileName;
    }
  }

  Future<void> _loadVisualInspectorData() async {
    final activity = _activeResult.activity;
    final onlineFuture = widget.platformIoPort.isMapTilesAvailable();
    if (activity.trackpoints.length <= 2000) {
      _displayGeometry = CoreEngine.buildDisplayGeometry(activity);
      final isOnline = await onlineFuture;
      if (!mounted) return;
      setState(() => _isMapTilesAvailable = isOnline);
      return;
    }

    final geometryFuture = CoreEngine.buildDisplayGeometryInIsolate(activity);
    final results = await Future.wait<Object>([geometryFuture, onlineFuture]);
    if (!mounted) return;
    setState(() {
      _displayGeometry = results[0] as ActivityDisplayGeometry;
      _isMapTilesAvailable = results[1] as bool;
    });
  }

  Future<void> _applyRecomputedResult(
    ParseResult nextResult, {
    bool syncSportType = false,
    List<StitchedPartInfo>? nextStitchParts,
  }) async {
    final geometry = nextResult.activity.trackpoints.length <= 2000
        ? CoreEngine.buildDisplayGeometry(nextResult.activity)
        : await CoreEngine.buildDisplayGeometryInIsolate(nextResult.activity);
    if (!mounted) return;
    setState(() {
      _activeResult = nextResult;
      if (syncSportType) {
        _sportType = nextResult.activity.sportType;
      }
      if (nextStitchParts != null) {
        _stitchParts = nextStitchParts;
      }
      _displayGeometry = geometry;
      if (!_hasCustomFileName) {
        _fileNameController.text = _smartDefaultFileName;
      }
    });
  }

  Future<void> _updateBlendConfig(BlendConfiguration nextConfig) async {
    final sources = widget.blendSources;
    if (sources == null) return;
    setState(() => _blendConfig = nextConfig);
    final blended = await CoreEngine.blendActivitiesInIsolate(
      sources,
      nextConfig,
    );
    if (!mounted) return;
    await _applyRecomputedResult(blended, syncSportType: true);
  }

  Future<void> _updateStitchConfig(StitchConfiguration nextConfig) async {
    final sources = widget.stitchSources;
    if (sources == null) return;
    setState(() => _stitchConfig = nextConfig);
    final stitched = await CoreEngine.stitchActivitiesInIsolate(
      sources,
      nextConfig,
    );
    if (!mounted) return;
    await _applyRecomputedResult(
      stitched.asParseResult,
      nextStitchParts: stitched.parts,
    );
  }

  void _onBaseTimelineChanged(String? newBaseId) {
    final current = _blendConfig;
    final sources = widget.blendSources;
    if (current == null || sources == null || newBaseId == null) return;
    if (newBaseId == current.baseSourceId) return;

    final oldBaseId = current.baseSourceId;
    final newBase = sources.firstWhere(
      (s) => s.id == newBaseId,
      orElse: () => sources.first,
    );
    final nextChannels = Map<Channel, String?>.from(current.channelSources);
    for (final channel in Channel.values) {
      if (nextChannels[channel] == oldBaseId &&
          newBase.activity.availableChannels.contains(channel)) {
        nextChannels[channel] = newBaseId;
      }
    }

    _updateBlendConfig(
      current.copyWith(
        baseSourceId: newBaseId,
        channelSources: Map.unmodifiable(nextChannels),
        lapsSourceId:
            current.lapsSourceId == oldBaseId ? newBaseId : current.lapsSourceId,
        caloriesSourceId: current.caloriesSourceId == oldBaseId
            ? newBaseId
            : current.caloriesSourceId,
        sportTypeSourceId: current.sportTypeSourceId == oldBaseId
            ? newBaseId
            : current.sportTypeSourceId,
        deviceInfoSourceId: current.deviceInfoSourceId == oldBaseId
            ? newBaseId
            : current.deviceInfoSourceId,
      ),
    );
  }

  void _onBlendChannelChanged(Channel channel, String? sourceId) {
    final current = _blendConfig;
    if (current == null || sourceId == null) return;
    final nextChannels = Map<Channel, String?>.from(current.channelSources);
    nextChannels[channel] = sourceId;
    _updateBlendConfig(
      current.copyWith(channelSources: Map.unmodifiable(nextChannels)),
    );
  }

  @override
  void dispose() {
    _titleController.removeListener(_onTitleChanged);
    _titleController.dispose();
    _descriptionController.dispose();
    _fileNameController.dispose();
    _distanceOverrideController.dispose();
    super.dispose();
  }

  ActivityEdit get _currentEdit => ActivityEdit(
        title: _titleController.text.trim().isEmpty
            ? _activeResult.activity.title
            : _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        sportType: _sportType,
        distanceOverrideMeters: _distanceOverrideMeters,
        strippedChannels: Set.unmodifiable(_strippedChannels),
      );

  void _toggleStrippableChannel(StrippableChannel channel, bool keep) {
    setState(() {
      if (keep) {
        _strippedChannels.remove(channel);
      } else {
        _strippedChannels.add(channel);
      }
    });
  }

  void _applyNudgeDistanceOverride(double targetMeters) {
    setState(() {
      _distanceOverrideMeters = targetMeters;
      _distanceOverrideController.text = formatDistanceInput(
        targetMeters,
        units: widget.unitSystem,
      );
    });
  }

  void _onDistanceOverrideChanged(String raw) {
    setState(() {
      _distanceOverrideMeters = parseDistanceOverrideMeters(
        raw,
        units: widget.unitSystem,
      );
    });
  }

  void _clearDistanceOverride() {
    setState(() {
      _distanceOverrideMeters = null;
      _distanceOverrideController.clear();
    });
  }

  String get _smartDefaultFileName => buildSmartExportFileName(
        startTime: _activeResult.summary.startTime,
        title: _currentEdit.title ?? _activeResult.activity.title,
        extension: _exportFormat.extension,
      );

  String get _resolvedExportFileName => sanitizeExportFileName(
        _fileNameController.text,
        extension: _exportFormat.extension,
        fallback: _smartDefaultFileName,
      );

  Future<ExportResult> _buildExportResult() {
    switch (_exportFormat) {
      case ExportFormat.fit:
        return CoreEngine.exportFitInIsolate(
          _activeResult.activity,
          _currentEdit,
        );
      case ExportFormat.gpx:
        return CoreEngine.exportGpxInIsolate(
          _activeResult.activity,
          _currentEdit,
        );
      case ExportFormat.tcx:
        return CoreEngine.exportTcxInIsolate(
          _activeResult.activity,
          _currentEdit,
        );
    }
  }

  Future<void> _handleSave() async {
    setState(() {
      _isExporting = true;
      _exportStatusMessage = null;
    });
    try {
      final fileName = _resolvedExportFileName;
      final result = await _buildExportResult();
      final saved = await widget.platformIoPort.saveExportFile(
        suggestedFileName: fileName,
        bytes: result.bytes,
      );
      if (!mounted) return;
      setState(() {
        _exportStatusMessage = saved
            ? 'Export File saved as $fileName.'
            : 'Save cancelled.';
      });
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  Future<void> _handleShare() async {
    setState(() {
      _isExporting = true;
      _exportStatusMessage = null;
    });
    try {
      final fileName = _resolvedExportFileName;
      final result = await _buildExportResult();
      await widget.platformIoPort.shareExportFile(
        fileName: fileName,
        bytes: result.bytes,
      );
      if (!mounted) return;
      setState(() {
        _exportStatusMessage = 'Shared $fileName.';
      });
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  Future<void> _copyTitle() async {
    final title = _currentEdit.title ?? _activeResult.activity.title;
    await widget.platformIoPort.copyToClipboard(title);
    if (!mounted) return;
    setState(() {
      _titleCopied = true;
      _descriptionCopied = false;
    });
  }

  Future<void> _copyDescription() async {
    final description = _currentEdit.description ?? '';
    await widget.platformIoPort.copyToClipboard(description);
    if (!mounted) return;
    setState(() {
      _descriptionCopied = true;
      _titleCopied = false;
    });
  }

  Future<void> _openStravaUploadPage() async {
    final launched = await widget.platformIoPort.launchExternalUrl(
      Uri.parse('https://www.strava.com/upload/select'),
    );
    if (!mounted || launched) return;
    setState(() {
      _exportStatusMessage = 'Could not open Strava upload page.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final diagnostics = _activeResult.diagnostics;
    final effectiveActivity = _distanceOverrideMeters != null
        ? CoreEngine.applyDistanceOverride(
            _activeResult.activity,
            _distanceOverrideMeters,
          )
        : _activeResult.activity;
    final effectiveSummary = _distanceOverrideMeters != null
        ? ActivitySummary(
            trackpointCount: _activeResult.summary.trackpointCount,
            startTime: _activeResult.summary.startTime,
            endTime: _activeResult.summary.endTime,
            duration: _activeResult.summary.duration,
            gpsDistanceMeters: _distanceOverrideMeters!,
            elevationGainMeters: _activeResult.summary.elevationGainMeters,
            avgHeartRateBpm: _activeResult.summary.avgHeartRateBpm,
            maxHeartRateBpm: _activeResult.summary.maxHeartRateBpm,
            avgPaceSecondsPerKm: _distanceOverrideMeters! > 0 &&
                    _activeResult.summary.duration.inMilliseconds > 0
                ? (_activeResult.summary.duration.inMilliseconds / 1000.0) /
                    (_distanceOverrideMeters! / 1000.0)
                : _activeResult.summary.avgPaceSecondsPerKm,
            calories: _activeResult.summary.calories,
            deviceInfo: _activeResult.summary.deviceInfo,
            lapCount: _activeResult.summary.lapCount,
          )
        : _activeResult.summary;
    final distanceDiagnostics = CoreEngine.analyzeDistance(
      _activeResult.activity,
      isImperial: widget.unitSystem == UnitSystem.imperial,
      distanceOverrideMeters: _distanceOverrideMeters,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(_currentEdit.title ?? _activeResult.activity.title),
        leading: IconButton(
          tooltip: 'Back to Start',
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onClose,
        ),
        actions: [
          IconButton(
            key: const Key('settings-button'),
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              showSettingsSheet(
                context,
                initialUnitSystem: widget.unitSystem,
                initialThemeMode: widget.themeMode,
                onUnitSystemChanged: (u) => widget.onUnitSystemChanged?.call(u),
                onThemeModeChanged: (m) => widget.onThemeModeChanged?.call(m),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (diagnostics.isNotEmpty) _DiagnosticBanner(diagnostics: diagnostics),
          Expanded(
            child: IndexedStack(
              index: _selectedTab,
              children: [
                _OverviewTab(
                  activity: effectiveActivity,
                  summary: effectiveSummary,
                  distanceDiagnostics: distanceDiagnostics,
                  distanceOverrideMeters: _distanceOverrideMeters,
                  onApplyNudge: _applyNudgeDistanceOverride,
                  sourceFileName: widget.sourceFileName,
                  currentTitle: _currentEdit.title ?? _activeResult.activity.title,
                  currentSportType: _sportType,
                  displayGeometry: _displayGeometry,
                  isMapTilesAvailable: _isMapTilesAvailable,
                  unitSystem: widget.unitSystem,
                ),
                _EditTab(
                  titleController: _titleController,
                  descriptionController: _descriptionController,
                  distanceOverrideController: _distanceOverrideController,
                  hasDistanceOverride: _distanceOverrideMeters != null,
                  unitSystem: widget.unitSystem,
                  onDistanceOverrideChanged: _onDistanceOverrideChanged,
                  onClearDistanceOverride: _clearDistanceOverride,
                  sportType: _sportType,
                  activity: _activeResult.activity,
                  strippedChannels: _strippedChannels,
                  onToggleChannel: _toggleStrippableChannel,
                  onSportChanged: (sport) {
                    if (sport != null) {
                      setState(() => _sportType = sport);
                    }
                  },
                  blendSources: widget.blendSources,
                  blendConfig: _blendConfig,
                  onBaseTimelineChanged: _onBaseTimelineChanged,
                  onBlendChannelChanged: _onBlendChannelChanged,
                  onBlendMetadataChanged: _updateBlendConfig,
                  stitchParts: _stitchParts,
                  stitchConfig: _stitchConfig,
                  onRemoveGapChanged: (removeGap) {
                    final current = _stitchConfig;
                    if (current == null) return;
                    _updateStitchConfig(current.copyWith(removeGap: removeGap));
                  },
                ),
                _ExportTab(
                  exportFormat: _exportFormat,
                  hasDistanceOverride: _distanceOverrideMeters != null,
                  exportWarnings: CoreEngine.analyzeExportWarnings(
                    _activeResult.activity,
                    _currentEdit,
                    _exportFormat,
                  ),
                  fileNameController: _fileNameController,
                  isExporting: _isExporting,
                  statusMessage: _exportStatusMessage,
                  onFileNameChanged: (value) {
                    _hasCustomFileName = value.trim().isNotEmpty;
                  },
                  onFormatChanged: (format) {
                    setState(() {
                      _exportFormat = format;
                      _exportStatusMessage = null;
                      if (_hasCustomFileName) {
                        _fileNameController.text = sanitizeExportFileName(
                          _fileNameController.text,
                          extension: format.extension,
                          fallback: _smartDefaultFileName,
                        );
                      } else {
                        _fileNameController.text = _smartDefaultFileName;
                      }
                    });
                  },
                  onSave: _handleSave,
                  onShare: _handleShare,
                  titleCopied: _titleCopied,
                  descriptionCopied: _descriptionCopied,
                  onCopyTitle: _copyTitle,
                  onCopyDescription: _copyDescription,
                  onOpenStravaUpload: _openStravaUploadPage,
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: (index) => setState(() => _selectedTab = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.analytics_outlined),
            selectedIcon: Icon(Icons.analytics),
            label: 'Overview',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune),
            label: 'Edit & Channels',
          ),
          NavigationDestination(
            icon: Icon(Icons.ios_share_outlined),
            selectedIcon: Icon(Icons.ios_share),
            label: 'Export',
          ),
        ],
      ),
    );
  }
}

class _DiagnosticBanner extends StatelessWidget {
  const _DiagnosticBanner({required this.diagnostics});

  final List<Diagnostic> diagnostics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: colors.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, color: colors.onSecondaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final d in diagnostics)
                    Text(
                      d.message,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSecondaryContainer,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({
    required this.activity,
    required this.summary,
    required this.distanceDiagnostics,
    required this.distanceOverrideMeters,
    required this.onApplyNudge,
    required this.sourceFileName,
    required this.currentTitle,
    required this.currentSportType,
    required this.displayGeometry,
    required this.isMapTilesAvailable,
    required this.unitSystem,
  });

  final Activity activity;
  final ActivitySummary summary;
  final DistanceDiagnostics distanceDiagnostics;
  final double? distanceOverrideMeters;
  final ValueChanged<double> onApplyNudge;
  final String sourceFileName;
  final String currentTitle;
  final SportType currentSportType;
  final ActivityDisplayGeometry? displayGeometry;
  final bool? isMapTilesAvailable;
  final UnitSystem unitSystem;

  @override
  Widget build(BuildContext context) {
    final distanceText =
        formatDistance(summary.gpsDistanceMeters, units: unitSystem);
    final durationText = formatDuration(summary.duration);
    final paceText = summary.avgPaceSecondsPerKm != null
        ? formatPace(summary.avgPaceSecondsPerKm!, units: unitSystem)
        : '—';
    final elevationText =
        formatElevation(summary.elevationGainMeters, units: unitSystem);
    final avgHrText =
        summary.avgHeartRateBpm != null ? '${summary.avgHeartRateBpm} bpm' : '—';
    final maxHrText =
        summary.maxHeartRateBpm != null ? '${summary.maxHeartRateBpm} bpm' : '—';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  currentTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  '${currentSportType.displayName} • $sourceFileName',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (displayGeometry != null)
          RouteMapCard(
            routePoints: displayGeometry!.routePoints,
            isOnline: isMapTilesAvailable,
          )
        else
          const Card(
            child: SizedBox(
              height: 240,
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              _StatRow(label: 'Distance', value: distanceText),
              const Divider(height: 1),
              _StatRow(label: 'Duration', value: durationText),
              const Divider(height: 1),
              _StatRow(label: 'Average Pace', value: paceText),
              const Divider(height: 1),
              _StatRow(
                label: 'Elevation Gain',
                value: elevationText,
              ),
              const Divider(height: 1),
              _StatRow(label: 'Average Heart Rate', value: avgHrText),
              const Divider(height: 1),
              _StatRow(label: 'Max Heart Rate', value: maxHrText),
              const Divider(height: 1),
              _StatRow(
                label: 'Trackpoints',
                value: '${summary.trackpointCount}',
              ),
              const Divider(height: 1),
              _StatRow(
                label: 'Laps',
                value: '${summary.lapCount}',
              ),
              if (summary.calories != null) ...[
                const Divider(height: 1),
                _StatRow(
                  label: 'Calories',
                  value: '${summary.calories} kcal',
                ),
              ],
              if (summary.deviceInfo != null) ...[
                const Divider(height: 1),
                _StatRow(
                  label: 'Device',
                  value: summary.deviceInfo!,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        _StravaTaxCard(
          diagnostics: distanceDiagnostics,
          distanceOverrideMeters: distanceOverrideMeters,
          unitSystem: unitSystem,
          onApplyNudge: onApplyNudge,
        ),
        if (displayGeometry != null) ...[
          const SizedBox(height: 12),
          ChannelChartsSection(
            geometry: displayGeometry!,
            unitSystem: unitSystem,
          ),
        ],
        if (activity.laps.isNotEmpty) ...[
          const SizedBox(height: 12),
          LapTableCard(
            laps: activity.laps,
            unitSystem: unitSystem,
          ),
        ],
      ],
    );
  }
}

class _StravaTaxCard extends StatelessWidget {
  const _StravaTaxCard({
    required this.diagnostics,
    required this.distanceOverrideMeters,
    required this.unitSystem,
    required this.onApplyNudge,
  });

  final DistanceDiagnostics diagnostics;
  final double? distanceOverrideMeters;
  final UnitSystem unitSystem;
  final ValueChanged<double> onApplyNudge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final unitSuffix = distanceUnitLabel(unitSystem);
    final recordedText = diagnostics.recordedDistanceMeters != null
        ? formatPreciseDistance(
            diagnostics.recordedDistanceMeters!,
            units: unitSystem,
          )
        : '—';
    final gpsText = diagnostics.gpsDistanceMeters > 0
        ? formatDistance(diagnostics.gpsDistanceMeters, units: unitSystem)
        : '—';
    final predictedText =
        '${diagnostics.predictedStravaDisplayValue.toStringAsFixed(2)} $unitSuffix';
    final taxText = diagnostics.stravaTaxMeters != null
        ? '${diagnostics.stravaTaxMeters! >= 0 ? '+' : ''}${formatPreciseDistance(diagnostics.stravaTaxMeters!, units: unitSystem)}'
        : '—';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          key: const Key('strava-tax-card'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                child: Text(
                  'Strava Tax Diagnostics',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              _StatRow(label: 'Recorded Distance', value: recordedText),
              const Divider(height: 1),
              _StatRow(label: 'GPS Distance (2D Haversine)', value: gpsText),
              const Divider(height: 1),
              _StatRow(label: 'Strava Tax Discrepancy', value: taxText),
              const Divider(height: 1),
              _StatRow(
                label: 'Predicted Strava Display',
                value: predictedText,
              ),
              if (distanceOverrideMeters != null) ...[
                const Divider(height: 1),
                _StatRow(
                  label: 'Distance Override',
                  value: formatDistance(
                    distanceOverrideMeters!,
                    units: unitSystem,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (diagnostics.dropsMilestone &&
            diagnostics.nudgeTargetMeters != null &&
            diagnostics.nudgeTargetDisplayValue != null) ...[
          const SizedBox(height: 12),
          Card(
            key: const Key('strava-truncation-warning-card'),
            color: colors.tertiaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: colors.onTertiaryContainer,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Strava Floor-Truncation Warning',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: colors.onTertiaryContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Strava rounds down to 2 decimals ($predictedText), which drops the ${diagnostics.nudgeTargetDisplayValue!.toStringAsFixed(2)} $unitSuffix milestone.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onTertiaryContainer,
                    ),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.tonalIcon(
                    key: const Key('nudge-distance-override-button'),
                    onPressed: () =>
                        onApplyNudge(diagnostics.nudgeTargetMeters!),
                    icon: const Icon(Icons.auto_fix_high),
                    label: Text(
                      'Nudge to ${diagnostics.nudgeTargetDisplayValue!.toStringAsFixed(2)} $unitSuffix',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _SequentialStitchingSection extends StatelessWidget {
  const _SequentialStitchingSection({
    required this.parts,
    required this.config,
    required this.unitSystem,
    required this.onRemoveGapChanged,
  });

  final List<StitchedPartInfo> parts;
  final StitchConfiguration config;
  final UnitSystem unitSystem;
  final ValueChanged<bool> onRemoveGapChanged;

  static String _formatUtcTime(DateTime dt) {
    final u = dt.toUtc();
    final hh = u.hour.toString().padLeft(2, '0');
    final mm = u.minute.toString().padLeft(2, '0');
    final ss = u.second.toString().padLeft(2, '0');
    return '$hh:$mm:$ss UTC';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Sequential Stitching',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              for (var i = 0; i < parts.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                ListTile(
                  key: Key('stitch-part-$i'),
                  leading: CircleAvatar(
                    radius: 14,
                    child: Text('${i + 1}'),
                  ),
                  title: Text('Part ${i + 1}: ${parts[i].fileName}'),
                  subtitle: Text(
                    '${_formatUtcTime(parts[i].effectiveStartTime)} – ${_formatUtcTime(parts[i].effectiveEndTime)} • '
                    '${formatDistance(parts[i].distanceMeters, units: unitSystem)} • '
                    '${parts[i].keptTrackpointCount} pts'
                    '${parts[i].trimmedHeadCount > 0 ? ' (trimmed ${parts[i].trimmedHeadCount})' : ''}',
                  ),
                ),
              ],
              const Divider(height: 1),
              SwitchListTile(
                key: const Key('stitch-remove-gap-switch'),
                title: const Text('Remove gap'),
                subtitle: const Text(
                  'Shift subsequent parts flush against the preceding part for continuous elapsed time.',
                ),
                value: config.removeGap,
                onChanged: onRemoveGapChanged,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChannelBlendingSection extends StatelessWidget {
  const _ChannelBlendingSection({
    required this.sources,
    required this.config,
    required this.onBaseTimelineChanged,
    required this.onChannelChanged,
    required this.onMetadataChanged,
  });

  final List<BlendSource> sources;
  final BlendConfiguration config;
  final ValueChanged<String?> onBaseTimelineChanged;
  final void Function(Channel channel, String? sourceId) onChannelChanged;
  final ValueChanged<BlendConfiguration> onMetadataChanged;

  static String _channelLabel(Channel channel) {
    switch (channel) {
      case Channel.gps:
        return 'GPS Position';
      case Channel.elevation:
        return 'Elevation';
      case Channel.distance:
        return 'Cumulative Distance';
      case Channel.heartRate:
        return 'Heart Rate';
      case Channel.cadence:
        return 'Cadence';
      case Channel.power:
        return 'Power';
      case Channel.temperature:
        return 'Temperature';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Channel Blending',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  key: const Key('blend-base-timeline-dropdown'),
                  initialValue: config.baseSourceId,
                  decoration: const InputDecoration(
                    labelText: 'Base Timeline',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final s in sources)
                      DropdownMenuItem(
                        value: s.id,
                        child: Text(
                          '${s.fileName} (${s.activity.trackpoints.length} pts)',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: onBaseTimelineChanged,
                ),
                const SizedBox(height: 16),
                Text(
                  'Telemetry Channels (±5s alignment)',
                  style: theme.textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                for (final channel in Channel.values) ...[
                  Builder(
                    builder: (context) {
                      final matching = sources
                          .where(
                            (s) => s.activity.availableChannels.contains(channel),
                          )
                          .toList();
                      if (matching.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text(
                            '${_channelLabel(channel)}: Not present in any Source File',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        );
                      }
                      final selectedId = config.channelSources[channel];
                      final effectiveValue = matching.any((s) => s.id == selectedId)
                          ? selectedId
                          : matching.first.id;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: DropdownButtonFormField<String>(
                          key: Key('blend-channel-${channel.name}-dropdown'),
                          initialValue: effectiveValue,
                          decoration: InputDecoration(
                            labelText: _channelLabel(channel),
                            border: const OutlineInputBorder(),
                          ),
                          items: [
                            for (final s in matching)
                              DropdownMenuItem(
                                value: s.id,
                                child: Text(
                                  s.fileName,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (id) => onChannelChanged(channel, id),
                        ),
                      );
                    },
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  'Activity Metadata Sources',
                  style: theme.textTheme.labelLarge,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: const Key('blend-meta-laps-dropdown'),
                  initialValue: config.lapsSourceId ?? config.baseSourceId,
                  decoration: const InputDecoration(
                    labelText: 'Laps Source',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final s in sources)
                      DropdownMenuItem(
                        value: s.id,
                        child: Text(
                          '${s.fileName} (${s.activity.laps.length} laps)',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (id) {
                    if (id != null) {
                      onMetadataChanged(config.copyWith(lapsSourceId: id));
                    }
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: const Key('blend-meta-calories-dropdown'),
                  initialValue: config.caloriesSourceId ?? config.baseSourceId,
                  decoration: const InputDecoration(
                    labelText: 'Calories Source',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final s in sources)
                      DropdownMenuItem(
                        value: s.id,
                        child: Text(
                          '${s.fileName} (${s.activity.calories ?? '—'} kcal)',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (id) {
                    if (id != null) {
                      onMetadataChanged(config.copyWith(caloriesSourceId: id));
                    }
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: const Key('blend-meta-sport-dropdown'),
                  initialValue: config.sportTypeSourceId ?? config.baseSourceId,
                  decoration: const InputDecoration(
                    labelText: 'Sport Type Source',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final s in sources)
                      DropdownMenuItem(
                        value: s.id,
                        child: Text(
                          '${s.fileName} (${s.activity.sportType.displayName})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (id) {
                    if (id != null) {
                      onMetadataChanged(config.copyWith(sportTypeSourceId: id));
                    }
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: const Key('blend-meta-device-dropdown'),
                  initialValue: config.deviceInfoSourceId ?? config.baseSourceId,
                  decoration: const InputDecoration(
                    labelText: 'Device Info Source',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final s in sources)
                      DropdownMenuItem(
                        value: s.id,
                        child: Text(
                          '${s.fileName} (${s.activity.deviceInfo ?? '—'})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (id) {
                    if (id != null) {
                      onMetadataChanged(config.copyWith(deviceInfoSourceId: id));
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(label),
      trailing: Text(
        value,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _EditTab extends StatelessWidget {
  const _EditTab({
    required this.titleController,
    required this.descriptionController,
    required this.distanceOverrideController,
    required this.hasDistanceOverride,
    required this.unitSystem,
    required this.onDistanceOverrideChanged,
    required this.onClearDistanceOverride,
    required this.sportType,
    required this.activity,
    required this.strippedChannels,
    required this.onToggleChannel,
    required this.onSportChanged,
    this.blendSources,
    this.blendConfig,
    this.onBaseTimelineChanged,
    this.onBlendChannelChanged,
    this.onBlendMetadataChanged,
    this.stitchParts,
    this.stitchConfig,
    this.onRemoveGapChanged,
  });

  final TextEditingController titleController;
  final TextEditingController descriptionController;
  final TextEditingController distanceOverrideController;
  final bool hasDistanceOverride;
  final UnitSystem unitSystem;
  final ValueChanged<String> onDistanceOverrideChanged;
  final VoidCallback onClearDistanceOverride;
  final SportType sportType;
  final Activity activity;
  final Set<StrippableChannel> strippedChannels;
  final void Function(StrippableChannel channel, bool keep) onToggleChannel;
  final ValueChanged<SportType?> onSportChanged;
  final List<BlendSource>? blendSources;
  final BlendConfiguration? blendConfig;
  final ValueChanged<String?>? onBaseTimelineChanged;
  final void Function(Channel channel, String? sourceId)? onBlendChannelChanged;
  final ValueChanged<BlendConfiguration>? onBlendMetadataChanged;
  final List<StitchedPartInfo>? stitchParts;
  final StitchConfiguration? stitchConfig;
  final ValueChanged<bool>? onRemoveGapChanged;

  bool _isChannelPresent(StrippableChannel channel) {
    switch (channel) {
      case StrippableChannel.heartRate:
        return activity.availableChannels.contains(Channel.heartRate);
      case StrippableChannel.gps:
        return activity.availableChannels.contains(Channel.gps);
      case StrippableChannel.elevation:
        return activity.availableChannels.contains(Channel.elevation);
      case StrippableChannel.cadence:
        return activity.availableChannels.contains(Channel.cadence);
      case StrippableChannel.power:
        return activity.availableChannels.contains(Channel.power);
      case StrippableChannel.temperature:
        return activity.availableChannels.contains(Channel.temperature);
      case StrippableChannel.calories:
        return activity.calories != null;
      case StrippableChannel.laps:
        return activity.laps.isNotEmpty;
      case StrippableChannel.deviceInfo:
        return activity.deviceInfo != null &&
            activity.deviceInfo!.trim().isNotEmpty;
    }
  }

  @override
  Widget build(BuildContext context) {
    final unitSuffix = distanceUnitLabel(unitSystem);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (blendSources != null &&
            blendSources!.length >= 2 &&
            blendConfig != null) ...[
          _ChannelBlendingSection(
            sources: blendSources!,
            config: blendConfig!,
            onBaseTimelineChanged: onBaseTimelineChanged!,
            onChannelChanged: onBlendChannelChanged!,
            onMetadataChanged: onBlendMetadataChanged!,
          ),
          const SizedBox(height: 20),
        ],
        if (stitchParts != null &&
            stitchParts!.length >= 2 &&
            stitchConfig != null) ...[
          _SequentialStitchingSection(
            parts: stitchParts!,
            config: stitchConfig!,
            unitSystem: unitSystem,
            onRemoveGapChanged: onRemoveGapChanged!,
          ),
          const SizedBox(height: 20),
        ],
        TextField(
          key: const Key('edit-title-field'),
          controller: titleController,
          decoration: const InputDecoration(
            labelText: 'Activity Title',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('edit-description-field'),
          controller: descriptionController,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Description',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<SportType>(
          key: const Key('edit-sport-dropdown'),
          initialValue: sportType,
          decoration: const InputDecoration(
            labelText: 'Sport Type',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final sport in SportType.values)
              DropdownMenuItem(
                value: sport,
                child: Text(sport.displayName),
              ),
          ],
          onChanged: onSportChanged,
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('edit-distance-override-field'),
          controller: distanceOverrideController,
          onChanged: onDistanceOverrideChanged,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Distance Override ($unitSuffix)',
            hintText: 'Leave empty to keep original distance',
            border: const OutlineInputBorder(),
            suffixIcon: hasDistanceOverride ||
                    distanceOverrideController.text.isNotEmpty
                ? IconButton(
                    key: const Key('clear-distance-override-button'),
                    tooltip: 'Clear Distance Override',
                    icon: const Icon(Icons.clear),
                    onPressed: onClearDistanceOverride,
                  )
                : null,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Channel Controls (Keep / Strip)',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              for (final channel in StrippableChannel.values) ...[
                Builder(
                  builder: (context) {
                    final isPresent = _isChannelPresent(channel);
                    final isKept = !strippedChannels.contains(channel);
                    final subtitleText = !isPresent
                        ? 'Not present in loaded Activity'
                        : (channel == StrippableChannel.laps &&
                                activity.laps.length > 1)
                            ? 'Present (${activity.laps.length} Laps)'
                            : (isKept
                                ? 'Present — keep on export'
                                : 'Present — stripped on export');
                    return SwitchListTile(
                      key: Key('channel-toggle-${channel.name}'),
                      title: Text(channel.displayName),
                      subtitle: Text(subtitleText),
                      value: isPresent && isKept,
                      onChanged: isPresent
                          ? (keep) => onToggleChannel(channel, keep)
                          : null,
                    );
                  },
                ),
                if (channel == StrippableChannel.deviceInfo &&
                    strippedChannels.contains(StrippableChannel.deviceInfo))
                  Padding(
                    key: const Key('device-info-strip-note'),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.tertiaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 18,
                            color: Theme.of(context)
                                .colorScheme
                                .onTertiaryContainer,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Stripping Device / Creator Info means target platforms such as Strava may apply automatic elevation correction or re-evaluate stats.',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onTertiaryContainer,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ExportTab extends StatelessWidget {
  const _ExportTab({
    required this.exportFormat,
    required this.hasDistanceOverride,
    required this.exportWarnings,
    required this.fileNameController,
    required this.isExporting,
    required this.statusMessage,
    required this.onFileNameChanged,
    required this.onFormatChanged,
    required this.onSave,
    required this.onShare,
    required this.titleCopied,
    required this.descriptionCopied,
    required this.onCopyTitle,
    required this.onCopyDescription,
    required this.onOpenStravaUpload,
  });

  final ExportFormat exportFormat;
  final bool hasDistanceOverride;
  final List<ExportWarning> exportWarnings;
  final TextEditingController fileNameController;
  final bool isExporting;
  final String? statusMessage;
  final ValueChanged<String> onFileNameChanged;
  final ValueChanged<ExportFormat> onFormatChanged;
  final VoidCallback onSave;
  final VoidCallback onShare;
  final bool titleCopied;
  final bool descriptionCopied;
  final VoidCallback onCopyTitle;
  final VoidCallback onCopyDescription;
  final VoidCallback onOpenStravaUpload;

  @override
  Widget build(BuildContext context) {
    final shortLabel = exportFormat.extension.toUpperCase();
    final hasBlockingWarning = exportWarnings.any((w) => w.isBlocking);
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return ListView(
      key: const Key('export-tab-list'),
      padding: const EdgeInsets.all(16),
      children: [
        SegmentedButton<ExportFormat>(
          key: const Key('export-format-selector'),
          segments: [
            for (final format in ExportFormat.values)
              ButtonSegment<ExportFormat>(
                value: format,
                label: Text(format.extension.toUpperCase()),
              ),
          ],
          selected: {exportFormat},
          onSelectionChanged: (selection) {
            if (selection.isNotEmpty) {
              onFormatChanged(selection.first);
            }
          },
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('export-filename-field'),
          controller: fileNameController,
          onChanged: onFileNameChanged,
          decoration: InputDecoration(
            labelText: 'Export File (${exportFormat.displayName})',
            prefixIcon: const Icon(Icons.description_outlined),
            border: const OutlineInputBorder(),
          ),
        ),
        for (final warning in exportWarnings.where(
          (w) =>
              w.isBlocking ||
              (hasDistanceOverride &&
                  exportFormat == ExportFormat.gpx &&
                  w.code == ExportWarningCode.gpxDropsCumulativeDistance),
        )) ...[
          const SizedBox(height: 12),
          _ExportWarningCard(
            key: warning.isBlocking
                ? const Key('export-blocking-warning')
                : const Key('gpx-distance-override-warning'),
            warning: warning,
          ),
        ],
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: (isExporting || hasBlockingWarning) ? null : onSave,
          icon: const Icon(Icons.save_alt),
          label: Text('Save $shortLabel'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: (isExporting || hasBlockingWarning) ? null : onShare,
          icon: const Icon(Icons.share),
          label: Text('Share $shortLabel'),
        ),
        if (statusMessage != null) ...[
          const SizedBox(height: 16),
          Card(
            color: colors.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                statusMessage!,
                style: TextStyle(
                  color: colors.onPrimaryContainer,
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
        Card(
          key: const Key('strava-upload-helper-card'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Strava Upload Helper',
                  style: textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  'Copy your edited metadata and open Strava\'s manual upload page.',
                  style: textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      key: const Key('copy-title-button'),
                      onPressed: onCopyTitle,
                      icon: Icon(
                        titleCopied ? Icons.check : Icons.content_copy,
                        size: 18,
                      ),
                      label: const Text('Copy Title'),
                    ),
                    OutlinedButton.icon(
                      key: const Key('copy-description-button'),
                      onPressed: onCopyDescription,
                      icon: Icon(
                        descriptionCopied ? Icons.check : Icons.content_copy,
                        size: 18,
                      ),
                      label: const Text('Copy Description'),
                    ),
                  ],
                ),
                if (titleCopied || descriptionCopied) ...[
                  const SizedBox(height: 8),
                  Text(
                    titleCopied ? 'Title copied' : 'Description copied',
                    style: textTheme.labelMedium?.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  key: const Key('open-strava-upload-button'),
                  onPressed: onOpenStravaUpload,
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Open Strava Upload Page'),
                ),
              ],
            ),
          ),
        ),
        for (final warning in exportWarnings.where(
          (w) =>
              !w.isBlocking &&
              !(hasDistanceOverride &&
                  exportFormat == ExportFormat.gpx &&
                  w.code == ExportWarningCode.gpxDropsCumulativeDistance),
        )) ...[
          const SizedBox(height: 12),
          _ExportWarningCard(
            key: Key('export-warning-${warning.code.name}'),
            warning: warning,
          ),
        ],
      ],
    );
  }
}

class _ExportWarningCard extends StatelessWidget {
  const _ExportWarningCard({
    super.key,
    required this.warning,
  });

  final ExportWarning warning;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Card(
      color: warning.isBlocking
          ? colors.errorContainer
          : colors.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              warning.isBlocking ? Icons.block : Icons.warning_amber_rounded,
              color: warning.isBlocking
                  ? colors.onErrorContainer
                  : colors.onTertiaryContainer,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                warning.message,
                style: textTheme.bodySmall?.copyWith(
                  color: warning.isBlocking
                      ? colors.onErrorContainer
                      : colors.onTertiaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
