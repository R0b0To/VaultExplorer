import 'package:flutter/material.dart';
import '../../../theme.dart';
import 'highlighted_text.dart';

/// Single source of truth for the selection-mode visual language shared by
/// every row-style list tile in the file browser ([FileTile], [DirectoryTile]).
///
/// ### Why this exists
/// [FileTile] and [DirectoryTile] previously each hard-coded the same five
/// decisions independently:
///   - selected background tint (`cs.primaryContainer.withValues(alpha:0.3)`)
///   - trailing check / unchecked-circle icon + size + color
///   - selected title font weight
///   - content padding
///   - `dense: true`
///
/// A change to any of these (e.g. swapping the check icon, adjusting the
/// tint alpha) required editing both files identically, with no compiler
/// error if one was missed. This class centralises those decisions.
///
/// [FileGridView]'s `_GridCell` intentionally does NOT use this — the grid
/// uses a different visual language (full-cell tint + corner badge,
/// appropriate for a card-style cell rather than a row), so sharing here
/// would be a false abstraction across two genuinely different layouts.
abstract final class TileSelectionStyle {
  /// Background tint applied to a selected [ListTile] via `selectedTileColor`.
  static Color selectedBackground(ColorScheme cs) =>
      cs.primaryContainer.withValues(alpha: 0.3);

  /// Standard content padding shared by both row tiles.
  static const contentPadding = EdgeInsets.symmetric(
    horizontal: 16,
    vertical: 4,
  );

  /// Title [FontWeight] — slightly bolder when selected so the row reads as
  /// "active" without changing size or color.
  static FontWeight titleWeight(bool selected) =>
      selected ? FontWeight.w500 : FontWeight.normal;

  /// Leading icon color: primary when selected, otherwise [unselectedColor]
  /// (the tile's own type-specific color — e.g. a folder's secondary tint or
  /// a file's extension-based color).
  static Color leadingIconColor(
    ColorScheme cs, {
    required bool selected,
    required Color unselectedColor,
  }) => selected ? cs.primary : unselectedColor;
}

/// The trailing checkbox-style indicator shown on a row tile while
/// [selectionMode] is active.
///
/// Renders a filled check circle when [selected], an empty outline circle
/// otherwise. Both [FileTile] and [DirectoryTile] render this identically;
/// extracting it means the indicator can only ever look one way across the
/// whole list view.
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

/// Shared row shell for [DirectoryTile] and [FileTile] — the squircle
/// leading icon, name, date column, and trailing slot, wrapped in the
/// tap/long-press/selection treatment from [TileSelectionStyle].

class FileRowShell extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final bool isCompact;
  final double zoomLevel;

  /// Squircle background when NOT selected — differs between directories
  /// (a tinted secondaryContainer) and files (surfaceContainerHighest).
  final Color unselectedIconBackground;

  final String displayName;
  final String? searchQuery;
  final String dateStr;
  final Widget trailing;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const FileRowShell({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.unselectedIconBackground,
    required this.displayName,
    this.searchQuery,
    required this.dateStr,
    required this.trailing,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
    this.isCompact = false,
    this.zoomLevel = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final squircleBackground =
        isSelected ? cs.primaryContainer : unselectedIconBackground;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(16), // Rounded ripples
        onTap: onTap,
        onLongPress: onLongPress,
        child: Ink(
          decoration: BoxDecoration(
            color: isSelected
                ? TileSelectionStyle.selectedBackground(cs)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          padding: EdgeInsets.symmetric(
            horizontal: 12,
            vertical: (isCompact ? 4 : 10) * zoomLevel, // Plush interior targets
          ),
          child: Row(
            children: [
              // 1. The plush "Squircle" leading icon
              Container(
                width: (isCompact ? 32 : 44) * zoomLevel,
                height: (isCompact ? 32 : 44) * zoomLevel,
                decoration: BoxDecoration(
                  color: squircleBackground,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: AppIconSize.action * zoomLevel,
                  color: TileSelectionStyle.leadingIconColor(
                    cs,
                    selected: isSelected,
                    unselectedColor: iconColor,
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // 2. Name
              Expanded(
                child: HighlightedText(
                  text: displayName,
                  query: searchQuery,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: TileSelectionStyle.titleWeight(isSelected),
                    letterSpacing: 0,
                  ),
                ),
              ),
              if (!isCompact) ...[
                const SizedBox(width: 12),

                // 3. Date column
                SizedBox(
                  width: 80, // Reduced from 90 to give more space to file name
                  child: Text(
                    dateStr,
                    textAlign: TextAlign.right,
                    style: textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              
              if (!isCompact) ...[
                const SizedBox(width: 12),

                // 4. Trailing column (size, selection indicator, or "⋯" menu)
                SizedBox(width: 80, child: trailing), // Reduced from 96
              ] else ...[
                const SizedBox(width: 8),
                trailing,
              ],
            ],
          ),
        ),
      ),
    );
  }
}