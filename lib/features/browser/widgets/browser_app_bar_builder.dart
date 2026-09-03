import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/core/providers/legacy_services_providers.dart';
import 'package:vaultexplorer/core/utils/file_type_utils.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/core/widgets/activity/app_bar_clipboard_chip.dart';
import 'package:vaultexplorer/core/widgets/activity/app_bar_transfer_button.dart';
import 'package:vaultexplorer/data/models/file_manager_action.dart';
import 'package:vaultexplorer/data/models/file_manager_toolbar_config.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/vault_item.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/services/archive_service.dart';
import 'package:vaultexplorer/features/browser/browser_dialogs.dart';
import 'package:vaultexplorer/features/browser/file_browser_screen.dart' show PathSegment;
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/file_info_sheet.dart';
import 'package:vaultexplorer/features/browser/widgets/selection_app_bar.dart';
import 'package:vaultexplorer/features/browser/widgets/selection_app_bar_wide.dart';
import 'package:vaultexplorer/features/browser/widgets/settings_menu_button.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';

PreferredSizeWidget buildBrowserAppBar(
  BuildContext context, {
  required WidgetRef ref,
  required MountedContainer container,
  required List<PathSegment> pathStack,
  required ValueChanged<int> onJumpTo,
  required List<RawEntry> filteredItems,
  required int dirCount,
  required int fileCount,
  required bool isSelectionMode,
  required Set<RawEntry> selectedItems,
  required bool isReadOnly,
  required bool searchActive,
  required String currentDirPath,
  required FileManagerToolbarConfig toolbarConfig,
  required String? currentFilter,
  required int? freeSpace,
  required int selectedTotalBytes,
  required bool hasPendingFolderSizes,
  required Map<FileManagerAction, WidgetBuilder> actionBuilders,
  required bool Function(RawEntry entry) isFolderMounted,
  required bool Function(RawEntry entry) isPinned,
  required bool Function(RawEntry entry) isBookmark,
  required VoidCallback onExitSelectionMode,
  required VoidCallback onSelectAll,
  required VoidCallback onCopy,
  required VoidCallback onCut,
  required VoidCallback onExport,
  required VoidCallback onCompressSelected,
  required VoidCallback onExtractSelectedArchive,
  required VoidCallback onDelete,
  required VoidCallback onEncryptSelected,
  required VoidCallback onDecryptSelected,
  required void Function({required bool pin}) onTogglePin,
  required void Function({required bool bookmark}) onToggleBookmark,
  required void Function(String path) onDirectoryReload,
  required void Function(String msg, {required bool error}) onSetStatus,
  required Future<void> Function(
    String fileName,
    String fullPath,
    String ext,
    AppSettings settings,
  )
  onShowOpenWithDialog,
  required Future<void> Function(RawEntry entry) onShowFolderDocumentProviderSheet,
  required Future<void> Function(RawEntry entry) onToggleFolderDocumentProvider,
  required Future<void> Function(String fileName, String fullPath) onEditImage,
  required Future<void> Function() onSettingsClosed,
  required bool isFiltered,
  required VoidCallback? onPaste,
  /// When false, no back/leading icon is shown regardless of Navigator
  /// state (decoy mode's file manager has no dashboard underneath it to
  /// return to -- see DecoyFileManagerScreen). Defaults to true, matching
  /// the original always-shown back-to-dashboard button.
  bool showBackButton = true,
  /// Wraps the built title widget before it's handed to [AppBar.title].
  /// Decoy mode uses this to add the long-press "reveal the real vault"
  /// gesture (HiddenVaultTrigger) without this shared, container-agnostic
  /// builder needing to know that concept exists. Defaults to identity.
  Widget Function(Widget title)? wrapTitle,
}) {
  final allItems = filteredItems;
  final cs = Theme.of(context).colorScheme;
  final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
  final showActionBar = !searchActive;

  if (isSelectionMode) {
    final single = selectedItems.length == 1;
    final singleFile = single && !selectedItems.first.isDir;
    final singleFolder = single && selectedItems.first.isDir;
    final folderDocProviderMounted =
        singleFolder && isFolderMounted(selectedItems.first);
    // Export-to-device and expose-as-document-provider only make sense for
    // a real encrypted vault: decoy mode's "container" is just a plain
    // local-storage folder (see LocalStorageContainerX.isLocalStorage), so
    // both actions are hidden there rather than threaded through a second
    // no-op implementation.
    final hideVaultOnlyActions = container.isLocalStorage;
    final singleArchiveSelected = singleFile &&
        ArchiveService.isArchive(
          selectedItems.first.name.contains('.')
              ? selectedItems.first.name.split('.').last.toLowerCase()
              : '',
        );
    final showPinOption = selectedItems.any((item) => !isPinned(item));
    final showUnpinOption = selectedItems.any((item) => isPinned(item));
    final showBookmarkOption = selectedItems.any((item) => !isBookmark(item));
    final showUnbookmarkOption = selectedItems.any((item) => isBookmark(item));
    final showEncryptOption = selectedItems
        .any((item) => !item.isDir && !isAppEncryptedFileName(item.name));
    final showDecryptOption = selectedItems
        .any((item) => !item.isDir && isAppEncryptedFileName(item.name));
    final showEditImageOption = singleFile && MediaViewerConstants.isImage(selectedItems.first.name);
    final totalBytes = selectedTotalBytes;
    final isPending = hasPendingFolderSizes;
    final sizeLabel = isPending
        ? (totalBytes > 0
              ? context.l10n.sizeCalculatingWithBytesLabel(formatBytes(totalBytes))
              : context.l10n.sizeCalculatingLabel)
        : formatBytes(totalBytes);

    void doShowFileInfo() {
      final entry = selectedItems.first;
      onExitSelectionMode();
      FileInfoSheet.show(
        context,
        container: container,
        entry: entry,
        currentDirPath: currentDirPath,
      );
    }
    void doRename() {
      final entries = selectedItems.toList();
      for (final entry in entries) {
        final parts = entry.name.split('.');
        final ext = parts.length > 1 ? parts.last.toLowerCase() : '';
        if (VaultItemType.values.any((t) => t.name.toLowerCase() == ext)) {
          onSetStatus(context.l10n.editSecureItemsToRenameMessage, error: false);
          onExitSelectionMode();
          return;
        }
      }
      unawaited(BrowserDialogs.showRename(
        context,
        container: container,
        oldEntries: entries,
        existingEntries: allItems,
        currentDirPath: currentDirPath,
        onSuccess: () => onDirectoryReload(currentDirPath),
        readOnly: isReadOnly,
      ));
      onExitSelectionMode();
    }

    Future<void> doOpenWithApp() async {
      final entry = selectedItems.first;
      final path = currentDirPath.isEmpty
          ? entry.name
          : '$currentDirPath/${entry.name}';
      final parts = entry.name.split('.');
      final ext = parts.length > 1 ? parts.last.toLowerCase() : '';
      onExitSelectionMode();
      if (VaultItemType.values.any((t) => t.name.toLowerCase() == ext)) {
        onSetStatus(context.l10n.vaultItemsCannotBeOpenedExternallyMessage, error: true);
        return;
      }
      final settings = await ref.read(appSettingsServiceProvider).loadSettings();
      if (context.mounted) {
        await onShowOpenWithDialog(entry.name, path, ext, settings);
      }
    }

    Future<void> doToggleDocProvider() async {
      final entry = selectedItems.first;
      onExitSelectionMode();
      if (folderDocProviderMounted) {
        await onShowFolderDocumentProviderSheet(entry);
      } else {
        await onToggleFolderDocumentProvider(entry);
      }
    }

    Future<void> doEditImage() async {
      final entry = selectedItems.first;
      final path = currentDirPath.isEmpty ? entry.name : '$currentDirPath/${entry.name}';
      onExitSelectionMode();
      await onEditImage(entry.name, path);
    }

    if (!isLandscape) {
      return SelectionAppBar(
        selectedCount: selectedItems.length,
        selectionLabel: sizeLabel,
        singleSelected: single,
        singleFileSelected: singleFile,
        singleFolderSelected: singleFolder,
        singleArchiveSelected: singleArchiveSelected,
        folderDocumentProviderMounted: folderDocProviderMounted,
        hideVaultOnlyActions: hideVaultOnlyActions,
        readOnly: isReadOnly,
        showPinOption: showPinOption,
        showUnpinOption: showUnpinOption,
        onPin: () => onTogglePin(pin: true),
        onUnpin: () => onTogglePin(pin: false),
        showBookmarkOption: showBookmarkOption,
        showUnbookmarkOption: showUnbookmarkOption,
        onBookmark: () => onToggleBookmark(bookmark: true),
        onUnbookmark: () => onToggleBookmark(bookmark: false),
        showEncryptOption: showEncryptOption,
        showDecryptOption: showDecryptOption,
        onEncrypt: onEncryptSelected,
        onDecrypt: onDecryptSelected,
        onClose: onExitSelectionMode,
        onSelectAll: onSelectAll,
        onRename: doRename,
        onCopy: onCopy,
        onCut: onCut,
        onExport: onExport,
        onCompressSelection: onCompressSelected,
        onExtractSelectedArchive: onExtractSelectedArchive,
        onDelete: onDelete,
        onOpenWithApp: doOpenWithApp,
        onToggleDocumentProvider: doToggleDocProvider,
        onFileInfo: doShowFileInfo,
        showEditImageOption: showEditImageOption,
        onEditImage: doEditImage,
      );
    }
    return SelectionAppBarWide(
      selectedCount: selectedItems.length,
      selectionLabel: sizeLabel,
      singleFileSelected: singleFile,
      singleFolderSelected: singleFolder,
      singleArchiveSelected: singleArchiveSelected,
      folderDocumentProviderMounted: folderDocProviderMounted,
      hideVaultOnlyActions: hideVaultOnlyActions,
      readOnly: isReadOnly,
      showPinOption: showPinOption,
      showUnpinOption: showUnpinOption,
      showBookmarkOption: showBookmarkOption,
      showUnbookmarkOption: showUnbookmarkOption,
      showEncryptOption: showEncryptOption,
      showDecryptOption: showDecryptOption,
      showActionBar: showActionBar,
      visibleActions: toolbarConfig.visible,
      actionBuilders: actionBuilders,
      onClose: onExitSelectionMode,
      onSelectAll: onSelectAll,
      onRename: doRename,
      onCopy: onCopy,
      onCut: onCut,
      onExport: onExport,
      onCompressSelection: onCompressSelected,
      onExtractSelectedArchive: onExtractSelectedArchive,
      onDelete: onDelete,
      onOpenWithApp: doOpenWithApp,
      onToggleDocumentProvider: doToggleDocProvider,
      onPin: () => onTogglePin(pin: true),
      onUnpin: () => onTogglePin(pin: false),
      onBookmark: () => onToggleBookmark(bookmark: true),
      onUnbookmark: () => onToggleBookmark(bookmark: false),
      onEncrypt: onEncryptSelected,
      onDecrypt: onDecryptSelected,
      onFileInfo: doShowFileInfo,
      showEditImageOption: showEditImageOption,
      onEditImage: doEditImage,
    );
  }

  final hasParents = pathStack.length > 1;

  Widget buildReadOnlyBadge() {
    return Tooltip(
      message: context.l10n.mountedReadOnlyTooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(100),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline_rounded, size: 11, color: cs.onSurfaceVariant),
            const SizedBox(width: 3),
            Text(
              context.l10n.readOnlyBadgeAbbreviation,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _buildLeftTruncatedPath(
    String rootName,
    List<PathSegment> stack,
    double maxWidth,
    TextStyle style,
  ) {
    if (stack.length == 1) return rootName;
    final allLabels = [rootName, ...stack.sublist(1).map((s) => s.label)];
    final fullPath = allLabels.join('/');
    double measure(String text) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        maxLines: 1,
        textDirection: TextDirection.ltr,
      )..layout();
      return painter.width;
    }
    if (measure(fullPath) <= maxWidth) {
      return fullPath;
    }
    int low = 0;
    int high = fullPath.length - 1;
    int bestK = fullPath.length - 1;
    while (low <= high) {
      final mid = (low + high) ~/ 2;
      final candidate = '…${fullPath.substring(mid)}';
      if (measure(candidate) <= maxWidth) {
        bestK = mid;
        high = mid - 1;
      } else {
        low = mid + 1;
      }
    }
    return '…${fullPath.substring(bestK)}';
  }

  Widget buildTitleHeader() {
    final textTheme = Theme.of(context).textTheme;
    final style = textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold) ??
        const TextStyle(fontSize: 16, fontWeight: FontWeight.bold);
    if (!hasParents) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              container.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          if (isReadOnly) ...[
            const SizedBox(width: 8),
            buildReadOnlyBadge(),
          ],
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final reservedSpace = 22.0 + (isReadOnly ? 46.0 : 0.0) + 12.0;
        final availableWidth =
            (constraints.maxWidth - reservedSpace).clamp(60.0, 2000.0);
        final displayTitle = _buildLeftTruncatedPath(
          container.displayName,
          pathStack,
          availableWidth,
          style,
        );
        return MenuAnchor(
          builder: (ctx, controller, child) => InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              if (controller.isOpen) {
                controller.close();
              } else {
                controller.open();
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: style,
                    ),
                  ),
                  Icon(
                    Icons.arrow_drop_down_rounded,
                    size: 22,
                    color: cs.primary,
                  ),
                  if (isReadOnly) ...[
                    const SizedBox(width: 6),
                    buildReadOnlyBadge(),
                  ],
                ],
              ),
            ),
          ),
          menuChildren: [
            for (int i = 0; i < pathStack.length; i++) ...[
              (() {
                final segment = pathStack[i];
                final isCurrent = i == pathStack.length - 1;
                final isRoot = i == 0;
                final label = isRoot ? container.displayName : segment.label;
                final IconData icon = isRoot
                    ? Icons.home_rounded
                    : (segment.isArchiveRoot ? Icons.archive_rounded : Icons.folder_rounded);
                final Color iconColor = isRoot
                    ? cs.primary
                    : (segment.isArchiveRoot ? const Color(0xFFFF8F00) : cs.secondary);
                return MenuItemButton(
                  onPressed: isCurrent ? null : () => onJumpTo(i),
                  leadingIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (i > 0) SizedBox(width: (i - 1) * 12.0),
                      Icon(icon, size: 18, color: isCurrent ? cs.primary : iconColor),
                    ],
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                      color: isCurrent ? cs.primary : cs.onSurface,
                    ),
                  ),
                );
              })(),
            ],
          ],
        );
      },
    );
  }

  return AppBar(
    leading: showBackButton
        ? IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: context.l10n.backToDashboardTooltip,
            onPressed: () => Navigator.of(context).pop(),
          )
        : null,
    automaticallyImplyLeading: showBackButton,
    title: (wrapTitle ?? (Widget w) => w)(
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          buildTitleHeader(),
          if (toolbarConfig.showStatsBar)
            buildBrowserAppBarStatsSubtitle(
              context,
              dirCount: dirCount,
              fileCount: fileCount,
              isFiltered: isFiltered,
              freeSpace: freeSpace,
            ),
        ],
      ),
    ),
    actions: [
      const AppBarTransferButton(),
      AppBarClipboardButton(onPaste: onPaste),
      if (isLandscape && showActionBar) ...[
        ...toolbarConfig.visible.map((action) => actionBuilders[action]!(context)),
      ],
      SettingsMenuButton(
        // Not the local-storage container's real path -- see
        // FileManagerToolbarSettingsController's bookmark-reorder section,
        // which persists straight through ContainerRepository the same
        // way FileBrowserPinsBookmarksController used to (see
        // decoy_local_marks_service.dart for why that's unsafe here).
        containerUri: container.isLocalStorage ? null : container.uri,
        onSettingsClosed: onSettingsClosed,
      ),
    ],
  );
}

Widget buildBrowserAppBarStatsSubtitle(
  BuildContext context, {
  required int dirCount,
  required int fileCount,
  required bool isFiltered,
  required int? freeSpace,
}) {
  final cs = Theme.of(context).colorScheme;
  final textTheme = Theme.of(context).textTheme;
  final style = textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant);
  final parts = <String>[
    if (dirCount > 0) context.l10n.statsFolderCount(dirCount),
    if (fileCount > 0) context.l10n.statsFileCount(fileCount),
    if (dirCount == 0 && fileCount == 0) ...[
      context.l10n.statsFolderCount(0),
      context.l10n.statsFileCount(0),
    ],
    if (freeSpace != null && freeSpace >= 0) context.l10n.freeSpaceLabel(formatBytes(freeSpace)),
    if (isFiltered) context.l10n.filteredLabel,
  ];
  return Text(
    parts.join(' · '),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: style,
  );
}