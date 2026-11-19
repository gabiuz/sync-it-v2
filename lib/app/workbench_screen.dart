import 'package:flutter/material.dart';

import '../core/core_engine.dart';
import '../port/platform_io_port.dart';

class WorkbenchScreen extends StatefulWidget {
  const WorkbenchScreen({
    super.key,
    required this.initialResult,
    required this.sourceFileName,
    required this.platformIoPort,
    required this.onClose,
  });

  final ParseResult initialResult;
  final String sourceFileName;
  final PlatformIoPort platformIoPort;
  final VoidCallback onClose;

  @override
  State<WorkbenchScreen> createState() => _WorkbenchScreenState();
}

class _WorkbenchScreenState extends State<WorkbenchScreen> {
  int _selectedTab = 0;
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  late SportType _sportType;
  ExportFormat _exportFormat = ExportFormat.fit;
  bool _isExporting = false;
  String? _exportStatusMessage;

  @override
  void initState() {
    super.initState();
    final activity = widget.initialResult.activity;
    _titleController = TextEditingController(text: activity.title);
    _descriptionController = TextEditingController(text: activity.description);
    _sportType = activity.sportType;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  ActivityEdit get _currentEdit => ActivityEdit(
        title: _titleController.text.trim().isEmpty
            ? widget.initialResult.activity.title
            : _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        sportType: _sportType,
      );

  String get _suggestedExportFileName {
    final raw = (_currentEdit.title ?? widget.initialResult.activity.title)
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final base = raw.isEmpty ? 'activity' : raw;
    return '$base.${_exportFormat.extension}';
  }

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
    }
  }

  Future<void> _handleSave() async {
    setState(() {
      _isExporting = true;
      _exportStatusMessage = null;
    });
    try {
      final result = await _buildExportResult();
      final saved = await widget.platformIoPort.saveExportFile(
        suggestedFileName: _suggestedExportFileName,
        bytes: result.bytes,
      );
      if (!mounted) return;
      setState(() {
        _exportStatusMessage = saved
            ? 'Export File saved as $_suggestedExportFileName.'
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
      final result = await _buildExportResult();
      await widget.platformIoPort.shareExportFile(
        fileName: _suggestedExportFileName,
        bytes: result.bytes,
      );
      if (!mounted) return;
      setState(() {
        _exportStatusMessage = 'Shared $_suggestedExportFileName.';
      });
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
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
                  suggestedFileName: _suggestedExportFileName,
                  isExporting: _isExporting,
                  statusMessage: _exportStatusMessage,
                  onFormatChanged: (format) {
                    setState(() {
                      _exportFormat = format;
                      _exportStatusMessage = null;
                    });
                  },
                  onSave: _handleSave,
                  onShare: _handleShare,
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
  });

  final Activity activity;
  final ActivitySummary summary;
  final String sourceFileName;
  final String currentTitle;
  final SportType currentSportType;

  @override
  Widget build(BuildContext context) {
    final distanceKm = (summary.gpsDistanceMeters / 1000.0).toStringAsFixed(2);
    final durationText = _formatDuration(summary.duration);
    final paceText = summary.avgPaceSecondsPerKm != null
        ? _formatPace(summary.avgPaceSecondsPerKm!)
        : '—';
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
        Card(
          child: Column(
            children: [
              _StatRow(label: 'Distance', value: '$distanceKm km'),
              const Divider(height: 1),
              _StatRow(label: 'Duration', value: durationText),
              const Divider(height: 1),
              _StatRow(label: 'Average Pace', value: paceText),
              const Divider(height: 1),
              _StatRow(
                label: 'Elevation Gain',
                value: '${summary.elevationGainMeters.toStringAsFixed(0)} m',
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
      ],
    );
  }

  static String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  static String _formatPace(double secondsPerKm) {
    final totalSeconds = secondsPerKm.round();
    final mins = totalSeconds ~/ 60;
    final secs = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs /km';
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
    required this.suggestedFileName,
    required this.isExporting,
    required this.statusMessage,
    required this.onFormatChanged,
    required this.onSave,
    required this.onShare,
  });

  final ExportFormat exportFormat;
  final String suggestedFileName;
  final bool isExporting;
  final String? statusMessage;
  final ValueChanged<ExportFormat> onFormatChanged;
  final VoidCallback onSave;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final shortLabel = exportFormat.extension.toUpperCase();
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
          Card(
            child: ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text('Export File (${exportFormat.displayName})'),
              subtitle: Text(suggestedFileName),
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
        ],
      ),
    );
  }
}
