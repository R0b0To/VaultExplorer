import 'package:flutter/material.dart';
import '../../../utils/file_type_utils.dart';
import '../../../utils/format_utils.dart';
import '../../../utils/raw_entry.dart';
import '../../../theme.dart'; // Design tokens for AppRadius, AppIconSize, AppSpacing
import 'tile_selection_style.dart';

/// Stateless renderer for a flat columned list of directory entries.
class FileListView extends StatelessWidget {
  final List<String> dirs;
  final List<String> files;
  final bool isSelectionMode;
  final Set<String> selectedItems;

  final ValueChanged<String> onDirTap;
  final ValueChanged<String> onFileTap;
  final ValueChanged<String> onItemLongPress;

  /// Called when the trailing "⋯" icon on a file tile is tapped.
  final ValueChanged<String>? onFileLongMenu;

  const FileListView({
    super.key,
    required this.dirs,
    required this.files,
    required this.isSelectionMode,
    required this.selectedItems,
    required this.onDirTap,
    required this.onFileTap,
    required this.onItemLongPress,
    this.onFileLongMenu,
  });

  static const _months = [
    'Jan','Feb','Mar','Apr','May','Jun',
    'Jul','Aug','Sep','Oct','Nov','Dec',
  ];

  String _formatDateColumn(int secs) {
    if (secs <= 0) return '—';
    final dt = DateTime.fromMillisecondsSinceEpoch(secs * 1000);
    final now = DateTime.now();

    final isToday =
        dt.year == now.year && dt.month == now.month && dt.day == now.day;

    if (isToday) {
      final hr = dt.hour.toString().padLeft(2, '0');
      final min = dt.minute.toString().padLeft(2, '0');
      return '$hr:$min';
    }

    final monthAbbr = _months[dt.month - 1];
    return dt.year == now.year
        ? '$monthAbbr ${dt.day}'
        : '$monthAbbr ${dt.day}, ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final total = dirs.length + files.length;
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      children: [
        const Divider(),
        Expanded(
          child: ListView.builder(
            // Apply generous bottom padding so the last item can be scrolled fully 
            // into view above the FloatingActivityStack and the system gesture pill.
            padding: EdgeInsets.only(
              top: 4, 
              bottom: 100 + MediaQuery.paddingOf(context).bottom,
            ),
            itemCount: total,
            itemBuilder: (_, index) {
              final isDir = index < dirs.length;
              final rawItem = isDir ? dirs[index] : files[index - dirs.length];
              final isSelected = selectedItems.contains(rawItem);

              final entry = RawEntry.parse(rawItem);

              String displayName = entry.name;
              IconData? vaultIcon;
              Color? vaultColor;

              if (!isDir) {
                final ext = displayName.split('.').last;
                // Use the shared vault-type helpers from file_type_utils.dart.
                vaultIcon = vaultIconForExt(ext);
                vaultColor = vaultColorForExt(ext);

                // Strip the vault extension from the display name.
                if (vaultIcon != null) {
                  final parts = displayName.split('.');
                  if (parts.length > 1) {
                    parts.removeLast();
                    displayName = parts.join('.');
                  }
                }
              }

              final dateStr = _formatDateColumn(entry.modifiedSecs);
              // Hide sizes for vault items and directories
              final sizeStr = isDir || vaultIcon != null
                  ? ''
                  : formatBytes(entry.sizeBytes);

              final displayIcon = isDir
                  ? Icons.folder_rounded
                  : (vaultIcon ?? iconForFile(entry.name));

              final iconColor = isDir
                  ? cs.secondary
                  : (vaultColor ?? colorForFile(entry.name));

              return InkWell(
                onTap: () => isDir ? onDirTap(rawItem) : onFileTap(rawItem),
                onLongPress: () => onItemLongPress(rawItem),
                // Ink allows the MD3 ripple effect to render correctly over colored backgrounds
                child: Ink(
                  color: isSelected
                      ? TileSelectionStyle.selectedBackground(cs)
                      : Colors.transparent,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14, // Increased to meet MD3 48dp minimum touch target height
                  ),
                  child: Row(
                    children: [
                      Icon(
                        displayIcon,
                        size: AppIconSize.action,
                        color: TileSelectionStyle.leadingIconColor(
                          cs,
                          selected: isSelected,
                          unselectedColor: iconColor,
                        ),
                      ),
                      const SizedBox(width: 16),

                      Expanded(
                        flex: 5,
                        child: Text(
                          displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodyMedium?.copyWith(
                            fontWeight: TileSelectionStyle.titleWeight(
                              isSelected,
                            ),
                          ),
                        ),
                      ),

                      SizedBox(
                        width: 90,
                        child: Text(
                          dateStr,
                          textAlign: TextAlign.right,
                          style: textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),

                      if (isSelectionMode) ...[
                        if (isSelected) ...[
                          const SizedBox(width: 60),
                          TileSelectionIndicator(selected: isSelected),
                        ] else ...[
                          SizedBox(
                            width: 80,
                            child: Text(
                              sizeStr,
                              textAlign: TextAlign.right,
                              style: textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ] else if (isDir) ...[
                        const SizedBox(width: 80),
                      ] else ...[
                        SizedBox(
                          width: 80,
                          child: Text(
                            sizeStr,
                            textAlign: TextAlign.right,
                            style: textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}