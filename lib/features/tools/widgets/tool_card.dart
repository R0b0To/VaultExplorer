import 'package:flutter/material.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';

/// One tappable tool entry in the Tools tab's grouped grid — icon badge,
/// title, short subtitle. Mirrors `container_card.dart`'s `_BaseContainerCard`
/// visual language (tinted icon chip on a `surfaceContainer` card) so the
/// Tools tab reads as the same app as the Vaults dashboard.
class ToolCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color? iconColor;

  const ToolCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;
    final accent = iconColor ?? cs.primary;

    return Card(
      elevation: 0,
      color: cs.surfaceContainer,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                child: Icon(icon, size: AppIconSize.action, color: accent),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.1,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.25,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
