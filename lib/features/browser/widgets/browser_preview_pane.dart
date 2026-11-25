import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/utils/file_type_utils.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/archive_context.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/features/browser/widgets/file_item_actions_sheet.dart'
    show FileThumbnailLeading;
import 'package:vaultexplorer/features/browser/widgets/folder_thumbnail_preview.dart';
import 'package:vaultexplorer/features/browser/widgets/preview_pane_content.dart';
import 'package:vaultexplorer/features/browser/widgets/preview_pane_media.dart';

/// A compact details and thumbnail panel for the file manager's current
/// selection. It sits beside a single pane and below the focused pane in
/// split desktop mode.
class BrowserPreviewPane extends StatelessWidget {
  final MountedContainer container;
  final Set<RawEntry> selectedItems;
  final List<RawEntry> currentItems;
  final String folderName;
  final int? folderTotalBytes;
  final bool folderStatsLoading;
  final String currentDirPath;
  final ThumbnailCacheMode cacheMode;
  final ThumbnailQuality quality;
  final bool isBottom;
  final ArchiveContext? archiveContext;
  final String? archiveRootPath;

  const BrowserPreviewPane({
    super.key,
    required this.container,
    required this.selectedItems,
    required this.currentItems,
    required this.folderName,
    this.folderTotalBytes,
    this.folderStatsLoading = false,
    required this.currentDirPath,
    required this.cacheMode,
    required this.quality,
    this.isBottom = false,
    this.archiveContext,
    this.archiveRootPath,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final previewingCurrentFolder = selectedItems.isEmpty;
    final entry = selectedItems.length == 1
        ? selectedItems.first
        : previewingCurrentFolder
        ? RawEntry(name: folderName, isDir: true, sizeBytes: 0, modifiedSecs: 0)
        : null;
    final folderCount = currentItems.where((item) => item.isDir).length;
    final fileCount = currentItems.length - folderCount;
    final listedFileBytes = currentItems.fold<int>(
      0,
      (total, item) => total + (item.isDir ? 0 : item.sizeBytes),
    );
    final folderSize = folderTotalBytes == null
        ? folderStatsLoading
              ? context.l10n.sizeCalculatingLabel
              : formatBytes(listedFileBytes)
        : formatBytes(folderTotalBytes!);
    // Content that is shown for real (full-resolution image, playable video or
    // audio, the start of a text file, a font specimen) gets a larger area than
    // the generic thumbnail. Archives cannot be read through the container
    // path, so they keep the thumbnail only.
    final previewKind =
        entry != null &&
            !entry.isDir &&
            !entry.isPlaceholder &&
            archiveContext == null
        ? previewPaneKindFor(entry.name)
        : PreviewPaneKind.none;
    final isRichPreview =
        previewKind != PreviewPaneKind.none &&
        previewKind != PreviewPaneKind.unknownText;
    final richExtent = previewKind == PreviewPaneKind.audio ? 300.0 : 420.0;
    final imageExtent = isBottom
        ? 132.0
        : isRichPreview
        ? richExtent
        : 240.0;

    return Material(
      color: cs.surfaceContainerLow,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            left: isBottom
                ? BorderSide.none
                : BorderSide(color: cs.outlineVariant),
            top: isBottom
                ? BorderSide(color: cs.outlineVariant)
                : BorderSide.none,
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(isBottom ? 12 : 16),
          child: selectedItems.length > 1
              ? _MultipleSelectionSummary(count: selectedItems.length)
              : entry == null
              ? _EmptyPreview()
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final previewHeight = !constraints.maxHeight.isFinite
                        ? imageExtent
                        : isBottom
                        ? constraints.maxHeight
                        : (constraints.maxHeight * (isRichPreview ? 0.6 : 0.45))
                              .clamp(96.0, imageExtent)
                              .toDouble();
                    final fallbackColor = entry.isDir
                        ? cs.secondary
                        : colorForFile(entry.name);
                    final thumbnailContent = previewingCurrentFolder
                        ? archiveContext == null
                              ? FolderThumbnailPreview(
                                  key: ValueKey<String>(
                                    'desktop_preview_folder:${container.volId}:$currentDirPath',
                                  ),
                                  container: container,
                                  folderPath: currentDirPath,
                                  cacheMode: cacheMode,
                                  quality: quality,
                                  iconSize: 64,
                                  previewSize: 96,
                                  child: Center(
                                    child: Icon(
                                      Icons.folder_rounded,
                                      color: cs.secondary,
                                      size: 64,
                                    ),
                                  ),
                                )
                              : Center(
                                  child: Icon(
                                    Icons.folder_rounded,
                                    color: cs.secondary,
                                    size: 64,
                                  ),
                                )
                        : FileThumbnailLeading(
                            key: ValueKey<String>(
                              'desktop_preview:${container.volId}:$currentDirPath:${entry.name}',
                            ),
                            entry: entry,
                            container: container,
                            currentDirPath: currentDirPath,
                            cacheMode: cacheMode,
                            quality: quality,
                            archiveContext: archiveContext,
                            archiveRootPath: archiveRootPath,
                            fallbackIcon: entry.isDir
                                ? Icons.folder_rounded
                                : iconForFile(entry.name),
                            fallbackIconColor: fallbackColor,
                          );
                    // Images show at full resolution, videos and audio play in
                    // place and text/fonts render their content; the thumbnail
                    // stays as the poster / fallback.
                    final entryPath = currentDirPath.isEmpty
                        ? entry.name
                        : '$currentDirPath/${entry.name}';
                    final contentKey =
                        '${container.volId}:$entryPath:${entry.sizeBytes}:${entry.modifiedSecs}';
                    final Widget previewContent = switch (previewKind) {
                      PreviewPaneKind.none => thumbnailContent,
                      PreviewPaneKind.video => PreviewPaneVideo(
                        key: ValueKey<String>(
                          'desktop_preview_video:${container.volId}:$entryPath',
                        ),
                        container: container,
                        filePath: entryPath,
                        poster: thumbnailContent,
                        startingFolder: currentDirPath.isEmpty
                            ? null
                            : currentDirPath,
                        quality: quality,
                        cacheMode: cacheMode,
                      ),
                      PreviewPaneKind.image => PreviewPaneImage(
                        container: container,
                        filePath: entryPath,
                        quality: quality,
                        cacheMode: cacheMode,
                      ),
                      PreviewPaneKind.audio => PreviewPaneAudio(
                        key: ValueKey<String>('desktop_preview_audio:$contentKey'),
                        container: container,
                        filePath: entryPath,
                        sizeBytes: entry.sizeBytes,
                        poster: thumbnailContent,
                      ),
                      PreviewPaneKind.text ||
                      PreviewPaneKind.unknownText => PreviewPaneText(
                        key: ValueKey<String>('desktop_preview_text:$contentKey'),
                        container: container,
                        filePath: entryPath,
                        sizeBytes: entry.sizeBytes,
                        sniff: previewKind == PreviewPaneKind.unknownText,
                        poster: thumbnailContent,
                      ),
                      PreviewPaneKind.font => PreviewPaneFont(
                        key: ValueKey<String>('desktop_preview_font:$contentKey'),
                        container: container,
                        filePath: entryPath,
                        sizeBytes: entry.sizeBytes,
                        poster: thumbnailContent,
                      ),
                    };
                    final thumbnail = DecoratedBox(
                      position: DecorationPosition.foreground,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: cs.outlineVariant.withValues(alpha: 0.35),
                        ),
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: previewContent,
                        ),
                      ),
                    );

