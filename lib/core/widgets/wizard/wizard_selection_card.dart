import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/widgets/container_format_icon.dart';
import 'package:vaultexplorer/data/models/container_format.dart';

/// One tappable card in a row of mutually-exclusive choices.
///
/// Supports either a leading [icon] or a [format] (which renders [ContainerFormatIcon]).
class WizardSelectionCard extends StatelessWidget {
  final IconData? icon;
  final ContainerFormat? format;
  final String title;
  final String? subtitle;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;

  const WizardSelectionCard({
    super.key,
    this.icon,
    this.format,
    required this.title,
    this.subtitle,
    required this.selected,
    this.enabled = true,
    this.onTap,
  }) : assert(icon != null || format != null, 'Either icon or format must be provided');

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;

    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: AnimatedContainer(
            duration: AppMotion.short2,
            curve: AppMotion.standard,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            decoration: BoxDecoration(
              color: selected
                  ? cs.primaryContainer.withValues(alpha: 0.35)
                  : cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected
                        ? cs.primaryContainer
                        : cs.surfaceContainerHighest,
                     borderRadius: BorderRadius.circular(16),
                    
                  ),
                  child: format != null
                      ? ContainerFormatIcon(
                          format: format!,
                          color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                          size: 24,
                        )
                      : Icon(
                          icon,
                          size: AppIconSize.action,
                          color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                        ),
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: selected ? cs.primary : cs.onSurface,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.2,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Icon(
                  selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                  size: 16,
                  color: selected
                      ? cs.primary
                      : cs.outlineVariant.withValues(alpha: 0.6),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}