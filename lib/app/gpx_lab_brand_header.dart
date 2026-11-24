import 'package:flutter/material.dart';

import 'gpx_lab_theme.dart';

/// Dedicated brand header for **GPX Lab** with clean drop-in slots for the
/// upcoming custom [logo] mark and character/[persona] illustration.
class GpxLabBrandHeader extends StatelessWidget {
  const GpxLabBrandHeader({
    super.key,
    this.logo,
    this.persona,
    this.title = GpxLabTheme.appName,
    this.subtitle = GpxLabTheme.appTagline,
  });

  final Widget? logo;
  final Widget? persona;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Column(
      key: const Key('brand-header'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            KeyedSubtree(
              key: const Key('brand-logo-slot'),
              child: logo ?? _DefaultLogoMark(colors: colors),
            ),
            const SizedBox(width: 10),
            KeyedSubtree(
              key: const Key('brand-persona-slot'),
              child: persona ?? _DefaultPersonaBadge(colors: colors),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _DefaultLogoMark extends StatelessWidget {
  const _DefaultLogoMark({required this.colors});

  final ColorScheme colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('brand-logo-placeholder'),
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colors.primary.withValues(alpha: 0.24),
        ),
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.route_rounded,
        size: 34,
        color: colors.primary,
      ),
    );
  }
}

class _DefaultPersonaBadge extends StatelessWidget {
  const _DefaultPersonaBadge({required this.colors});

  final ColorScheme colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('brand-persona-placeholder'),
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        shape: BoxShape.circle,
        border: Border.all(
          color: colors.outlineVariant,
        ),
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.directions_run_rounded,
        size: 20,
        color: colors.primary,
      ),
    );
  }
}
