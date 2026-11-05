// Small building blocks shared by the Storage Analyzer's views: the colour
// language for file types, one row for a file or folder, the breadcrumb, and
// the bundle of callbacks the screen hands to every view.
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/features/tools/widgets/storage_analyzer_controller.dart';

/// Colours for one file type. [accent] is the saturated colour (legend dots,
/// share bars); [fill]/[onFill] are a matching container pair that keeps text
/// readable on a treemap tile in both light and dark themes.
class StorageCategoryStyle {
  const StorageCategoryStyle({
    required this.accent,
    required this.fill,
    required this.onFill,
  });

  final Color accent;
  final Color fill;
  final Color onFill;
}

/// The colour language for file types. Pass '' for folders.
StorageCategoryStyle storageCategoryStyle(
  BuildContext context,
  String category,
) {
  final cs = context.colors;
  final semantic = context.semanticColors;
  switch (category) {
    case StorageCategory.images:
      return StorageCategoryStyle(
        accent: cs.primary,
        fill: cs.primaryContainer,
        onFill: cs.onPrimaryContainer,
      );
    case StorageCategory.videos:
      return StorageCategoryStyle(
        accent: cs.tertiary,
        fill: cs.tertiaryContainer,
        onFill: cs.onTertiaryContainer,
      );
    case StorageCategory.audio:
      return StorageCategoryStyle(
        accent: cs.secondary,
        fill: cs.secondaryContainer,
        onFill: cs.onSecondaryContainer,
      );
    case StorageCategory.documents:
      return StorageCategoryStyle(
        accent: semantic.warning,
        fill: semantic.warningContainer,
        onFill: semantic.onWarningContainer,
      );
    case StorageCategory.archives:
      return StorageCategoryStyle(
        accent: semantic.success,
        fill: semantic.successContainer,
        onFill: semantic.onSuccessContainer,
      );
    case StorageCategory.other:
      return StorageCategoryStyle(
        accent: cs.outline,
        fill: cs.surfaceContainerHighest,
        onFill: cs.onSurfaceVariant,
      );
    default: // folders
      return StorageCategoryStyle(
        accent: cs.primary,
        fill: cs.surfaceContainerHigh,
        onFill: cs.onSurface,
      );
  }
}

String storageCategoryLabel(BuildContext context, String category) {
  final l10n = context.l10n;
  return switch (category) {
    StorageCategory.images => l10n.storageCategoryImages,
    StorageCategory.videos => l10n.storageCategoryVideos,
    StorageCategory.audio => l10n.storageCategoryAudio,
    StorageCategory.documents => l10n.storageCategoryDocuments,
    StorageCategory.archives => l10n.storageCategoryArchives,
    _ => l10n.storageCategoryOther,
  };
}

IconData storageCategoryIcon(String category) {
  return switch (category) {
    StorageCategory.images => Icons.image_outlined,
    StorageCategory.videos => Icons.movie_outlined,
    StorageCategory.audio => Icons.audiotrack_outlined,
    StorageCategory.documents => Icons.description_outlined,
    StorageCategory.archives => Icons.folder_zip_outlined,
    _ => Icons.insert_drive_file_outlined,
  };
}

/// The icon for a node: a folder, or the glyph of its file type.
IconData storageNodeIcon(StorageNode node) =>
    node.isDir ? Icons.folder_rounded : storageCategoryIcon(node.category);

/// "37%", or "<1%" for a sliver, or "" for nothing.
String storagePercentLabel(int part, int whole) {
  if (whole <= 0 || part <= 0) return '';
  final pct = part * 100 / whole;
  if (pct < 1) return '<1%';
  return '${pct.round()}%';
}

String? storageDateLabel(BuildContext context, int modifiedSecs) {
  if (modifiedSecs <= 0) return null;
  final dt = DateTime.fromMillisecondsSinceEpoch(modifiedSecs * 1000);
  return MaterialLocalizations.of(context).formatShortDate(dt);
}

/// What the views can ask the screen to do. Keeping these in one object lets
/// the views stay plain functions of (state, actions).
class StorageActions {
  const StorageActions({
    required this.onTap,
    required this.onLongPress,
    required this.onMore,
    required this.onNavigate,
  });

  /// A node was tapped. [drill] says whether a folder may be opened by that
  /// tap in this view (true in the map and folder list; false in flat lists,
  /// which have no folder to open into).
  final void Function(StorageNode node, bool drill) onTap;

  /// A node was long-pressed: start (or extend) a selection.
  final void Function(StorageNode node) onLongPress;

  /// The node's "more" button: opens its action sheet.
  final void Function(StorageNode node) onMore;

