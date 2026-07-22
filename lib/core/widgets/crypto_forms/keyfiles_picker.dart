import 'package:flutter/material.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart' show KeyfileRef;

/// The "keyfiles" picker card — previously hand-duplicated (with minor
/// visual drift) across `unlock_sheet.dart`, `usb_unlock_sheet.dart`,
/// `container_config_sheet.dart`'s `_RealPasswordGateDialog`. One
/// implementation now backs all of them.
class KeyfilesPicker extends StatelessWidget {
  final List<KeyfileRef> keyfiles;
  final bool picking;
  final VoidCallback onPick;
  final ValueChanged<KeyfileRef> onRemove;
  final bool enabled;

  const KeyfilesPicker({
    super.key,
    required this.keyfiles,
    required this.picking,
    required this.onPick,
    required this.onRemove,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.lg),
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
                  Icon(Icons.insert_drive_file_outlined, size: AppIconSize.standard, color: cs.primary),
                  const SizedBox(width: 10),
                  Text(
                    'Keyfiles (optional)',
                    style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600, color: cs.onSurface),
                  ),
                ],
              ),
              TextButton.icon(
                onPressed: (enabled && !picking) ? onPick : null,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: picking
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add file'),
              ),
            ],
          ),
          if (keyfiles.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: keyfiles
                  .map(
                    (k) => InputChip(
                      avatar: Icon(Icons.description_outlined, size: 16, color: cs.onSurfaceVariant),
                      label: Text(k.displayName, style: textTheme.bodySmall, overflow: TextOverflow.ellipsis),
                      onDeleted: enabled ? () => onRemove(k) : null,
                      deleteIconColor: cs.error,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                      backgroundColor: cs.surfaceContainerHigh,
                    ),
                  )
                  .toList(),
            ),
          ] else ...[
            const SizedBox(height: 8),
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
