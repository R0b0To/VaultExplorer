import 'package:flutter/material.dart';
import '../../../utils/file_type_utils.dart';
import '../../../utils/format_utils.dart';
import '../../../utils/raw_entry.dart';
import '../../../theme.dart'; // Design tokens for AppRadius, AppIconSize, AppSpacing
import 'tile_selection_style.dart';

/// Stateless renderer for a modern inset list of directory entries.
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
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
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

  /// Builds the modern trailing layout containing either the selection indicator,
  /// the file size, or the "More" (⋯) actions menu.
  Widget _buildTrailingColumn({
    required BuildContext context,
    required bool isDir,
    required String sizeStr,
    required bool isSelected,
    required String rawItem,
  }) {
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
            ? TileSelectionIndicator(selected: true)
            : (isDir ? const SizedBox.shrink() : sizeWidget),
      );
    }

    if (isDir) {
      return const SizedBox.shrink();
    }

    // Fulfills the missing onFileLongMenu requirement natively
    if (onFileLongMenu != null) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: sizeWidget,
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 32,
            height: 32,
            child: IconButton(
              padding: EdgeInsets.zero,
              iconSize: 20,
              color: cs.onSurfaceVariant,
              icon: const Icon(Icons.more_horiz_rounded), // Standard MD3 Kebab
              onPressed: () => onFileLongMenu!(rawItem),
            ),
          ),
        ],
      );
    }

    return Align(
      alignment: Alignment.centerRight,
      child: sizeWidget,
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = dirs.length + files.length;
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      children: [
        // Modern MD3 drops full-width dividers in favor of whitespace padding
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            // Increased safe padding for bottom sheets & floating clipboards
            padding: EdgeInsets.only(
              top: 0,
              bottom: 112 + MediaQuery.paddingOf(context).bottom,
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
                vaultIcon = vaultIconForExt(ext);
                vaultColor = vaultColorForExt(ext);

                if (vaultIcon != null) {
                  final parts = displayName.split('.');
                  if (parts.length > 1) {
                    parts.removeLast();
                    displayName = parts.join('.');
                  }
                }
              }

              final dateStr = _formatDateColumn(entry.modifiedSecs);
              final sizeStr = isDir || vaultIcon != null
                  ? ''
                  : formatBytes(entry.sizeBytes);

              final displayIcon = isDir
                  ? Icons.folder_rounded
                  : (vaultIcon ?? iconForFile(entry.name));

              final iconColor = isDir
                  ? cs.secondary
                  : (vaultColor ?? colorForFile(entry.name));

              // Tonal mapping for the icon's background "squircle"
              final squircleBackground = isSelected
                  ? cs.primaryContainer
                  : (isDir
                      ? cs.secondaryContainer.withValues(alpha: 0.4)
                      : cs.surfaceContainerHighest);

              // ── Modern Inset List Item ──
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16), // Rounded Ripples
                  onTap: () => isDir ? onDirTap(rawItem) : onFileTap(rawItem),
                  onLongPress: () => onItemLongPress(rawItem),
                  child: Ink(
                    decoration: BoxDecoration(
                      color: isSelected
                          ? TileSelectionStyle.selectedBackground(cs)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10, // Plush interior targets
                    ),
                    child: Row(
                      children: [
                        // 1. The plush "Squircle" Leading Icon
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: squircleBackground,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            displayIcon,
                            size: AppIconSize.action,
                            color: TileSelectionStyle.leadingIconColor(
                              cs,
                              selected: isSelected,
                              unselectedColor: iconColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),

                        // 2. File Name (Upgraded to titleMedium for better legibility)
                        Expanded(
                          child: Text(
                            displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.titleMedium?.copyWith(
                              fontWeight: TileSelectionStyle.titleWeight(
                                isSelected,
                              ),
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),

                        // 3. Date Column
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
                        const SizedBox(width: 12),

                        // 4. Trailing Column (Size & Actions)
                        SizedBox(
                          width: 96,
                          child: _buildTrailingColumn(
                            context: context,
                            isDir: isDir,
                            sizeStr: sizeStr,
                            isSelected: isSelected,
                            rawItem: rawItem,
                          ),
                        ),
                      ],
                    ),
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