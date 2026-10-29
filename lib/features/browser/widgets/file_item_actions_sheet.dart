import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/utils/file_type_utils.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/core/widgets/thumbnail/async_thumbnail.dart';
import 'package:vaultexplorer/data/models/archive_context.dart';
import 'package:vaultexplorer/data/models/file_item_action.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/data/services/thumbnail_cache_service.dart';
import 'package:vaultexplorer/data/services/video_thumbnail_fetcher.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';
import 'package:vaultexplorer/features/browser/widgets/archive_thumbnail_support.dart';
import 'package:vaultexplorer/features/browser/widgets/folder_thumbnail_preview.dart';
import 'package:vaultexplorer/features/browser/widgets/thumbnail_raw_fallback.dart';

class FileItemActionsSheet extends ConsumerWidget {
  final RawEntry entry;
  final MountedContainer container;
  final String currentDirPath;
  final bool isReadOnly;
  final bool isPinned;
  final bool isBookmark;
  final bool isDocumentProviderMounted;
  final ThumbnailCacheMode thumbnailCacheMode;
  final ThumbnailQuality thumbnailQuality;
  final ArchiveContext? archiveContext;
  final String? archiveRootPath;
  final Widget? customLeading;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onCopy;
  final VoidCallback onCut;
  final VoidCallback onTogglePin;
  final VoidCallback onToggleBookmark;
  final VoidCallback onInfo;
  final VoidCallback? onArchive;
  final VoidCallback? onExtract;
  final VoidCallback? onOpenWith;
  final VoidCallback? onShare;
  final VoidCallback? onEditImage;
  final VoidCallback? onEditVideo;
  final VoidCallback? onEditAudio;
  final VoidCallback? onToggleDocProvider;
  final VoidCallback? onSyncSettings;

  /// Selection-bar parity actions (vault export + quick encrypt/decrypt).
  final VoidCallback? onExport;
  final VoidCallback? onEncrypt;
  final VoidCallback? onDecrypt;

  /// Tab actions (only wired while the file manager is hosted in tabs).
  final VoidCallback? onOpenInNewTab;

  /// Set only when the sheet is opened from search results: shows the item in
  /// the folder it lives in. Not a configurable action (it has no meaning
  /// outside a search), so it is always offered when set.
  final VoidCallback? onGoToLocation;

  /// The user's item-action configuration: hidden actions are not offered,
  /// and the quick row and the list follow this order.
  final List<FileItemAction> actionOrder;
  final Set<FileItemAction> hiddenActions;

  /// Which actions go in the horizontal quick row; all others are list rows.
  final Set<FileItemAction> quickActions;

  const FileItemActionsSheet({
    super.key,
    required this.entry,
    required this.container,
    required this.currentDirPath,
    required this.isReadOnly,
    required this.isPinned,
    required this.isBookmark,
    this.isDocumentProviderMounted = false,
    this.thumbnailCacheMode = ThumbnailCacheMode.appCache,
    this.thumbnailQuality = ThumbnailQuality.defaultQuality,
    this.archiveContext,
    this.archiveRootPath,
    this.customLeading,
    required this.onRename,
    required this.onDelete,
    required this.onCopy,
    required this.onCut,
    required this.onTogglePin,
    required this.onToggleBookmark,
    required this.onInfo,
    this.onArchive,
    this.onExtract,
    this.onOpenWith,
    this.onShare,
    this.onEditImage,
    this.onEditVideo,
    this.onEditAudio,
    this.onToggleDocProvider,
    this.onSyncSettings,
    this.onExport,
    this.onEncrypt,
    this.onDecrypt,
    this.onOpenInNewTab,
    this.onGoToLocation,
    this.actionOrder = FileItemAction.values,
    this.hiddenActions = const {},
    this.quickActions = FileItemAction.defaultQuickActions,
  });

