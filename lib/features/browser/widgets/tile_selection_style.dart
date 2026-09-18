import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
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
  ///
  /// The default (false) treats [customLeading] as edge-to-edge artwork:
  /// it's filled into the tinted squircle and clipped to it, which is
  /// right for a photo or video frame but wrong for an app icon -- the
  /// tint shows as a coloured square behind an icon that already has a
  /// background of its own, and the rounded clip shaves the icon's
  /// corners off. When true the box contributes nothing visually: no
  /// tint, no clip, just a small inset so the icon doesn't sit flush
  /// against the row's text.
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

  String _columnText(FileDetailColumn col, BuildContext context) =>
      switch (col) {
        FileDetailColumn.date => formatEntryDate(entry.modifiedSecs),
        FileDetailColumn.size => entry.isDir ? '' : formatBytes(entry.sizeBytes),
        FileDetailColumn.type => _getTypeLabel(entry, context),
      };

  Widget _buildColumnWidget(
    FileDetailColumn col,
    BuildContext context,
  ) {
    final double width = switch (col) {
      FileDetailColumn.date => 50,
      FileDetailColumn.size => 50,
      FileDetailColumn.type => 46,
    };
    final effectiveWidth = width * zoomLevel;

    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SizedBox(
      width: effectiveWidth,
      child: Text(
        _columnText(col, context),
        textAlign: TextAlign.right,
        style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: FileNameLabel(
            text: displayName,
            query: searchQuery,
            mode: longFileNameMode,
            style: textTheme.titleMedium?.copyWith(
              fontWeight: TileSelectionStyle.titleWeight(isSelected),
              letterSpacing: 0,
              height: 1.2,
            ),
          ),
        ),
        if (caption.isNotEmpty) ...[
          const SizedBox(height: 2),
          Flexible(
            child: Text(
              caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                height: 1.2,
              ),
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
    final squircleBackground =
        isSelected ? cs.primaryContainer : unselectedIconBackground;
    // See [customLeadingIsIcon]: a self-contained icon gets no tint, no
    // clip and a small inset; everything else keeps the filled squircle.
    final bareIconLeading = customLeading != null && customLeadingIsIcon;
    final leadingBackground =
        bareIconLeading ? Colors.transparent : squircleBackground;
    final leadingClip = bareIconLeading ? Clip.none : Clip.antiAlias;
    final leadingPadding =
        bareIconLeading ? const EdgeInsets.all(2.0) : EdgeInsets.zero;
    final effectiveTrailing = trailing;
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
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  if (entry.isPlaceholder || onIconTap == null)
                    Container(
                      width: (isCompact ? 32 : 44) * zoomLevel,
                      height: (isCompact ? 32 : 44) * zoomLevel,
                      padding: leadingPadding,
                      decoration: BoxDecoration(
                        color: leadingBackground,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      clipBehavior: leadingClip,
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
                    )
                  else
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: onIconTap,
                      child: Container(
                        width: (isCompact ? 32 : 44) * zoomLevel,
                        height: (isCompact ? 32 : 44) * zoomLevel,
                        padding: leadingPadding,
                        decoration: BoxDecoration(
                          color: leadingBackground,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        clipBehavior: leadingClip,
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
                    ),
                  if (entry.isPlaceholder)
                    Positioned.fill(
                      child: Center(
                        child: SizedBox(
                          width: (isCompact ? 16 : 20) * zoomLevel,
                          height: (isCompact ? 16 : 20) * zoomLevel,
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
                child: (isDetailed && !entry.isDir)
                    ? _buildDetailedNameBlock(context, textTheme, cs)
                    : FileNameLabel(
                        text: displayName,
                        query: searchQuery,
                        mode: longFileNameMode,
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: TileSelectionStyle.titleWeight(isSelected),
                          letterSpacing: 0,
                        ),
                      ),
              ),
              if (!isCompact && !isDetailed && detailColumns.isNotEmpty) ...[
                for (int i = 0; i < detailColumns.length; i++) ...[
                  const SizedBox(width: 8),
                  _buildColumnWidget(detailColumns[i], context),
                ],
              ],
              if (isSelectionMode) ...[
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