  /// A breadcrumb segment was tapped.
  final void Function(String path) onNavigate;
}

/// One file or folder as a list row: icon (or checkbox while selecting), name,
/// a one-line detail, its share of the parent as a bar, size, and a menu.
class StorageNodeTile extends StatelessWidget {
  const StorageNodeTile({
    super.key,
    required this.node,
    required this.parentBytes,
    required this.selected,
    required this.selecting,
    required this.drill,
    required this.actions,
    this.showPath = false,
  });

  final StorageNode node;

  /// What the share bar and percentage are measured against.
  final int parentBytes;
  final bool selected;

  /// Any selection exists, so rows show checkboxes.
  final bool selecting;
  final bool drill;
  final StorageActions actions;

  /// Show the full path as the detail line (for flat lists that mix folders).
  final bool showPath;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;
    final l10n = context.l10n;
    final style = storageCategoryStyle(
      context,
      node.isDir ? '' : node.category,
    );

    final date = storageDateLabel(context, node.modifiedSecs);
    final String detail;
    if (showPath) {
      detail = node.path;
    } else {
      final first = node.isDir
          ? l10n.storageAnalyzerFileCount(node.fileCount)
          : storageCategoryLabel(context, node.category);
      detail = date == null ? first : '$first · $date';
    }

    final double fraction = parentBytes > 0
        ? (node.sizeBytes / parentBytes).clamp(0.0, 1.0).toDouble()
        : 0.0;
    final pct = storagePercentLabel(node.sizeBytes, parentBytes);

    final leading = selecting
        ? SizedBox(
            width: 40,
            height: 40,
            child: Center(
              child: Checkbox(
                value: selected,
                onChanged: (_) => actions.onTap(node, false),
              ),
            ),
          )
        : Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: style.fill,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(
              storageNodeIcon(node),
              size: AppIconSize.standard,
              color: style.onFill,
            ),
          );

    return Material(
      color: selected
          ? cs.primaryContainer.withValues(alpha: 0.45)
          : Colors.transparent,
      child: InkWell(
        onTap: () => actions.onTap(node, drill),
        onLongPress: () => actions.onLongPress(node),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      node.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    if (!showPath) ...[
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.full),
                        child: LinearProgressIndicator(
                          value: fraction,
                          minHeight: 4,
                          backgroundColor: cs.surfaceContainerHighest,
                          color: style.accent,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatBytes(node.sizeBytes),
                    style: textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (pct.isNotEmpty && !showPath)
                    Text(
                      pct,
                      style: textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.more_vert_rounded),
                tooltip: l10n.optionsActionTooltip,
                visualDensity: VisualDensity.compact,
                onPressed: () => actions.onMore(node),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `Vault › Photos › 2023`, scrolling sideways when long and always showing the
/// deepest folder. Every segment but the last navigates to that folder.
class StorageBreadcrumb extends StatelessWidget {
  const StorageBreadcrumb({
    super.key,
    required this.rootLabel,
    required this.path,
    required this.onNavigate,
    this.trailing,
  });

  final String rootLabel;
  final String path;
  final void Function(String path) onNavigate;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final l10n = context.l10n;
    final segments = path.isEmpty ? const <String>[] : path.split('/');

    final crumbs = <Widget>[
      _Crumb(
        label: rootLabel,
        onTap: path.isEmpty ? null : () => onNavigate(''),
      ),
    ];
    var acc = '';
    for (var i = 0; i < segments.length; i++) {
      acc = acc.isEmpty ? segments[i] : '$acc/${segments[i]}';
      final target = acc;
      final isLast = i == segments.length - 1;
      crumbs.add(
        Icon(
          Icons.chevron_right_rounded,
          size: AppIconSize.small,
          color: cs.onSurfaceVariant,
        ),
      );
      crumbs.add(
        _Crumb(
          label: segments[i],
          onTap: isLast ? null : () => onNavigate(target),
        ),
      );
    }

    String parentOf(String p) {
      final slash = p.lastIndexOf('/');
      return slash < 0 ? '' : p.substring(0, slash);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_upward_rounded),
            tooltip: l10n.storageAnalyzerUpOneLevel,
            visualDensity: VisualDensity.compact,
            onPressed: path.isEmpty ? null : () => onNavigate(parentOf(path)),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(children: crumbs),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _Crumb extends StatelessWidget {
  const _Crumb({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;
    final isCurrent = onTap == null;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Text(
          label,
          maxLines: 1,
          style: textTheme.labelLarge?.copyWith(
            fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
            color: isCurrent ? cs.onSurface : cs.primary,
          ),
        ),
      ),
    );
  }
}