  static Future<void> show(
    BuildContext context, {
    required RawEntry entry,
    required MountedContainer container,
    required String currentDirPath,
    required bool isReadOnly,
    required bool isPinned,
    required bool isBookmark,
    bool isDocumentProviderMounted = false,
    ThumbnailCacheMode thumbnailCacheMode = ThumbnailCacheMode.appCache,
    ThumbnailQuality thumbnailQuality = ThumbnailQuality.defaultQuality,
    ArchiveContext? archiveContext,
    String? archiveRootPath,
    Widget? customLeading,
    required VoidCallback onRename,
    required VoidCallback onDelete,
    required VoidCallback onCopy,
    required VoidCallback onCut,
    required VoidCallback onTogglePin,
    required VoidCallback onToggleBookmark,
    required VoidCallback onInfo,
    VoidCallback? onArchive,
    VoidCallback? onExtract,
    VoidCallback? onOpenWith,
    VoidCallback? onShare,
    VoidCallback? onEditImage,
    VoidCallback? onEditVideo,
    VoidCallback? onEditAudio,
    VoidCallback? onToggleDocProvider,
    VoidCallback? onSyncSettings,
    VoidCallback? onExport,
    VoidCallback? onEncrypt,
    VoidCallback? onDecrypt,
    VoidCallback? onOpenInNewTab,
    VoidCallback? onGoToLocation,
    List<FileItemAction> actionOrder = FileItemAction.values,
    Set<FileItemAction> hiddenActions = const {},
    Set<FileItemAction> quickActions = FileItemAction.defaultQuickActions,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => FileItemActionsSheet(
        entry: entry,
        container: container,
        currentDirPath: currentDirPath,
        isReadOnly: isReadOnly,
        isPinned: isPinned,
        isBookmark: isBookmark,
        isDocumentProviderMounted: isDocumentProviderMounted,
        thumbnailCacheMode: thumbnailCacheMode,
        thumbnailQuality: thumbnailQuality,
        archiveContext: archiveContext,
        archiveRootPath: archiveRootPath,
        customLeading: customLeading,
        onRename: onRename,
        onDelete: onDelete,
        onCopy: onCopy,
        onCut: onCut,
        onTogglePin: onTogglePin,
        onToggleBookmark: onToggleBookmark,
        onInfo: onInfo,
        onArchive: onArchive,
        onExtract: onExtract,
        onOpenWith: onOpenWith,
        onShare: onShare,
        onEditImage: onEditImage,
        onEditVideo: onEditVideo,
        onEditAudio: onEditAudio,
        onToggleDocProvider: onToggleDocProvider,
        onSyncSettings: onSyncSettings,
        onExport: onExport,
        onEncrypt: onEncrypt,
        onDecrypt: onDecrypt,
        onOpenInNewTab: onOpenInNewTab,
        onGoToLocation: onGoToLocation,
        actionOrder: actionOrder,
        hiddenActions: hiddenActions,
        quickActions: quickActions,
      ),
    );
  }

  Widget _buildLeading(
    BuildContext context,
    WidgetRef ref,
    ColorScheme cs,
    IconData fallbackIcon,
    Color fallbackIconColor,
  ) {
    if (customLeading != null) return customLeading!;

    final cleanName = entry.name;
    final fullPath = currentDirPath.isEmpty
        ? cleanName
        : '$currentDirPath/$cleanName';
    final ext = cleanName.contains('.')
        ? cleanName.split('.').last.toLowerCase()
        : '';
    final vaultIcon = vaultIconForExt(ext);
    final vaultColor = vaultColorForExt(ext);

    if (entry.isDir) {
      return FolderThumbnailPreview(
        container: container,
        folderPath: fullPath,
        cacheMode: thumbnailCacheMode,
        quality: thumbnailQuality,
        iconSize: 24,
        child: Center(
          child: Icon(fallbackIcon, color: fallbackIconColor, size: 24),
        ),
      );
    }

    if (vaultIcon != null) {
      return Center(child: Icon(vaultIcon, color: vaultColor, size: 24));
    }

    final isImg =
        MediaViewerConstants.isImage(cleanName) && !entry.isPlaceholder;
    final isVid =
        MediaViewerConstants.isVideo(cleanName) && !entry.isPlaceholder;

    if (isImg) {
      return _ItemImageThumbnail(
        container: container,
        filePath: fullPath,
        cacheMode: thumbnailCacheMode,
        quality: thumbnailQuality,
        archiveContext: archiveContext,
        archiveRootPath: archiveRootPath,
        fallbackIcon: fallbackIcon,
        fallbackIconColor: fallbackIconColor,
      );
    }

    if (isVid) {
      return _ItemVideoThumbnail(
        container: container,
        filePath: fullPath,
        cacheMode: thumbnailCacheMode,
        quality: thumbnailQuality,
        fallbackIcon: fallbackIcon,
        fallbackIconColor: fallbackIconColor,
        archiveContext: archiveContext,
        archiveRootPath: archiveRootPath,
      );
    }

    return Center(
      child: Icon(fallbackIcon, color: fallbackIconColor, size: 24),
    );
  }