                    // The facts under the name: the side panel lists them below
                    // the thumbnail, the bottom panel in a column of its own.
                    final detailRows = <Widget>[
                      _DetailRow(
                        label: context.l10n.sortFieldType,
                        value: entry.isDir
                            ? context.l10n.nounFolderCapitalized
                            : _fileType(entry.name),
                      ),
                      if (previewingCurrentFolder) ...[
                        _DetailRow(
                          label: context.l10n.contentsLabel,
                          value: context.l10n.folderItemCount(
                            currentItems.length,
                          ),
                        ),
                        if (folderCount > 0)
                          _DetailRow(
                            label: context.l10n.nounFolderCapitalized,
                            value: context.l10n.statsFolderCount(folderCount),
                          ),
                        if (fileCount > 0)
                          _DetailRow(
                            label: context.l10n.nounFileCapitalized,
                            value: context.l10n.statsFileCount(fileCount),
                          ),
                        _DetailRow(
                          label: context.l10n.totalSizeLabel,
                          value: folderSize,
                        ),
                      ] else if (!entry.isDir)
                        _DetailRow(
                          label: context.l10n.sortFieldSize,
                          value: formatBytes(entry.sizeBytes),
                        ),
                      if (entry.modifiedSecs > 0)
                        _DetailRow(
                          label: context.l10n.sortFieldDate,
                          value: formatEntryDate(entry.modifiedSecs, context),
                        ),
                    ];

                    if (isBottom) {
                      // A thumbnail sized to the panel's height rather than to
                      // its width, so a wide panel does not stretch it.
                      final maxThumbnailWidth = (constraints.maxWidth * 0.45)
                          .clamp(96.0, 260.0)
                          .toDouble();
                      final thumbnailWidth = (previewHeight * 1.25)
                          .clamp(96.0, maxThumbnailWidth)
                          .toDouble();
                      // Wide enough for the details to sit beside the name.
                      final showDetails =
                          constraints.maxWidth - thumbnailWidth - 32 >= 420;
                      return Row(
                        children: [
                          SizedBox(
                            width: thumbnailWidth,
                            height: previewHeight,
                            child: thumbnail,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 2,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  entry.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  previewingCurrentFolder
                                      ? '${context.l10n.folderItemCount(currentItems.length)} · $folderSize'
                                      : entry.isDir
                                      ? context.l10n.nounFolderCapitalized
                                      : '${_fileType(entry.name)}${entry.sizeBytes > 0 ? ' · ${formatBytes(entry.sizeBytes)}' : ''}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          if (showDetails) ...[
                            const SizedBox(width: 16),
                            Expanded(
                              flex: 3,
                              child: SingleChildScrollView(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: detailRows,
                                ),
                              ),
                            ),
                          ],
                        ],
                      );
                    }

                    return SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(height: previewHeight, child: thumbnail),
                          const SizedBox(height: 16),
                          Text(
                            entry.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          ...detailRows,
                        ],
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  static String _fileType(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return 'File';
    return name.substring(dot + 1).toUpperCase();
  }
}

class _EmptyPreview extends StatelessWidget {
  const _EmptyPreview();

  @override
  Widget build(BuildContext context) => Center(
    child: Icon(
      Icons.preview_outlined,
      size: 40,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}

class _MultipleSelectionSummary extends StatelessWidget {
  final int count;

  const _MultipleSelectionSummary({required this.count});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.checklist_rounded,
          size: 40,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 12),
        Text(context.l10n.selectionBarSelectedCount(count)),
      ],
    ),
  );
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: textTheme.bodySmall?.copyWith(color: muted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
