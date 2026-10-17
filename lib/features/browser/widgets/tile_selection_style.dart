import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/theme/file_manager_skin_scope.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/file_manager_skin.dart';
import 'package:vaultexplorer/data/models/file_manager_toolbar_config.dart';
import 'package:vaultexplorer/data/models/long_file_name_display_mode.dart';
import 'package:vaultexplorer/features/browser/widgets/file_name_label.dart';

abstract final class TileSelectionStyle {
  static Color selectedBackground(ColorScheme cs) =>
      cs.primaryContainer.withValues(alpha: 0.3);
  static const contentPadding = EdgeInsets.symmetric(
    horizontal: 16,
    vertical: 4,
  );
  /// Name weight is deliberately the same selected or not: a heavier weight
  /// widens the glyphs, so selecting a row would visibly shift/reflow its name.
  static const FontWeight titleWeight = FontWeight.normal;
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

  /// Two-row layout: [displayName] on its own line, with the visible
  /// [detailColumns] (typically date and size) joined onto a second line
  /// underneath instead of right-aligned in fixed-width columns. Mutually
  /// exclusive with [isCompact] -- callers set at most one.
  final bool isDetailed;
  final double zoomLevel;
  final Color unselectedIconBackground;
  final String displayName;
  final String? searchQuery;
  final RawEntry entry;
  final List<FileDetailColumn> detailColumns;

  /// How to shorten [displayName] when it doesn't fit on one line. See
  /// [FileNameLabel].
  final LongFileNameDisplayMode longFileNameMode;
  final Widget? trailing;
  final bool hasTrailingSlot;
  final bool isSelected;
  final bool isSelectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  /// Tapping directly on the leading icon/thumbnail toggles this row's
  /// selection instead of triggering [onTap]. Null means the icon has no
  /// special tap behaviour of its own (it just contributes to the row's tap
  /// target as before).
  final VoidCallback? onIconTap;
  final Widget? iconBadge;
  final Widget? customLeading;

  /// Set when [customLeading] is an icon that stands on its own -- an
  /// APK's launcher icon, which already carries its own shape, background
  /// and padding as designed by whoever shipped the app.
  final bool customLeadingIsIcon;

  const FileRowShell({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.unselectedIconBackground,
    required this.displayName,
    this.searchQuery,
    required this.entry,
    this.detailColumns = const [FileDetailColumn.date, FileDetailColumn.size],
    this.longFileNameMode = LongFileNameDisplayMode.ellipsizeEnd,
    this.trailing,
    this.hasTrailingSlot = false,
    required this.isSelected,
    this.isSelectionMode = false,
    required this.onTap,
    required this.onLongPress,
    this.onIconTap,
    this.isCompact = false,
    this.isDetailed = false,
    this.zoomLevel = 1.0,
    this.iconBadge,
    this.customLeading,
    this.customLeadingIsIcon = false,
  });

  static double _columnBaseWidth(FileDetailColumn col) => switch (col) {
    FileDetailColumn.date => 100,
    FileDetailColumn.size => 60,
    FileDetailColumn.type => 50,
  };

  String _columnText(FileDetailColumn col, BuildContext context) =>
      switch (col) {
        FileDetailColumn.date => formatEntryDate(entry.modifiedSecs, context),
        FileDetailColumn.size => entry.isDir ? '' : formatBytes(entry.sizeBytes),
        FileDetailColumn.type => _getTypeLabel(entry, context),
      };

  double _columnWidth(FileDetailColumn col, BuildContext context) {
    final textScaler = MediaQuery.textScalerOf(context);
    final maxWidth = textScaler.scale(_columnBaseWidth(col));
    if (col != FileDetailColumn.date) return maxWidth;

    final painter = TextPainter(
      text: TextSpan(
        text: _columnText(col, context),
        style: Theme.of(context).textTheme.bodySmall,
      ),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: textScaler,
    )..layout();
    return painter.width > maxWidth ? maxWidth : painter.width;
  }

  Widget _buildColumnWidget(
    FileDetailColumn col,
    BuildContext context,
  ) {
    final effectiveWidth = _columnWidth(col, context);

    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SizedBox(
      width: effectiveWidth,
      child: Text(
        _columnText(col, context),
        textAlign: TextAlign.right,
        style: textTheme.bodySmall?.copyWith(
          color: FileManagerSkinScope.of(context).detailsColor ??
              cs.onSurfaceVariant,
        ),
        maxLines: 1,
        softWrap: false,
      ),
    );
  }

