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
    this.unitSystem = UnitSystem.metric,
    this.themeMode = ThemeMode.system,
    this.onUnitSystemChanged,
    this.onThemeModeChanged,
  });

  final ParseResult initialResult;
  final String sourceFileName;
  final PlatformIoPort platformIoPort;
  final VoidCallback onClose;
  final UnitSystem unitSystem;
  final ThemeMode themeMode;
  final ValueChanged<UnitSystem>? onUnitSystemChanged;
  final ValueChanged<ThemeMode>? onThemeModeChanged;

  @override
  State<WorkbenchScreen> createState() => _WorkbenchScreenState();
}

class _WorkbenchScreenState extends State<WorkbenchScreen> {
  int _selectedTab = 0;
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  late TextEditingController _fileNameController;
  bool _hasCustomFileName = false;
  late SportType _sportType;
  ExportFormat _exportFormat = ExportFormat.fit;
  bool _isExporting = false;
  String? _exportStatusMessage;
  bool _titleCopied = false;
  bool _descriptionCopied = false;
  ActivityDisplayGeometry? _displayGeometry;
  bool? _isMapTilesAvailable;

  @override
  void initState() {
    super.initState();
    final activity = widget.initialResult.activity;
    _titleController = TextEditingController(text: activity.title);
    _descriptionController = TextEditingController(text: activity.description);
    _sportType = activity.sportType;
    _fileNameController = TextEditingController(text: _smartDefaultFileName);
    _titleController.addListener(_onTitleChanged);
    _loadVisualInspectorData();
  }

  void _onTitleChanged() {
    if (!_hasCustomFileName) {
      _fileNameController.text = _smartDefaultFileName;
    }
  }

  Future<void> _loadVisualInspectorData() async {
    final activity = widget.initialResult.activity;
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

  @override
  void dispose() {
    _titleController.removeListener(_onTitleChanged);
    _titleController.dispose();
    _descriptionController.dispose();
    _fileNameController.dispose();
    super.dispose();
  }

  ActivityEdit get _currentEdit => ActivityEdit(
        title: _titleController.text.trim().isEmpty
            ? widget.initialResult.activity.title
            : _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        sportType: _sportType,
      );

  String get _smartDefaultFileName => buildSmartExportFileName(
        startTime: widget.initialResult.summary.startTime,
        title: _currentEdit.title ?? widget.initialResult.activity.title,
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
          widget.initialResult.activity,
          _currentEdit,
        );
      case ExportFormat.gpx:
        return CoreEngine.exportGpxInIsolate(
          widget.initialResult.activity,
          _currentEdit,
        );
      case ExportFormat.tcx:
        return CoreEngine.exportTcxInIsolate(
          widget.initialResult.activity,
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
    final title = _currentEdit.title ?? widget.initialResult.activity.title;
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
    final diagnostics = widget.initialResult.diagnostics;
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentEdit.title ?? widget.initialResult.activity.title),
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
                  activity: widget.initialResult.activity,
                  summary: widget.initialResult.summary,
                  sourceFileName: widget.sourceFileName,
                  currentTitle: _currentEdit.title ?? widget.initialResult.activity.title,
                  currentSportType: _sportType,
                  displayGeometry: _displayGeometry,
                  isMapTilesAvailable: _isMapTilesAvailable,
                  unitSystem: widget.unitSystem,
                ),
                _EditTab(
                  titleController: _titleController,
                  descriptionController: _descriptionController,
                  sportType: _sportType,
                  availableChannels: widget.initialResult.activity.availableChannels,
                  onSportChanged: (sport) {
                    if (sport != null) {
                      setState(() => _sportType = sport);
                    }
                  },
                ),
                _ExportTab(
                  exportFormat: _exportFormat,
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
    required this.sourceFileName,
    required this.currentTitle,
    required this.currentSportType,
    required this.displayGeometry,
    required this.isMapTilesAvailable,
    required this.unitSystem,
  });

  final Activity activity;
  final ActivitySummary summary;
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
    required this.sportType,
    required this.availableChannels,
    required this.onSportChanged,
  });

  final TextEditingController titleController;
  final TextEditingController descriptionController;
  final SportType sportType;
  final Set<Channel> availableChannels;
  final ValueChanged<SportType?> onSportChanged;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
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
        const SizedBox(height: 20),
        Text(
          'Detected Channels',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final channel in availableChannels)
              Chip(label: Text(channel.name)),
          ],
        ),
      ],
    );
  }
}

class _ExportTab extends StatelessWidget {
  const _ExportTab({
    required this.exportFormat,
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
    return ListView(
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
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: isExporting ? null : onSave,
          icon: const Icon(Icons.save_alt),
          label: Text('Save $shortLabel'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: isExporting ? null : onShare,
          icon: const Icon(Icons.share),
          label: Text('Share $shortLabel'),
        ),
        if (statusMessage != null) ...[
          const SizedBox(height: 16),
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                statusMessage!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
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
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  'Copy your edited metadata and open Strava\'s manual upload page.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
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
      ],
    );
  }
}
