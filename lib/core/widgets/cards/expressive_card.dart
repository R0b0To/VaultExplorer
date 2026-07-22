import 'package:flutter/material.dart';

/// Rounded, bordered card used to group a section of related form fields
/// or settings — the "Android 16/17 Expressive" card style used throughout
/// the settings and container-creation/configuration sheets.
///
/// This was previously a private class (`_ExpressiveCard`) copy-pasted
/// verbatim into 7 different files (about_screen.dart,
/// app_settings_screen.dart, file_manager_toolbar_settings_screen.dart,
/// change_password_screen.dart, create_container_sheet.dart,
/// usb_create_container_sheet.dart, container_config_sheet.dart). One
/// shared implementation now backs all of them.
class ExpressiveCard extends StatelessWidget {
  final List<Widget> children;
  const ExpressiveCard({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.surfaceContainerLow,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

/// Icon + title/subtitle header for the top of an [ExpressiveCard] section.
/// See [ExpressiveCard] for the deduplication history.
class ExpressiveSectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const ExpressiveSectionHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, size: 20, color: cs.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
