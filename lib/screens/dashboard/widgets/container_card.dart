import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../models/mounted_container.dart';
import '../../../services/vaultexplorer_api.dart';
import '../../../utils/format_utils.dart';
import '../../../theme.dart';
import '../../../widgets/common_widgets.dart';

// ── Base Container Card (Internal) ──────────────────────────────────────────

class _BaseContainerCard extends StatelessWidget {
  static const double _bottomAreaHeight = 14.0;

  final VoidCallback onTap;
  final IconData icon;
  final Color iconColor;
  final Color iconBackgroundColor;
  final String title;
  final Widget subtitle;
  final Widget? trailingAction;
  final Widget? bottomContent; // optional progress bar row
  final Color? backgroundColor;
  final BorderRadiusGeometry? borderRadius;

  const _BaseContainerCard({
    required this.onTap,
    required this.icon,
    required this.iconColor,
    required this.iconBackgroundColor,
    required this.title,
    required this.subtitle,
    this.trailingAction,
    this.bottomContent,
    this.backgroundColor,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    
    final effectiveRadius = borderRadius ?? BorderRadius.circular(AppRadius.xl);

    return Card(
      elevation: 0,
      color: backgroundColor ?? cs.surfaceContainer,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: effectiveRadius,
        side: BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Main content row: icon + text + action button
              Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: iconBackgroundColor,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(icon, size: 28, color: iconColor),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.1,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        subtitle,
                      ],
                    ),
                  ),
                  if (trailingAction != null) ...[
                    const SizedBox(width: 8),
                    trailingAction!,
                  ],
                ],
              ),
              // Fixed-height bottom area – same size in locked & unlocked cards
              SizedBox(
                height: _bottomAreaHeight,
                child: bottomContent ?? const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Mounted (unlocked) container card ──────────────────────────────────────
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
    if (fraction > 0.90) return cs.error;
    if (fraction > 0.70) return cs.tertiary;
    return cs.primary;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final usedBytes = container.totalSpace - container.freeSpace;
    final usedFraction = container.totalSpace > 0
        ? (usedBytes / container.totalSpace).clamp(0.0, 1.0)
        : 0.0;
    final hasSpace = container.totalSpace > 0;
    final isUsb = container.uri.startsWith('usb:');

    // Subtitle without the bar – bar goes in the bottom area
    Widget subtitleWidget;
    if (hasSpace) {
      subtitleWidget = Text(
        '${formatBytes(container.freeSpace)} free · ${formatBytes(container.totalSpace)} total',
        style: textTheme.bodyMedium?.copyWith(
          color: cs.onSurfaceVariant,
        ),
        overflow: TextOverflow.ellipsis,
      );
    } else {
      subtitleWidget = Text(
        'Vol ${container.volId} · Mounted',
        style: textTheme.bodyMedium?.copyWith(
          color: cs.onSurfaceVariant,
        ),
        overflow: TextOverflow.ellipsis,
      );
    }

    // Bottom content: mini progress bar row (only if space info is available)
    Widget? bottomContent;
    if (hasSpace) {
      bottomContent = Padding(
        padding: const EdgeInsets.only(top: 8.0), // space above the bar
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.full),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: usedFraction),
            duration: AppMotion.long1,
            curve: AppMotion.standard,
            builder: (context, animatedFraction, _) => LinearProgressIndicator(
              value: animatedFraction,
              minHeight: 6,
              backgroundColor: cs.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(
                _barColor(usedFraction, cs),
              ),
            ),
          ),
        ),
      );
    }

    return _BaseContainerCard(
      onTap: onBrowse,
      icon: isUsb ? Icons.usb_rounded : Icons.folder_zip_rounded,
      iconColor: cs.onPrimaryContainer,
      iconBackgroundColor: cs.primaryContainer,
      title: container.displayName,
      subtitle: subtitleWidget,
      trailingAction: _LockButton(container: container, onLocked: onLocked),
      bottomContent: bottomContent,
      borderRadius: borderRadius,
    );
  }
}

// ── Saved (locked) container card ───────────────────────────────────────────
class SavedContainerCard extends StatelessWidget {
  final String name;
  final String uri;
  final VoidCallback onUnlock;
  final BorderRadiusGeometry? borderRadius;

  const SavedContainerCard({
    super.key,
    required this.name,
    required this.uri,
    required this.onUnlock,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isUsb = uri.startsWith('usb:');

    return _BaseContainerCard(
      onTap: onUnlock,
      icon: isUsb ? Icons.usb_rounded : Icons.folder_zip_rounded,
      iconColor: cs.onSurfaceVariant,
      iconBackgroundColor: cs.surfaceContainerHighest,
      title: name,
      subtitle: Text(
        isUsb ? 'USB drive' : 'Locked container',
        style: textTheme.bodyMedium?.copyWith(
          color: cs.onSurfaceVariant,
        ),
        overflow: TextOverflow.ellipsis,
      ),
      trailingAction: _UnlockButton(
        onUnlock: onUnlock,
        isUsb: isUsb,
      ),
      backgroundColor: cs.surfaceContainerLow,
      borderRadius: borderRadius,
      // bottomContent is omitted → the fixed 28dp area remains empty
    );
  }
}

// ── Compact Icon‑Only Action Button (Android 16+ pill shape) ──────────────
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

// ── Lock button ───────────────────────────────────────────────────────────────
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
          message: 'An operation is in progress. Please wait before locking.',
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
          message: 'Lock failed: ${e.runtimeType}',
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
      tooltip: 'Lock container',
    );
  }
}

// ── Unlock button ────────────────────────────────────────────────────────────
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
      tooltip: isUsb ? 'Reconnect USB' : 'Unlock container',
    );
  }
}