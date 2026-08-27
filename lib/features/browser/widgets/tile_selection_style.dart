import 'package:flutter/material.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/file_manager_toolbar_config.dart';
import 'package:vaultexplorer/features/browser/widgets/highlighted_text.dart';

abstract final class TileSelectionStyle {
  static Color selectedBackground(ColorScheme cs) =>
      cs.primaryContainer.withValues(alpha: 0.3);
  static const contentPadding = EdgeInsets.symmetric(
    horizontal: 16,
    vertical: 4,
  );
  static FontWeight titleWeight(bool selected) =>
      selected ? FontWeight.w500 : FontWeight.normal;
  static Color leadingIconColor(
    ColorScheme cs, {
    required bool selected,
    required Color unselectedColor,
  }) => selected ? cs.primary : unselectedColor;
}

class TileSelectionIndicator extends StatelessWidget {
  final bool selected;
  const TileSelectionIndicator({super.key, required this.selected});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Icon(
      selected
          ? Icons.check_circle_rounded
          : Icons.radio_button_unchecked_rounded,
      size: 20,
      color: selected ? cs.primary : cs.outline,
    );
  }
}

class FileRowShell extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final bool isCompact;
  final double zoomLevel;
  final Color unselectedIconBackground;
  final String displayName;
  final String? searchQuery;
  final RawEntry entry;
  final List<FileDetailColumn> detailColumns;
  final Widget? trailing;
  final bool isSelected;
  final bool isSelectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final Widget? iconBadge;
  final Widget? customLeading;
  
  const FileRowShell({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.unselectedIconBackground,
    required this.displayName,
    this.searchQuery,
    required this.entry,
    this.detailColumns = const [FileDetailColumn.date, FileDetailColumn.size],
    this.trailing,
    required this.isSelected,
    this.isSelectionMode = false,
    required this.onTap,
    required this.onLongPress,
    this.isCompact = false,
    this.zoomLevel = 1.0,
    this.iconBadge,
    this.customLeading,
  });

  Widget _buildColumnWidget(
    FileDetailColumn col,
    BuildContext context, {
    bool isRightmost = false,
  }) {
    final double width = switch (col) {
      FileDetailColumn.date => 75,
      FileDetailColumn.size => 44,
      FileDetailColumn.type => 46,
    };
    final effectiveWidth = width * zoomLevel;

    if (isRightmost && isSelected) {
      return SizedBox(
        width: effectiveWidth,
        child: const Align(
          alignment: Alignment.centerRight,
          child: TileSelectionIndicator(selected: true),
        ),
      );
    }

    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final String text = switch (col) {
      FileDetailColumn.date => formatEntryDate(entry.modifiedSecs),
      FileDetailColumn.size => entry.isDir ? '' : formatBytes(entry.sizeBytes),
      FileDetailColumn.type => _getTypeLabel(entry, context),
    };

    return SizedBox(
      width: effectiveWidth,
      child: Text(
        text,
        textAlign: TextAlign.right,
        style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  static String _getTypeLabel(RawEntry entry, BuildContext context) {
    if (entry.isDir) return context.l10n.nounFolderCapitalized;
    final name = entry.name;
    if (!name.contains('.')) return context.l10n.nounFileCapitalized;
    final ext = name.split('.').last.trim();
    if (ext.isEmpty) return context.l10n.nounFileCapitalized;
    return ext.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final squircleBackground =
        isSelected ? cs.primaryContainer : unselectedIconBackground;
    final effectiveTrailing = trailing ??
        (entry.isPlaceholder
            ? SizedBox(
                width: 16 * zoomLevel,
                height: 16 * zoomLevel,
                child: CircularProgressIndicator(
                  strokeWidth: 2.0,
                  color: cs.primary.withValues(alpha: 0.8),
                ),
              )
            : null);
    Widget row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: entry.isPlaceholder ? null : onTap,
        onLongPress: entry.isPlaceholder ? null : onLongPress,
        child: Ink(
          decoration: BoxDecoration(
            color: isSelected
                ? TileSelectionStyle.selectedBackground(cs)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          padding: EdgeInsets.symmetric(
            horizontal: 12,
            vertical: (isCompact ? 4 : 10) * zoomLevel,
          ),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: (isCompact ? 32 : 44) * zoomLevel,
                    height: (isCompact ? 32 : 44) * zoomLevel,
                    decoration: BoxDecoration(
                      color: squircleBackground,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: customLeading ??
                        Icon(
                          icon,
                          size: AppIconSize.action * zoomLevel,
                          color: TileSelectionStyle.leadingIconColor(
                            cs,
                            selected: isSelected,
                            unselectedColor: iconColor,
                          ),
                        ),
                  ),
                  if (iconBadge != null && !isSelected)
                    Positioned(
                      left: -6,
                      top: -6,
                      child: iconBadge!,
                    ),
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: HighlightedText(
                  text: displayName,
                  query: searchQuery,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: TileSelectionStyle.titleWeight(isSelected),
                    letterSpacing: 0,
                  ),
                ),
              ),
              if (!isCompact && detailColumns.isNotEmpty) ...[
                for (int i = 0; i < detailColumns.length; i++) ...[
                  const SizedBox(width: 8),
                  _buildColumnWidget(
                    detailColumns[i],
                    context,
                    isRightmost: i == detailColumns.length - 1,
                  ),
                ],
              ],
              if (isCompact && isSelected && isSelectionMode) ...[
                const SizedBox(width: 8),
                const TileSelectionIndicator(selected: true),
              ] else if (effectiveTrailing != null) ...[
                const SizedBox(width: 8),
                effectiveTrailing,
              ],
            ],
          ),
        ),
      ),
    );
    if (entry.isPlaceholder) {
      row = Opacity(opacity: 0.5, child: row);
    }
    return row;
  }
}