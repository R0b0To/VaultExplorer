import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/theme/file_manager_skin_scope.dart';
import 'package:vaultexplorer/data/models/file_manager_skin.dart';
import 'package:vaultexplorer/data/models/long_file_name_display_mode.dart';
import 'package:vaultexplorer/features/browser/widgets/file_name_label.dart';

/// Shared utility methods for grid and masonry views.
abstract final class GridCardUtils {
  /// Dynamically computes responsive icon size based on tile width and column count.
  static double calculateIconSize(
    BuildContext context,
    int columns, {
    double spacing = 8,
  }) {
    final width = MediaQuery.sizeOf(context).width;
    final tileWidth = (width - 20 - (columns - 1) * spacing) / columns;

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

  /// Whether the 3-dots button is offered at all. Mirrors the list layout's
  /// `showItemActionsMenu` setting; the button also needs [onMoreTap] and is
  /// hidden while selecting and on placeholders.
  final bool showMoreButton;
  final bool isPinned;
  final bool isBookmark;
  final bool isDocumentProviderMounted;
  final bool isSynced;
  final bool isPlaceholder;
  final Color? cardColor;

  /// Whether this card represents a folder rather than a file. Lets the active
  /// skin style the two independently (see [FileManagerSkin]).
  final bool isFolder;

  /// Pass [aspectRatio] for Masonry items. Leave null for standard GridView items.
  final double? aspectRatio;

  /// Corner radius of the card (and so of the clipped preview). 12 is the
  /// default rounded look; 0 gives square cards.
  final double cornerRadius;

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
    this.showMoreButton = true,
    this.isPinned = false,
    this.isBookmark = false,
    this.isDocumentProviderMounted = false,
    this.isSynced = false,
    this.isPlaceholder = false,
    this.cardColor,
    this.isFolder = false,
    this.aspectRatio,
    this.cornerRadius = 12.0,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final skin = FileManagerSkinScope.of(context);

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
        if ((isPinned || isBookmark || isDocumentProviderMounted || isSynced) && !isSelected)
          Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isPinned)
                      Icon(
                        Icons.push_pin_rounded,
                        size: 13,
                        color: cs.primary,
                      ),
                    if (isBookmark) ...[
                      if (isPinned) const SizedBox(width: 3),
                      Icon(
                        Icons.star_rounded,
                        size: 13,
                        color: context.semanticColors.bookmark,
                      ),
                    ],
                    if (isDocumentProviderMounted) ...[
                      if (isPinned || isBookmark) const SizedBox(width: 3),
                      Icon(
                        Icons.folder_shared_rounded,
                        size: 13,
                        color: cs.tertiary,
                      ),
                    ],
                    if (isSynced) ...[
                      if (isPinned || isBookmark || isDocumentProviderMounted)
                        const SizedBox(width: 3),
                      Icon(
                        Icons.sync_rounded,
                        size: 13,
                        color: cs.primary,
                      ),
                    ],
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
        if (showMoreButton &&
            onMoreTap != null &&
            !isSelectionMode &&
            !isPlaceholder)
          // Top-right is free here: the selection check and the placeholder
          // spinner, the other occupants of this corner, both exclude it.
          LayoutBuilder(
            builder: (context, constraints) {
              // Dense grids have tiny tiles; a full-size button would hide
              // too much of the thumbnail.
              final compact = constraints.maxWidth < 100;
              final size = compact ? 22.0 : 28.0;
              return Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: EdgeInsets.all(compact ? 3 : 4),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHigh.withValues(alpha: 0.82),
                      shape: BoxShape.circle,
                    ),
                    child: SizedBox(
                      width: size,
                      height: size,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        iconSize: compact ? 16 : 18,
                        color: cs.onSurface,
                        icon: const Icon(Icons.more_vert_rounded),
                        onPressed: onMoreTap,
                      ),
                    ),
                  ),
                ),
              );
            },
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
        style: skin.nameStyle(
          textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
          ),
          isDir: isFolder,
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

    // The card behind the preview: tinted (classic), a thin outline, or no
    // box at all, per the active skin. Selection always wins so it stays
    // visible whatever the skin.
    Color fill = Colors.transparent;
    BorderSide side = BorderSide.none;
    if (isSelected) {
      fill = cs.primaryContainer.withValues(alpha: 0.3);
      side = BorderSide(color: cs.primary, width: 2.0);
    } else {
      switch (skin.styleFor(isDir: isFolder).container) {
        case SkinContainerStyle.filled:
          fill = cardColor ?? GridCardUtils.folderCardColor(cs, isMounted: false);
          side = BorderSide.none;
        case SkinContainerStyle.outlined:
          fill = Colors.transparent;
          side = BorderSide(color: cs.outlineVariant, width: 1.2);
        case SkinContainerStyle.none:
          break;
      }
    }

    Widget cell = Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(cornerRadius),
        side: side,
      ),
      color: fill,
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