  /// Row-2 caption for [isDetailed] rows: the same [detailColumns] the
  /// columned layout shows (typically date and size), joined onto one line
  /// instead of right-aligned in separate slots. Folders only show the name.
  String _buildDetailedCaption(BuildContext context) {
    if (entry.isDir) return '';
    return detailColumns
        .map((col) => _columnText(col, context))
        .where((text) => text.isNotEmpty)
        .join('    ');
  }

  /// [isDetailed] rows' two-line name block: [displayName] on top, and the
  /// [_buildDetailedCaption] (date/size, etc.) underneath in a smaller,
  /// muted style -- both single-line, never wrapping onto a second visual
  /// line of their own.
  Widget _buildDetailedNameBlock(
    BuildContext context,
    TextTheme textTheme,
    ColorScheme cs,
  ) {
    final caption = _buildDetailedCaption(context);
    final skin = FileManagerSkinScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        FileNameLabel(
          text: displayName,
          query: searchQuery,
          mode: longFileNameMode,
          style: skin.nameStyle(
            textTheme.titleMedium?.copyWith(
              fontWeight: TileSelectionStyle.titleWeight,
              letterSpacing: 0,
              height: 1.2,
            ),
            isDir: entry.isDir,
          ),
        ),
        if (caption.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodySmall?.copyWith(
              color: skin.detailsColor?.withValues(alpha: 0.9) ??
                  cs.onSurfaceVariant.withValues(alpha: 0.7),
              height: 1.2,
            ),
          ),
        ],
      ],
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
    final textScaler = MediaQuery.textScalerOf(context);

    final skin = FileManagerSkinScope.of(context);
    final bareIconLeading = customLeading != null && customLeadingIsIcon;

    // The tile behind the leading icon/thumbnail. A skin can keep the tinted
    // fill (classic), swap it for a thin outline, or drop the box entirely.
    // An APK's own launcher icon is always drawn bare regardless of skin. A
    // thumbnail is still clipped to the rounded shape even with no box, so
    // photos keep their rounded corners.
    Color leadingBackground = Colors.transparent;
    BoxBorder? leadingBorder;
    if (!bareIconLeading) {
      switch (skin.styleFor(isDir: entry.isDir).container) {
        case SkinContainerStyle.filled:
          leadingBackground =
              isSelected ? cs.primaryContainer : unselectedIconBackground;
        case SkinContainerStyle.outlined:
          leadingBackground =
              isSelected ? cs.primaryContainer : Colors.transparent;
          leadingBorder = Border.all(
            color: isSelected ? cs.primary : cs.outlineVariant,
            width: 1.2,
          );
        case SkinContainerStyle.none:
          break;
      }
    }
    final leadingDecoration = BoxDecoration(
      color: leadingBackground,
      borderRadius: BorderRadius.circular(12),
      border: leadingBorder,
    );
    final leadingClip = bareIconLeading ? Clip.none : Clip.antiAlias;
    final leadingPadding =
        bareIconLeading ? const EdgeInsets.all(2.0) : EdgeInsets.zero;
    final effectiveTrailing = trailing;

    // Clamp zoom-scaled icon and spinner sizes so high zoom levels don't overwhelm the row.
    final leadingSize =
        ((isCompact ? 32.0 : 44.0) * zoomLevel).clamp(24.0, 64.0);
    final iconActionSize = (AppIconSize.action * zoomLevel).clamp(16.0, 36.0);
    final spinnerSize =
        ((isCompact ? 16.0 : 20.0) * zoomLevel).clamp(12.0, 28.0);

    Widget row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 1),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: entry.isPlaceholder ? null : onTap,
        onLongPress: entry.isPlaceholder ? null : onLongPress,
        child: Ink(
          decoration: isSelected
              ? BoxDecoration(
                  color: TileSelectionStyle.selectedBackground(cs),
                  borderRadius: BorderRadius.circular(16),
                )
              : null,
          padding: EdgeInsets.symmetric(
            horizontal: 12,
            vertical: (isCompact ? 4 : 10) * zoomLevel,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final availableWidth = constraints.maxWidth;
              // When there is no overflow button, a selection indicator can
              // use the last detail column's space instead of adding a new
              // trailing slot and pushing every column to the left.
              final canUseLastColumnForSelection =
                  !isCompact && !isDetailed && detailColumns.isNotEmpty;
              final trailingWidth =
                  (hasTrailingSlot ||
                      effectiveTrailing != null ||
                      (isSelectionMode && !canUseLastColumnForSelection))
                  ? 36.0
                  : 0.0;
              const leadingSpacing = 10.0;

              // Width detail columns need
              double columnsRequiredWidth = 0.0;
              if (!isCompact && detailColumns.isNotEmpty) {
                for (final col in detailColumns) {
                  columnsRequiredWidth +=
                      textScaler.scale(_columnBaseWidth(col)) + 8.0; // 8.0 for SizedBox
                }
              }

              // Minimum readable width for the file name label
              final minNameWidth = textScaler.scale(70.0);

              // Check if columns + name + icon + trailing can fit without overflow
              final canFitColumns = (availableWidth -
                      leadingSize -
                      leadingSpacing -
                      trailingWidth -
                      columnsRequiredWidth) >=
                  minNameWidth;

              // Auto-switch to the detailed 2-line layout when explicitly requested
              // OR when zoom/font size makes side-by-side columns unable to fit.
              final effectiveDetailed = isDetailed ||
                  (!isCompact && !canFitColumns && detailColumns.isNotEmpty);
              final selectionInLastColumn =
                  isSelectionMode &&
                  !hasTrailingSlot &&
                  !isCompact &&
                  !effectiveDetailed &&
                  detailColumns.isNotEmpty;

              return Row(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      if (entry.isPlaceholder || onIconTap == null)
                        Container(
                          width: leadingSize,
                          height: leadingSize,
                          padding: leadingPadding,
                          decoration: leadingDecoration,
                          clipBehavior: leadingClip,
                          child: customLeading ??
                              Icon(
                                icon,
                                size: iconActionSize,
                                color: TileSelectionStyle.leadingIconColor(
                                  cs,
                                  selected: isSelected,
                                  unselectedColor: iconColor,
                                ),
                              ),
                        )
                      else
                        InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: onIconTap,
                          child: Container(
                            width: leadingSize,
                            height: leadingSize,
                            padding: leadingPadding,
                            decoration: leadingDecoration,
                            clipBehavior: leadingClip,
                            child: customLeading ??
                                Icon(
                                  icon,
                                  size: iconActionSize,
                                  color: TileSelectionStyle.leadingIconColor(
                                    cs,
                                    selected: isSelected,
                                    unselectedColor: iconColor,
                                  ),
                                ),
                          ),
                        ),
                      if (entry.isPlaceholder)
                        Positioned.fill(
                          child: Center(
                            child: SizedBox(
                              width: spinnerSize,
                              height: spinnerSize,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.0,
                                color: cs.primary.withValues(alpha: 0.9),
                              ),
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
                    child: (effectiveDetailed && !entry.isDir)
                        ? _buildDetailedNameBlock(context, textTheme, cs)
                        : FileNameLabel(
                            text: displayName,
                            query: searchQuery,
                            mode: longFileNameMode,
                            style: skin.nameStyle(
                              textTheme.titleMedium?.copyWith(
                                fontWeight: TileSelectionStyle.titleWeight,
                                letterSpacing: 0,
                              ),
                              isDir: entry.isDir,
                            ),
                          ),
                  ),
                  if (!isCompact &&
                      !effectiveDetailed &&
                      detailColumns.isNotEmpty) ...[
                    for (int i = 0; i < detailColumns.length; i++) ...[
                      const SizedBox(width: 8),
                      if (selectionInLastColumn &&
                          i == detailColumns.length - 1)
                        SizedBox(
                          width: _columnWidth(detailColumns[i], context),
                          child: Center(
                            child: TileSelectionIndicator(selected: isSelected),
                          ),
                        )
                      else
                        _buildColumnWidget(detailColumns[i], context),
                    ],
                  ],
                  if (isSelectionMode && !selectionInLastColumn) ...[
                    const SizedBox(width: 4),
                    SizedBox(
                      width: 32,
                      height: 32,
                      child: Center(
                        child: TileSelectionIndicator(selected: isSelected),
                      ),
                    ),
                  ] else if (effectiveTrailing != null) ...[
                    const SizedBox(width: 4),
                    effectiveTrailing,
                  ],
                ],
              );
            },
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
