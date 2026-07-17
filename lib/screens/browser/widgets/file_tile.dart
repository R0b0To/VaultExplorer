import 'package:flutter/material.dart';
import '../../../utils/file_type_utils.dart';
import '../../../utils/format_utils.dart';
import '../../../utils/raw_entry.dart';
import 'tile_selection_style.dart';

/// Row renderer for a single file entry in [FileListView].
class FileTile extends StatelessWidget {
  /// Raw wire-format entry, e.g. `"report.pdf|48213|1700000000"`.
  final String rawItem;
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final ValueChanged<String>? onLongMenu;

  const FileTile({
    super.key,
    required this.rawItem,
    required this.isSelectionMode,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
    this.onLongMenu,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final entry = RawEntry.parse(rawItem);

    String displayName = entry.name;
    final ext = displayName.split('.').last;
    final vaultIcon = vaultIconForExt(ext);
    final vaultColor = vaultColorForExt(ext);

    if (vaultIcon != null) {
      final parts = displayName.split('.');
      if (parts.length > 1) {
        parts.removeLast();
        displayName = parts.join('.');
      }
    }

    final sizeStr = vaultIcon != null ? '' : formatBytes(entry.sizeBytes);
    final displayIcon = vaultIcon ?? iconForFile(entry.name);
    final iconColor = vaultColor ?? colorForFile(entry.name);

    return FileRowShell(
      icon: displayIcon,
      iconColor: iconColor,
      unselectedIconBackground: cs.surfaceContainerHighest,
      displayName: displayName,
      dateStr: formatEntryDate(entry.modifiedSecs),
      trailing: _buildTrailing(context, sizeStr),
      isSelected: isSelected,
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }

  Widget _buildTrailing(BuildContext context, String sizeStr) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final sizeWidget = Text(
      sizeStr,
      textAlign: TextAlign.right,
      style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    if (isSelectionMode) {
      return Align(
        alignment: Alignment.centerRight,
        child: isSelected
            ? const TileSelectionIndicator(selected: true)
            : sizeWidget,
      );
    }

    if (onLongMenu != null) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Expanded(
            child: Align(alignment: Alignment.centerRight, child: sizeWidget),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 32,
            height: 32,
            child: IconButton(
              padding: EdgeInsets.zero,
              iconSize: 20,
              color: cs.onSurfaceVariant,
              icon: const Icon(Icons.more_horiz_rounded), // Standard MD3 kebab
              onPressed: () => onLongMenu!(rawItem),
            ),
          ),
        ],
      );
    }

    return Align(alignment: Alignment.centerRight, child: sizeWidget);
  }
}