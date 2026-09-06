import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/widgets/container_format_icon.dart';
import 'package:vaultexplorer/data/models/container_format.dart';

/// One tappable card in a row of mutually-exclusive choices.
///
/// Dynamically scales icon and padding down in landscape/compact height screens.
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
    final isShortScreen = MediaQuery.sizeOf(context).height < 520;

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
            padding: EdgeInsets.symmetric(
              vertical: isShortScreen ? 6 : 8,
              horizontal: 8,
            ),
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
                  width: isShortScreen ? 36 : 48,
                  height: isShortScreen ? 36 : 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected
                        ? cs.primaryContainer
                        : cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(isShortScreen ? 12 : 16),
                  ),
                  child: format != null
                      ? ContainerFormatIcon(
                          format: format!,
                          color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                          size: isShortScreen ? 18 : 24,
                        )
                      : Icon(
                          icon,
                          size: isShortScreen ? 18 : AppIconSize.action,
                          color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                        ),
                ),
                SizedBox(height: isShortScreen ? 4 : 8),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: isShortScreen ? 12 : null,
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
                      fontSize: isShortScreen ? 11 : null,
                      height: 1.2,
                    ),
                  ),
                ],
                SizedBox(height: isShortScreen ? 3 : 6),
                Icon(
                  selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                  size: isShortScreen ? 14 : 16,
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