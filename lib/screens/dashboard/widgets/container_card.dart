import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../models/mounted_container.dart';
import '../../../services/vaultexplorer_api.dart';
import '../../../utils/format_utils.dart';

// ── Base Container Card (Internal) ──────────────────────────────────────────

class _BaseContainerCard extends StatelessWidget {
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final IconData icon;
  final Color iconColor;
  final Color iconBackgroundColor;
  final String title;
  final Widget subtitle;
  final Widget? trailingAction;
  final Widget? bottomContent;
  final bool isElevated;

  const _BaseContainerCard({
    required this.onTap,
    this.onLongPress,
    required this.icon,
    required this.iconColor,
    required this.iconBackgroundColor,
    required this.title,
    required this.subtitle,
    this.trailingAction,
    this.bottomContent,
    this.isElevated = true,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Card(
      elevation: 0, // Modern Android drops shadows in favor of tonal surfaces
      color: isElevated ? cs.surfaceContainerLow : Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24), // Larger, plush corners (MD3+)
        side: isElevated
            ? BorderSide.none
            : BorderSide(color: cs.outlineVariant, width: 1),
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        // Slightly larger padding for a modern, airy feel
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 56, // Slightly larger touch-target standard
                    height: 56,
                    decoration: BoxDecoration(
                      color: iconBackgroundColor,
                      // "Squircle" look popular in modern Android quick settings
                      borderRadius: BorderRadius.circular(16), 
                    ),
                    child: Icon(icon, size: 28, color: iconColor),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.1, // Slight letter spacing
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        subtitle,
                      ],
                    ),
                  ),
                  if (trailingAction != null) ...[
                    const SizedBox(width: 12),
                    trailingAction!,
                  ],
                ],
              ),
              if (bottomContent != null) ...[
                const SizedBox(height: 16),
                bottomContent!,
              ],
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
  final VoidCallback? onLongPress;
  final VoidCallback onBrowse;

  const ContainerCard({
    super.key,
    required this.container,
    required this.onLocked,
    required this.onBrowse,
    this.onLongPress,
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

    return _BaseContainerCard(
      onTap: onBrowse,
      onLongPress: onLongPress,
      icon: isUsb ? Icons.usb_rounded : Icons.folder_zip_rounded,
      iconColor: cs.onPrimaryContainer,
      iconBackgroundColor: cs.primaryContainer,
      title: container.displayName,
      subtitle: hasSpace
          ? Text(
              '${formatBytes(container.freeSpace)} free · ${formatBytes(container.totalSpace)} total',
              style: textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            )
          : Text(
              'Vol ${container.volId} · Mounted',
              style: textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
      trailingAction: _LockButton(container: container, onLocked: onLocked),
      bottomContent: hasSpace
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${(usedFraction * 100).toStringAsFixed(0)}% used',
                      style: textTheme.labelMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      formatBytes(usedBytes),
                      style: textTheme.labelMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Modern Android uses thicker, fully pill-shaped progress indicators
                ClipRRect(
                  borderRadius: BorderRadius.circular(100),
                  child: LinearProgressIndicator(
                    value: usedFraction,
                    minHeight: 8, // Thicker indicator
                    backgroundColor: cs.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      _barColor(usedFraction, cs),
                    ),
                  ),
                ),
              ],
            )
          : null,
    );
  }
}

// ── Standard Modern Card Action Button ────────────────────────────────────────

class _CardActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isLoading;
  final VoidCallback? onPressed;
  final Color backgroundColor;
  final Color foregroundColor;

  const _CardActionButton({
    required this.label,
    required this.icon,
    this.isLoading = false,
    this.onPressed,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    // Retained SizedBox constraints as requested to prevent layout crashes,
    // but fully rounded to match Android 15/16 pill-shaped tonal buttons.
    return SizedBox(
      width: 124, 
      height: 44, // Slightly taller standard touch target
      child: FilledButton(
        onPressed: isLoading ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          disabledBackgroundColor: backgroundColor.withValues(alpha: 0.6),
          disabledForegroundColor: foregroundColor.withValues(alpha: 0.6),
          padding: EdgeInsets.zero,
          elevation: 0,
          // Fully rounded pill shape
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(100),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading)
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: foregroundColor.withValues(alpha: 0.8),
                ),
              )
            else
              Icon(icon, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'An operation is in progress. Please wait before locking.',
            ),
          ),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lock failed: ${e.runtimeType}')),
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
    
    return _CardActionButton(
      label: 'Lock',
      icon: Icons.lock_outline_rounded, // Using rounded icon family
      isLoading: _loading,
      onPressed: _lock,
      // Tonal button mappings (Secondary container is standard for low-emphasis actions)
      backgroundColor: cs.secondaryContainer,
      foregroundColor: cs.onSecondaryContainer,
    );
  }
}

// ── Saved (locked) container card ───────────────────────────────────────────

class SavedContainerCard extends StatelessWidget {
  final String name;
  final String uri;
  final VoidCallback onUnlock;
  final VoidCallback? onLongPress;

  const SavedContainerCard({
    super.key,
    required this.name,
    required this.uri,
    required this.onUnlock,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isUsb = uri.startsWith('usb:');

    return _BaseContainerCard(
      onTap: onUnlock,
      onLongPress: onLongPress,
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
      isElevated: false, // Uses the `outlineVariant` border approach
    );
  }
}

// ── Unlock button ─────────────────────────────────────────────────────────────

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
    
    return _CardActionButton(
      label: isUsb ? 'Reconnect' : 'Unlock',
      icon: isUsb ? Icons.usb_rounded : Icons.lock_open_rounded,
      onPressed: () {
        HapticFeedback.lightImpact(); // Added standard haptics for interactions
        onUnlock();
      },
      // Primary tonal variant for emphasis
      backgroundColor: cs.primaryContainer,
      foregroundColor: cs.onPrimaryContainer,
    );
  }
}