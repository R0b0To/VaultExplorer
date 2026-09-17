import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/data/models/media_viewer_action.dart';

class MediaViewerActionButton extends StatelessWidget {
  final MediaViewerAction action;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool isHighlighted;
  final Color? highlightColor;
  final String? customTooltip;
  final IconData? customIcon;
  final double size;

  const MediaViewerActionButton({
    super.key,
    required this.action,
    required this.onTap,
    this.onLongPress,
    this.isHighlighted = false,
    this.highlightColor,
    this.customTooltip,
    this.customIcon,
    this.size = 40.0,
  });

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final activeColor = highlightColor ?? cs.primary;
    final iconColor = isHighlighted ? activeColor : Colors.white;
    final tooltip = customTooltip ?? action.getLocalizedLabel(context.l10n);

    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: size,
        height: size,
        child: Material(
          color: isHighlighted
              ? activeColor.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.12),
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              HapticFeedback.lightImpact();
              onTap();
            },
            onLongPress: onLongPress != null
                ? () {
                    HapticFeedback.mediumImpact();
                    onLongPress!();
                  }
                : null,
            child: Center(
              child: Icon(
                customIcon ?? action.icon,
                size: AppIconSize.standard,
                color: iconColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}