  /// Wraps [onTap] the way every sheet action runs: close the sheet first,
  /// then invoke the callback. A confirmation (e.g. for delete) lives in the
  /// caller's callback and is untouched.
  VoidCallback _closeThen(BuildContext context, VoidCallback onTap) {
    return () {
      Navigator.pop(context);
      onTap();
    };
  }

  /// What to show for [action] on this item, or null when it does not apply
  /// (archive entries are virtual, and a missing callback means the caller
  /// does not offer the action). The same spec renders as a quick-row button
  /// or as a list row, so every action works in either place.
  _ActionSpec? _specFor(
    BuildContext context,
    ColorScheme cs,
    FileItemAction action,
  ) {
    final l10n = context.l10n;
    final inArchive = archiveContext != null;
    switch (action) {
      case FileItemAction.openInNewTab:
        if (onOpenInNewTab == null) return null;
        return _ActionSpec(
          icon: Icons.tab_rounded,
          label: l10n.browserTabOpenInNewTab,
          onTap: onOpenInNewTab!,
        );
      case FileItemAction.extract:
        // Archive entries are virtual, read-only entries. The sole file
        // operation available there is staging one for extraction into a
        // real destination.
        if (onExtract == null) return null;
        return _ActionSpec(
          icon: Icons.unarchive_outlined,
          label: l10n.extract,
          onTap: onExtract!,
        );
      case FileItemAction.openWith:
        if (inArchive || onOpenWith == null) return null;
        return _ActionSpec(
          icon: Icons.open_in_new_rounded,
          label: l10n.openWithAppAction,
          onTap: onOpenWith!,
        );
      case FileItemAction.share:
        if (inArchive || onShare == null) return null;
        return _ActionSpec(
          icon: Icons.share_rounded,
          label: l10n.shareAction,
          onTap: onShare!,
        );
      case FileItemAction.editImage:
        if (inArchive || onEditImage == null) return null;
        return _ActionSpec(
          icon: Icons.edit_outlined,
          label: l10n.editImageAction,
          enabled: !isReadOnly,
          onTap: onEditImage!,
        );
      case FileItemAction.editVideo:
        if (inArchive || onEditVideo == null) return null;
        return _ActionSpec(
          icon: Icons.content_cut_rounded,
          label: l10n.videoEditorEditAction,
          enabled: !isReadOnly,
          onTap: onEditVideo!,
        );
      case FileItemAction.editAudio:
        if (inArchive || onEditAudio == null) return null;
        return _ActionSpec(
          icon: Icons.graphic_eq_rounded,
          label: l10n.audioEditorEditAction,
          enabled: !isReadOnly,
          onTap: onEditAudio!,
        );
      case FileItemAction.rename:
        if (inArchive) return null;
        return _ActionSpec(
          icon: Icons.drive_file_rename_outline_rounded,
          label: l10n.renameAction,
          enabled: !isReadOnly,
          onTap: onRename,
        );
      case FileItemAction.copy:
        if (inArchive) return null;
        return _ActionSpec(
          icon: Icons.copy_rounded,
          label: l10n.copyAction,
          onTap: onCopy,
        );
      case FileItemAction.move:
        if (inArchive) return null;
        return _ActionSpec(
          icon: Icons.cut_rounded,
          label: l10n.moveAction,
          enabled: !isReadOnly,
          onTap: onCut,
        );
      case FileItemAction.archive:
        if (inArchive || onArchive == null) return null;
        return _ActionSpec(
          icon: Icons.archive_outlined,
          label: l10n.archiveSelectionAction,
          enabled: !isReadOnly,
          onTap: onArchive!,
        );
      case FileItemAction.exportToDevice:
        if (inArchive || onExport == null) return null;
        return _ActionSpec(
          icon: Icons.drive_folder_upload_rounded,
          label: l10n.exportToDeviceAction,
          onTap: onExport!,
        );
      case FileItemAction.encrypt:
        if (inArchive || onEncrypt == null) return null;
        return _ActionSpec(
          icon: Icons.lock_outline_rounded,
          label: l10n.cryptoDirectionEncrypt,
          onTap: onEncrypt!,
        );
      case FileItemAction.decrypt:
        if (inArchive || onDecrypt == null) return null;
        return _ActionSpec(
          icon: Icons.lock_open_rounded,
          label: l10n.cryptoDirectionDecrypt,
          onTap: onDecrypt!,
        );
      case FileItemAction.docProvider:
        if (inArchive || onToggleDocProvider == null) return null;
        return _ActionSpec(
          icon: isDocumentProviderMounted
              ? Icons.folder_shared_rounded
              : Icons.folder_shared_outlined,
          label: isDocumentProviderMounted
              ? l10n.documentProviderSettingsMenu
              : l10n.exposeAsDocumentProviderMenu,
          onTap: onToggleDocProvider!,
        );
      case FileItemAction.syncSettings:
        if (inArchive || onSyncSettings == null) return null;
        return _ActionSpec(
          icon: Icons.sync_rounded,
          label: l10n.autoSyncMenuAction,
          onTap: onSyncSettings!,
        );
      case FileItemAction.pin:
        if (inArchive) return null;
        return _ActionSpec(
          icon: isPinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
          label: isPinned ? l10n.unpinAction : l10n.pinAction,
          onTap: onTogglePin,
        );
      case FileItemAction.bookmark:
        if (inArchive) return null;
        return _ActionSpec(
          icon: isBookmark ? Icons.star_outline_rounded : Icons.star_rounded,
          label: isBookmark ? l10n.unbookmarkAction : l10n.bookmarkAction,
          onTap: onToggleBookmark,
        );
      case FileItemAction.delete:
        if (inArchive) return null;
        // Destructive: red accent. The confirmation dialog lives in the
        // `onDelete` callback supplied by the caller and is untouched.
        return _ActionSpec(
          icon: Icons.delete_outline_rounded,
          label: l10n.delete,
          color: cs.error,
          enabled: !isReadOnly,
          onTap: onDelete,
        );
    }
  }

