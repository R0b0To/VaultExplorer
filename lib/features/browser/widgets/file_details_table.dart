import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/utils/responsive.dart';
import 'package:vaultexplorer/core/widgets/layout/resizable_split_pane.dart';
import 'package:vaultexplorer/data/models/file_manager_toolbar_config.dart';
import 'package:vaultexplorer/features/browser/mixins/sort_mixin.dart';

/// The details table: the compact list on a wide window, drawn the way a
/// desktop file manager draws it, with the date, size and type columns at
/// fixed widths so they line up from row to row, under a header whose labels
/// sort the folder when clicked.
///
/// The rows ([FileRowShell]) and the [FileDetailsHeader] read their column
/// widths from here, which is what keeps them aligned.
abstract final class FileDetailsTable {
  /// Height of the header row, before the list's zoom.
  static const double headerHeight = 30;

  /// The width a column gets at normal text size.
  static double columnWidth(FileDetailColumn column) => switch (column) {
    FileDetailColumn.date => 150,
    FileDetailColumn.size => 84,
    FileDetailColumn.type => 110,
  };

  /// Whether a column's text sits against the right edge (numbers) or the
  /// left (everything else).
  static bool alignsEnd(FileDetailColumn column) =>
      column == FileDetailColumn.size;

  /// The sort a click on [column]'s header applies.
  static SortBy sortFor(FileDetailColumn column) => switch (column) {
    FileDetailColumn.date => SortBy.date,
    FileDetailColumn.size => SortBy.size,
    FileDetailColumn.type => SortBy.extension,
  };

  /// Whether the list draws the details table: only in the compact layout
  /// (the densest of the list layouts), only with columns to show, and only
  /// when the window is wide enough for the columns, the name and the rest.
  static bool enabled(
    BuildContext context, {
    required bool isCompact,
    required List<FileDetailColumn> columns,
  }) => isCompact && columns.isNotEmpty && context.screen.useWideLayout;
}

/// The header of the details table. Clicking a label sorts by it; clicking
/// the sorted label again reverses the order, and an arrow shows both.
class FileDetailsHeader extends StatelessWidget {
  const FileDetailsHeader({
    super.key,
    required this.columns,
    required this.sortBy,
    required this.sortAscending,
    required this.onSortBy,
    required this.zoomLevel,
    required this.trailingSlotWidth,
    this.largeThumbnail = false,
  });

  final List<FileDetailColumn> columns;
  final SortBy sortBy;
  final bool sortAscending;
  final ValueChanged<SortBy> onSortBy;

  /// The list's zoom, so the columns scale with the rows below.
  final double zoomLevel;

  /// Whether the rows draw large thumbnails, which makes their leading icon
  /// bigger.
  final bool largeThumbnail;

  /// Room the rows keep at their right edge for the item menu button or the
  /// selection indicator, so the last column ends where the rows' does.
  final double trailingSlotWidth;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    // The rows are drawn under a text scale of the system's times the zoom.
    final factor = MediaQuery.textScalerOf(context).scale(1.0) * zoomLevel;
    // The row's leading icon (compact size, clamped) plus the gap after it.
    final leadingWidth = largeThumbnail
        ? (54.0 * zoomLevel).clamp(36.0, 80.0) + 10.0
        : (32.0 * zoomLevel).clamp(24.0, 64.0) + 10.0;

    return BleedRight(
      bottomBorder: cs.outlineVariant.withValues(alpha: 0.6),
      child: Container(
      height: FileDetailsTable.headerHeight,
      // 1 px of row margin plus 12 px of row padding on each side.
      padding: const EdgeInsets.symmetric(horizontal: 13),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: cs.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
      ),
      child: Row(
        children: [
          SizedBox(width: leadingWidth),
          Expanded(
            child: _HeaderCell(
              label: l10n.sortFieldName,
              sorted: sortBy == SortBy.name,
              ascending: sortAscending,
              alignEnd: false,
              onTap: () => onSortBy(SortBy.name),
            ),
          ),
          for (final column in columns) ...[
            const SizedBox(width: 8),
            SizedBox(
              width: FileDetailsTable.columnWidth(column) * factor,
              child: _HeaderCell(
                label: column.getLocalizedLabel(l10n),
                sorted: sortBy == FileDetailsTable.sortFor(column),
                ascending: sortAscending,
                alignEnd: FileDetailsTable.alignsEnd(column),
                onTap: () => onSortBy(FileDetailsTable.sortFor(column)),
              ),
            ),
          ],
          SizedBox(width: trailingSlotWidth),
        ],
      ),
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({
    required this.label,
    required this.sorted,
    required this.ascending,
    required this.alignEnd,
    required this.onTap,
  });

  final String label;
  final bool sorted;
  final bool ascending;
  final bool alignEnd;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: sorted ? cs.primary : cs.onSurfaceVariant,
      fontWeight: sorted ? FontWeight.w700 : FontWeight.w600,
    );
    final arrow = sorted
        ? Icon(
            ascending
                ? Icons.arrow_upward_rounded
                : Icons.arrow_downward_rounded,
            size: 14,
            color: cs.primary,
          )
        : null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Row(
        mainAxisAlignment: alignEnd
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (alignEnd && arrow != null) arrow,
          Flexible(
            child: Text(
              label,
              style: style,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
            ),
          ),
          if (!alignEnd && arrow != null) arrow,
        ],
      ),
    );
  }
}
