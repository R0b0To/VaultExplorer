import 'package:flutter/material.dart';
import '../services/vaultexplorer_api.dart';

/// Presentational "Keyfiles (optional)" card shared by every unlock/config
/// surface that offers keyfile-based unlock. Previously copy-pasted
/// near-verbatim in unlock_sheet.dart, usb_unlock_sheet.dart, and
/// container_config_sheet.dart's _RealPasswordGateDialog. Pair with
/// [KeyfilePickerMixin] for the state/picking logic — this widget only
/// renders what it's handed.
class KeyfilePickerPanel extends StatelessWidget {
  final List<KeyfileRef> keyfiles;
  final bool picking;
  final bool enabled;
  final VoidCallback onPick;
  final ValueChanged<KeyfileRef> onRemove;

  /// container_config_sheet's dialog variant uses tighter spacing/icon
  /// sizes than the full-screen unlock sheets — `compact` reproduces that
  /// without a second copy of this widget.
  final bool compact;

  const KeyfilePickerPanel({
    super.key,
    required this.keyfiles,
    required this.picking,
    required this.onPick,
    required this.onRemove,
    this.enabled = true,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final iconSize = compact ? 18.0 : 20.0;
    final chipIconSize = compact ? 14.0 : 16.0;

    return Container(
      padding: EdgeInsets.all(compact ? 12 : 16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.insert_drive_file_outlined, size: iconSize, color: cs.primary),
                  SizedBox(width: compact ? 8 : 10),
                  Text(
                    'Keyfiles (optional)',
                    style: (compact ? textTheme.labelLarge : textTheme.titleSmall)
                        ?.copyWith(fontWeight: FontWeight.w600, color: cs.onSurface),
                  ),
                ],
              ),
              TextButton.icon(
                onPressed: (enabled && !picking) ? onPick : null,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 12, vertical: compact ? 4 : 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: picking
                    ? SizedBox(
                        width: compact ? 12 : 14,
                        height: compact ? 12 : 14,
                        child: const CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(Icons.add_rounded, size: compact ? 16 : 18),
                label: Text(compact ? 'Add' : 'Add file'),
              ),
            ],
          ),
          if (keyfiles.isNotEmpty) ...[
            SizedBox(height: compact ? 8 : 12),
            Wrap(
              spacing: compact ? 6 : 8,
              runSpacing: compact ? 6 : 8,
              children: keyfiles
                  .map(
                    (k) => InputChip(
                      avatar: Icon(Icons.description_outlined, size: chipIconSize, color: cs.onSurfaceVariant),
                      label: Text(k.displayName, style: textTheme.bodySmall, overflow: TextOverflow.ellipsis),
                      onDeleted: enabled ? () => onRemove(k) : null,
                      deleteIconColor: cs.error,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(compact ? 10 : 12)),
                      backgroundColor: compact ? null : cs.surfaceContainerHigh,
                    ),
                  )
                  .toList(),
            ),
          ] else ...[
            SizedBox(height: compact ? 6 : 8),
            Text(
              'No keyfiles attached',
              style: textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }
}