  /// Horizontal row of quick-action buttons.
  ///
  /// Each button is a Flexible child under `spaceAround`: it takes its natural
  /// width (>= 64dp, so the touch target is always >= 48x48dp) and shrinks, with
  /// an ellipsized label, rather than overflowing on narrow screens or with
  /// long localized labels.
  Widget _buildQuickRow(List<Widget> buttons) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [for (final button in buttons) Flexible(child: button)],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Apply the user's configuration: hidden actions are dropped and the rest
    // follow the configured order. Actions that do not apply to this item
    // (no callback, archive entry) yield null and are skipped.
    final configured = [
      for (final action in actionOrder)
        if (!hiddenActions.contains(action)) action,
    ];
    final quickButtons = <Widget>[];
    final listItems = <Widget>[];
    int? previousGroup;
    for (final action in configured) {
      final spec = _specFor(context, cs, action);
      if (spec == null) continue;
      final onTap = _closeThen(context, spec.onTap);
      if (quickActions.contains(action)) {
        quickButtons.add(
          _QuickActionButton(
            icon: spec.icon,
            label: spec.label,
            color: spec.color,
            enabled: spec.enabled,
            onTap: onTap,
          ),
        );
        continue;
      }
      // A small gap between rows of different groups, as before.
      if (previousGroup != null && previousGroup != action.group) {
        listItems.add(const SizedBox(height: 8));
      }
      listItems.add(
        _ActionTile(
          icon: spec.icon,
          label: spec.label,
          color: spec.color,
          enabled: spec.enabled,
          onTap: onTap,
        ),
      );
      previousGroup = action.group;
    }

    // "Go to location" is not one of the configurable actions: it only exists
    // for search results, where it is the reason to look at an item's sheet,
    // so it leads the list whatever order or hidden settings the user has.
    final goToLocation = onGoToLocation;
    if (goToLocation != null && archiveContext == null) {
      listItems.insertAll(0, [
        _ActionTile(
          icon: Icons.folder_open_rounded,
          label: context.l10n.goToLocationAction,
          onTap: _closeThen(context, goToLocation),
        ),
        if (listItems.isNotEmpty) const SizedBox(height: 8),
      ]);
    }

    final isDir = entry.isDir;
    final isInsideArchive = archiveContext != null;
    final ext = isDir
        ? ''
        : (entry.name.contains('.') ? entry.name.split('.').last : '');
    final icon = isDir
        ? (isDocumentProviderMounted
              ? Icons.folder_shared_rounded
              : Icons.folder_rounded)
        : (vaultIconForExt(ext) ?? iconForFile(entry.name));
    final iconColor = isDir
        ? (isDocumentProviderMounted ? cs.tertiary : cs.secondary)
        : (vaultColorForExt(ext) ?? colorForFile(entry.name));

