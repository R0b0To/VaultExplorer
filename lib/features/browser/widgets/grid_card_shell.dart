import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/data/models/long_file_name_display_mode.dart';
import 'package:vaultexplorer/features/browser/widgets/file_name_label.dart';

/// Shared utility methods for grid and masonry views.
abstract final class GridCardUtils {
  /// Dynamically computes responsive icon size based on tile width and column count.
  static double calculateIconSize(BuildContext context, int columns) {
    final width = MediaQuery.sizeOf(context).width;
    final tileWidth = (width - 20 - (columns - 1) * 8) / columns;

    final factor = switch (columns) {
      1 => 0.85,
      2 => 0.58, // ~105px in portrait
      3 => 0.50, // ~58px
      4 => 0.46, // ~42px
      _ => 0.42, // ~32-36px for 5+ columns
    };

    return (tileWidth * factor).clamp(32.0, 200.0);
  }

  /// Adapts column count when rotating between portrait and landscape
  /// so blocks retain a consistent physical size.
  static int adaptColumnsForOrientation({
    required Orientation currentOrientation,
    required Orientation? lastOrientation,
    required int currentColumns,
    required int minColumns,
    required int maxColumns,
  }) {
    if (lastOrientation != null && lastOrientation != currentOrientation) {
      if (currentOrientation == Orientation.landscape) {
        return (currentColumns * 1.7).round().clamp(minColumns, maxColumns);
      } else {
        return (currentColumns / 1.7).round().clamp(minColumns, maxColumns);
      }
    }
    return currentColumns.clamp(minColumns, maxColumns);
  }

  static Color folderCardColor(ColorScheme cs, {required bool isMounted}) {
    return isMounted
        ? cs.tertiaryContainer.withValues(alpha: 0.32)
        : cs.secondaryContainer.withValues(alpha: 0.32);
  }
}

/// Selection checkmark badge.
class GridCheckBadge extends StatelessWidget {
  final Color color;
  final Color onColor;

  const GridCheckBadge({
    super.key,
    required this.color,
    required this.onColor,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Icon(
          Icons.check_rounded,
          size: AppIconSize.inline,
          color: onColor,
        ),
      );
}

/// Unified card container for both [FileGridView] and [FileMasonryView].
class GridCardShell extends StatelessWidget {
  final Widget preview;
  final String label;
  final String? searchQuery;
  final bool isSelected;
  final bool isSelectionMode;
  final bool showFileName;
  final LongFileNameDisplayMode longFileNameMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback? onMoreTap;
  final bool isPinned;
  final bool isBookmark;
  final bool isPlaceholder;
  final Color? cardColor;

  /// Pass [aspectRatio] for Masonry items. Leave null for standard GridView items.
  final double? aspectRatio;

  const GridCardShell({
    super.key,
    required this.preview,
    required this.label,
    this.searchQuery,
    required this.isSelected,
    required this.isSelectionMode,
    this.showFileName = true,
    this.longFileNameMode = LongFileNameDisplayMode.ellipsizeEnd,
    required this.onTap,
    required this.onLongPress,
    this.onMoreTap,
    this.isPinned = false,
    this.isBookmark = false,
    this.isPlaceholder = false,
    this.cardColor,
    this.aspectRatio,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    Widget previewStack = Stack(
      fit: StackFit.expand,
      children: [
        preview,
        if (isSelected)
          DecoratedBox(
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.12),
            ),
          ),
        if ((isPinned || isBookmark) && !isSelected)
          Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh.withValues(alpha: 0.85),
                  shape: BoxShape.circle,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isPinned)
                      Icon(
                        Icons.push_pin_rounded,
                        size: 14,
                        color: cs.primary,
                      ),
                    if (isBookmark)
                      Icon(
                        Icons.star_rounded,
                        size: 14,
                        color: context.semanticColors.bookmark,
                      ),
                  ],
                ),
              ),
            ),
          ),
        if (isSelected)
          Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: GridCheckBadge(
                color: cs.primary,
                onColor: cs.onPrimary,
              ),
            ),
          ),
        if (isPlaceholder)
          Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh.withValues(alpha: 0.85),
                  shape: BoxShape.circle,
                ),
                child: SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.0,
                    color: cs.primary,
                  ),
                ),
              ),
            ),
          ),
      ],
    );

    Widget footer = Container(
      alignment: Alignment.center,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: FileNameLabel(
        text: label,
        query: searchQuery,
        mode: longFileNameMode,
        style: textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: cs.onSurface,
        ),
      ),
    );

    Widget body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: aspectRatio != null ? MainAxisSize.min : MainAxisSize.max,
      children: [
        if (aspectRatio != null)
          AspectRatio(aspectRatio: aspectRatio!, child: previewStack)
        else
          Expanded(child: previewStack),
        if (showFileName) footer,
      ],
    );

    Widget cell = Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isSelected
            ? BorderSide(color: cs.primary, width: 2.0)
            : BorderSide.none,
      ),
      color: isSelected
          ? cs.primaryContainer.withValues(alpha: 0.3)
          : (cardColor ?? GridCardUtils.folderCardColor(cs, isMounted: false)),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: body,
      ),
    );

    if (isPlaceholder) {
      cell = Opacity(opacity: 0.5, child: cell);
    }
    return cell;
  }
}