import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/data/models/container_format.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/core/widgets/container_format_icon.dart';

class _BaseContainerCard extends StatelessWidget {
  final VoidCallback onTap;
  final Widget icon;
  final Color iconBackgroundColor;
  final String title;
  final Widget subtitle;
  final Widget? trailingAction;
  final Color? backgroundColor;
  final BorderRadiusGeometry? borderRadius;
  const _BaseContainerCard({
    required this.onTap,
    required this.icon,
    required this.iconBackgroundColor,
    required this.title,
    required this.subtitle,
    this.trailingAction,
    this.backgroundColor,
    this.borderRadius,
  });
  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final effectiveRadius = borderRadius ?? BorderRadius.circular(24);
    return Card(
      elevation: 0,
      color: backgroundColor ?? cs.surfaceContainer,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: effectiveRadius,
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: iconBackgroundColor,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(child: icon),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.1,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    const SizedBox(height: 3),
                    subtitle,
                  ],
                ),
              ),
              if (trailingAction != null) ...[
                const SizedBox(width: 10),
                trailingAction!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class ContainerCard extends StatelessWidget {
  final MountedContainer container;
  final ValueChanged<int> onLocked;
  final VoidCallback onBrowse;
  final BorderRadiusGeometry? borderRadius;
  const ContainerCard({
    super.key,
    required this.container,
    required this.onLocked,
    required this.onBrowse,
    this.borderRadius,
  });

  Color _barColor(double fraction, ColorScheme cs) {
    final isLight = cs.brightness == Brightness.light;
    if (fraction > 0.90) {
      return isLight ? cs.error.withValues(alpha: 0.6) : cs.error;
    }
    if (fraction > 0.70) {
      return isLight ? cs.tertiary.withValues(alpha: 0.6) : cs.tertiary;
    }
    return isLight ? cs.primary.withValues(alpha: 0.6) : cs.primary;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isLight = cs.brightness == Brightness.light;
    final usedBytes = container.totalSpace - container.freeSpace;
    final usedFraction = container.totalSpace > 0
        ? (usedBytes / container.totalSpace).clamp(0.0, 1.0)
        : 0.0;
    final hasSpace = container.totalSpace > 0;
    final isUsb = container.uri.startsWith('usb:');
    final Widget progressBar;
    if (hasSpace) {
      progressBar = ClipRRect(
        borderRadius: BorderRadius.circular(100),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: usedFraction),
          duration: AppMotion.long1,
          curve: AppMotion.standard,
          builder: (context, animatedFraction, _) => LinearProgressIndicator(
            value: animatedFraction,
            minHeight: 4,
            backgroundColor: isLight
                ? cs.primary.withValues(alpha: 0.12)
                : cs.onPrimaryContainer.withValues(alpha: 0.15),
            valueColor: AlwaysStoppedAnimation<Color>(
              _barColor(usedFraction, cs),
            ),
          ),
        ),
      );
    } else {
      progressBar = ClipRRect(
        borderRadius: BorderRadius.circular(100),
        child: Container(
          height: 4,
          color: isLight
              ? cs.primary.withValues(alpha: 0.12)
              : cs.onPrimaryContainer.withValues(alpha: 0.15),
        ),
      );
    }
    final subtitleWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          hasSpace
              ? context.l10n.containerSpaceSummary(
                  formatBytes(container.freeSpace),
                  formatBytes(container.totalSpace),
                )
              : context.l10n.volMountedSummary(container.volId),
          style: textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
          ),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
        const SizedBox(height: 4),
        progressBar,
      ],
    );
    final iconWidget = isUsb
        ? Icon(Icons.usb_rounded, size: 26, color: cs.onPrimaryContainer)
        : ContainerFormatIcon(
            format: container.format,
            size: 26,
            color: cs.onPrimaryContainer,
          );
    final cardBg = Color.alphaBlend(
      isLight
          ? cs.primaryContainer.withValues(alpha: 0.55)
          : cs.primaryContainer.withValues(alpha: 0.35),
      cs.surfaceContainerHigh,
    );
    return _BaseContainerCard(
      onTap: onBrowse,
      icon: iconWidget,
      iconBackgroundColor: cs.primaryContainer,
      title: container.displayName,
      subtitle: subtitleWidget,
      trailingAction: _LockButton(container: container, onLocked: onLocked),
      backgroundColor: cardBg,
      borderRadius: borderRadius,
    );
  }
}