    final subtitleParts = <String>[
      if (!isDir) formatBytes(entry.sizeBytes),
      if (entry.modifiedSecs > 0) formatEntryDate(entry.modifiedSecs),
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header: Thumbnail/Icon + Filename + Meta
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: SizedBox.expand(
                      child: _buildLeading(context, ref, cs, icon, iconColor),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (subtitleParts.isNotEmpty)
                          Text(
                            subtitleParts.join('    '),
                            style: textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (!isInsideArchive)
                    IconButton(
                      icon: const Icon(Icons.info_outline_rounded),
                      iconSize: 22,
                      color: cs.onSurfaceVariant,
                      tooltip: context.l10n.fileInfoAction,
                      onPressed: () {
                        Navigator.pop(context);
                        onInfo();
                      },
                    ),
                ],
              ),
            ),
            const Divider(height: 16),

            if (quickButtons.isNotEmpty) ...[
              _buildQuickRow(quickButtons),
              if (listItems.isNotEmpty)
                Divider(
                  height: 16,
                  color: cs.outlineVariant.withValues(alpha: 0.5),
                ),
            ],

            // Secondary actions list
            if (listItems.isNotEmpty)
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: listItems,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ItemImageThumbnail extends ConsumerWidget {
  final MountedContainer container;
  final String filePath;
  final ThumbnailCacheMode cacheMode;
  final ThumbnailQuality quality;
  final ArchiveContext? archiveContext;
  final String? archiveRootPath;
  final IconData fallbackIcon;
  final Color fallbackIconColor;

  const _ItemImageThumbnail({
    required this.container,
    required this.filePath,
    required this.cacheMode,
    required this.quality,
    this.archiveContext,
    this.archiveRootPath,
    required this.fallbackIcon,
    required this.fallbackIconColor,
  });

  static Future<Uint8List> _fetch(
    ThumbnailCacheService thumbnailCache,
    VaultFileIoApi fileIoApi,
    MountedContainer container,
    String path,
    ThumbnailCacheMode mode,
    ThumbnailQuality quality,
    ArchiveContext? archiveContext,
    String? archiveRootPath,
  ) async {
    if (archiveContext != null && archiveRootPath != null) {
      final bytes = await fetchArchiveEntryForThumbnail(
        archiveContext: archiveContext,
        archiveRootPath: archiveRootPath,
        fullPath: path,
        fileIoApi: fileIoApi,
        targetSize: quality.scaledSize(180),
        quality: quality.jpegQuality,
      );
      thumbnailCache.cacheInMemory(container, path, bytes, quality);
      return bytes;
    }
    if (mode != ThumbnailCacheMode.disabled) {
      final cached = await thumbnailCache.fetch(
        container: container,
        filePath: path,
        mode: mode,
        quality: quality,
      );
      if (cached != null && cached.isNotEmpty) return cached;
    }
    final thumbBytes = await fileIoApi.getImageThumbnailOrThrow(
      container,
      path,
      targetSize: quality.scaledSize(180),
      quality: quality.jpegQuality,
    );
    if (thumbBytes == null || thumbBytes.isEmpty) {
      final raw = await readRawThumbnailFallback(fileIoApi, container, path);
      if (raw.length < 200 * 1024) {
        thumbnailCache.cacheInMemory(container, path, raw, quality);
      }
      return raw;
    }
    thumbnailCache.cacheInMemory(container, path, thumbBytes, quality);
    if (mode != ThumbnailCacheMode.disabled) {
      unawaited(
        thumbnailCache.store(
          container: container,
          filePath: path,
          data: thumbBytes,
          mode: mode,
          quality: quality,
        ),
      );
    }
    return thumbBytes;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thumbnailCache = ref.read(thumbnailCacheServiceProvider);
    final fileIoApi = ref.read(vaultFileIoApiProvider);
    final cs = Theme.of(context).colorScheme;

    return AsyncThumbnail(
      key: ValueKey('sheet_img:$filePath'),
      container: container,
      filePath: filePath,
      cache: ThumbnailConcurrency.inFlightThumbnails,
      limiter: ThumbnailConcurrency.imageLimiter,
      quality: quality,
      fetchFn: (c, p) => _fetch(
        thumbnailCache,
        fileIoApi,
        c,
        p,
        cacheMode,
        quality,
        archiveContext,
        archiveRootPath,
      ),
      debounce: const Duration(milliseconds: 50),
      syncLookup: () => thumbnailCache.peekMemory(container, filePath, quality),
      cacheHeight: quality.scaledSize(180),
      imageBuilder: (context, bytes, cacheHeight) => Image.memory(
        bytes,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        cacheHeight: cacheHeight,
        errorBuilder: (_, _, _) => Center(
          child: Icon(fallbackIcon, color: fallbackIconColor, size: 24),
        ),
      ),
      loadingBuilder: (context) => Container(
        color: cs.surfaceContainerHighest,
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: cs.primary.withValues(alpha: 0.6),
            ),
          ),
        ),
      ),
      errorBuilder: (context) =>
          Icon(fallbackIcon, color: fallbackIconColor, size: 24),
    );
  }
}

