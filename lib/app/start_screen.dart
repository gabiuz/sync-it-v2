import 'package:flutter/material.dart';

class StartScreen extends StatelessWidget {
  const StartScreen({
    super.key,
    required this.onImportTap,
    this.onBlendTap,
    this.isLoading = false,
    this.errorMessage,
  });

  final VoidCallback onImportTap;
  final VoidCallback? onBlendTap;
  final bool isLoading;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.route_rounded,
                    size: 64,
                    color: colors.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Sync-It',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Offline activity file workbench. Inspect, edit, and export clean FIT, TCX, or GPX files before uploading.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 32),
                  FilledButton.icon(
                    key: const Key('import-source-button'),
                    onPressed: isLoading ? null : onImportTap,
                    icon: isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.file_open_outlined),
                    label: Text(
                      isLoading
                          ? 'Parsing Source File...'
                          : 'Import Source File',
                    ),
                  ),
                  if (onBlendTap != null) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      key: const Key('blend-channels-button'),
                      onPressed: isLoading ? null : onBlendTap,
                      icon: const Icon(Icons.layers_outlined),
                      label: const Text('Blend Channels (2+ Files)'),
                    ),
                  ],
                  if (errorMessage != null) ...[
                    const SizedBox(height: 20),
                    Card(
                      color: colors.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.error_outline,
                              color: colors.onErrorContainer,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                errorMessage!,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colors.onErrorContainer,
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
          ),
        ),
      ),
    );
  }
}