class SavedContainerCard extends StatelessWidget {
  final String name;
  final String uri;
  final String containerFormat;
  final VoidCallback onUnlock;
  final BorderRadiusGeometry? borderRadius;
  const SavedContainerCard({
    super.key,
    required this.name,
    required this.uri,
    required this.containerFormat,
    required this.onUnlock,
    this.borderRadius,
  });
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isUsb = uri.startsWith('usb:');
    final iconWidget = isUsb
        ? Icon(Icons.usb_rounded, size: 26, color: cs.onSurfaceVariant)
        : ContainerFormatIcon(
            format: ContainerFormat.fromWire(containerFormat),
            size: 26,
            color: cs.onSurfaceVariant,
          );
    final subtitleWidget = Text(
      isUsb ? context.l10n.usbDriveLockedLabel : context.l10n.lockedContainerLabel,
      style: textTheme.bodySmall?.copyWith(
        color: cs.onSurfaceVariant,
      ),
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
    );
    return _BaseContainerCard(
      onTap: onUnlock,
      icon: iconWidget,
      iconBackgroundColor: cs.surfaceContainerHighest,
      title: name,
      subtitle: subtitleWidget,
      trailingAction: _UnlockButton(
        onUnlock: onUnlock,
        isUsb: isUsb,
      ),
      backgroundColor: cs.surfaceContainerHigh,
      borderRadius: borderRadius,
    );
  }
}

class _CompactIconButton extends StatelessWidget {
  final IconData icon;
  final bool isLoading;
  final VoidCallback? onPressed;
  final Color backgroundColor;
  final Color foregroundColor;
  final String? tooltip;
  const _CompactIconButton({
    required this.icon,
    this.isLoading = false,
    this.onPressed,
    required this.backgroundColor,
    required this.foregroundColor,
    this.tooltip,
  });
  @override
  Widget build(BuildContext context) {
    final message = isLoading && tooltip != null ? '$tooltip, in progress' : (tooltip ?? '');
    return Tooltip(
      message: message,
      child: SizedBox(
        width: 44,
        height: 44,
        child: FilledButton(
          onPressed: isLoading ? null : onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: backgroundColor,
            foregroundColor: foregroundColor,
            disabledBackgroundColor: backgroundColor.withValues(alpha: 0.6),
            disabledForegroundColor: foregroundColor.withValues(alpha: 0.6),
            padding: EdgeInsets.zero,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.full),
            ),
          ),
          child: isLoading
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: foregroundColor.withValues(alpha: 0.8),
                  ),
                )
              : Icon(icon, size: 22),
        ),
      ),
    );
  }
}

class _LockButton extends StatefulWidget {
  final MountedContainer container;
  final ValueChanged<int> onLocked;
  const _LockButton({required this.container, required this.onLocked});
  @override
  State<_LockButton> createState() => _LockButtonState();
}

class _LockButtonState extends State<_LockButton> {
  bool _loading = false;
  Future<void> _lock() async {
    HapticFeedback.mediumImpact();
    if (!vaultExplorerApi.acquireLockGuard(widget.container.volId)) {
      if (mounted) {
        showAppSnackBar(
          context,
          message: context.l10n.operationInProgressWaitMessage,
          tone: AppBannerTone.warning,
        );
      }
      return;
    }
    setState(() => _loading = true);
    try {
      await vaultExplorerApi.lockContainer(widget.container.uri);
      widget.onLocked(widget.container.volId);
    } catch (e) {
      if (mounted) {
        showAppSnackBar(
          context,
          message: context.l10n.lockFailedMessage(e.runtimeType.toString()),
          tone: AppBannerTone.error,
        );
      }
    } finally {
      vaultExplorerApi.releaseLockGuard(widget.container.volId);
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _CompactIconButton(
      icon: Icons.lock_open_rounded,
      isLoading: _loading,
      onPressed: _lock,
      backgroundColor: cs.primaryContainer,
      foregroundColor: cs.onPrimaryContainer,
      tooltip: context.l10n.lockContainerTooltip,
    );
  }
}

class _UnlockButton extends StatelessWidget {
  final VoidCallback onUnlock;
  final bool isUsb;
  const _UnlockButton({
    required this.onUnlock,
    required this.isUsb,
  });
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _CompactIconButton(
      icon: isUsb ? Icons.usb_rounded : Icons.lock_outline_rounded,
      onPressed: () {
        HapticFeedback.lightImpact();
        onUnlock();
      },
      backgroundColor: cs.secondaryContainer,
      foregroundColor: cs.onSecondaryContainer,
      tooltip: isUsb ? context.l10n.reconnectUsbTooltip : context.l10n.unlockContainerTooltip,
    );
  }
}