class _ItemVideoThumbnail extends ConsumerWidget {
  final MountedContainer container;
  final String filePath;
  final ThumbnailCacheMode cacheMode;
  final ThumbnailQuality quality;
  final IconData fallbackIcon;
  final Color fallbackIconColor;
  final ArchiveContext? archiveContext;
  final String? archiveRootPath;

  const _ItemVideoThumbnail({
    required this.container,
    required this.filePath,
    required this.cacheMode,
    required this.quality,
    required this.fallbackIcon,
    required this.fallbackIconColor,
    this.archiveContext,
    this.archiveRootPath,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thumbnailCache = ref.read(thumbnailCacheServiceProvider);
    final fileIoApi = ref.read(vaultFileIoApiProvider);
    final cs = Theme.of(context).colorScheme;

    return Stack(
      fit: StackFit.expand,
      children: [
        AsyncThumbnail(
          key: ValueKey('sheet_vid:$filePath'),
          container: container,
          filePath: filePath,
          quality: quality,
          cache: ThumbnailConcurrency.inFlightThumbnails,
          limiter: ThumbnailConcurrency.videoLimiter,
          fetchFn: (c, p) => VideoThumbnailFetcher.fetch(
            thumbnailCache,
            fileIoApi,
            c,
            p,
            mode: cacheMode,
            quality: quality,
            targetSize: quality.scaledSize(180),
            archiveContext: archiveContext,
            archiveRootPath: archiveRootPath,
          ),
          debounce: const Duration(milliseconds: 50),
          syncLookup: () =>
              thumbnailCache.peekMemory(container, filePath, quality),
          cacheHeight: quality.scaledSize(180),
          imageBuilder: (context, bytes, cacheHeight) => Image.memory(
            bytes,
            width: double.infinity,
            height: double.infinity,
            fit: BoxFit.cover,
            cacheHeight: cacheHeight,
            errorBuilder: (_, _, _) => Center(
              child: Icon(fallbackIcon, color: fallbackIconColor, size: 24),
            ),
          ),
          loadingBuilder: (context) => Container(
            color: cs.surfaceContainerHighest,
            child: Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: cs.primary.withValues(alpha: 0.6),
                ),
              ),
            ),
          ),
          errorBuilder: (context) =>
              Icon(fallbackIcon, color: fallbackIconColor, size: 24),
        ),
        Align(
          alignment: Alignment.bottomRight,
          child: Padding(
            padding: const EdgeInsets.all(3.0),
            child: Icon(
              Icons.play_circle_outline_rounded,
              size: 16,
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
        ),
      ],
    );
  }
}

/// What an action looks like and does for the current item; rendered either
/// as a quick-row button or as a list row.
class _ActionSpec {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;
  final Color? color;

  const _ActionSpec({
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
    this.color,
  });
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  final bool enabled;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final effectiveColor = enabled
        ? (color ?? cs.onSurface)
        : cs.onSurfaceVariant.withValues(alpha: 0.38);

    return ListTile(
      dense: true,
      leading: Icon(icon, color: effectiveColor, size: 22),
      title: Text(
        label,
        style: TextStyle(color: effectiveColor, fontWeight: FontWeight.w500),
      ),
      enabled: enabled,
      onTap: enabled ? onTap : null,
    );
  }
}

/// Icon-over-label button used by the horizontal quick-action row.
class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  final bool enabled;

  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final effectiveColor = enabled
        ? (color ?? cs.onSurface)
        : cs.onSurfaceVariant.withValues(alpha: 0.38);

    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        // >= 48x48dp touch target.
        constraints: const BoxConstraints(minWidth: 64, minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: effectiveColor, size: 22),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: textTheme.labelSmall?.copyWith(
                  color: effectiveColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
