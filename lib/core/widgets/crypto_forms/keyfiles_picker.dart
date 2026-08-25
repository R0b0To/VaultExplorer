import 'package:flutter/material.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart' show KeyfileRef;

/// The "keyfiles" picker card — backs unlock sheets, container config, and creation flows.
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

    return Padding(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Row(
                  children: [
                    Icon(
                      Icons.insert_drive_file_outlined,
                      size: AppIconSize.small,
                      color: cs.primary,
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        context.l10n.keyfilesOptionalLabel,
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: (enabled && !picking) ? onPick : null,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  backgroundColor: cs.surfaceContainerHighest,
                  foregroundColor: cs.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                ),
                icon: picking
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_rounded, size: AppIconSize.small),
                label: Text(context.l10n.addFile),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (keyfiles.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: keyfiles
                  .map(
                    (k) => InputChip(
                      avatar: Icon(
                        Icons.description_outlined,
                        size: 16,
                        color: cs.primary,
                      ),
                      label: Text(
                        k.displayName,
                        style: textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      onDeleted: enabled ? () => onRemove(k) : null,
                      deleteIconColor: cs.error,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        side: BorderSide.none,
                      ),
                      backgroundColor: cs.surfaceContainerHighest,
                    ),
                  )
                  .toList(),
            ),
          ] else ...[
            Text(
              context.l10n.noKeyfilesAttached,
              style: textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}