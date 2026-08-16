import 'package:flutter/material.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/file_type_utils.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/core/widgets/activity/app_bar_clipboard_chip.dart';
import 'package:vaultexplorer/data/models/file_manager_action.dart';
import 'package:vaultexplorer/data/models/file_manager_toolbar_config.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/vault_item.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/features/browser/browser_dialogs.dart';
import 'package:vaultexplorer/features/browser/file_browser_screen.dart' show PathSegment;
import 'package:vaultexplorer/features/browser/widgets/selection_app_bar.dart';
import 'package:vaultexplorer/features/browser/widgets/selection_app_bar_wide.dart';
import 'package:vaultexplorer/features/browser/widgets/settings_menu_button.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';

PreferredSizeWidget buildBrowserAppBar(
  BuildContext context, {
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
  required int freeSpace,
  required int selectedTotalBytes,
  required bool hasPendingFolderSizes,
  required Map<FileManagerAction, WidgetBuilder> actionBuilders,
  required bool Function(RawEntry entry) isFolderMounted,
  required bool Function(RawEntry entry) isPinned,
  required bool Function(RawEntry entry) isFavourite,
  required VoidCallback onExitSelectionMode,
  required VoidCallback onSelectAll,
  required VoidCallback onCopy,
  required VoidCallback onCut,
  required VoidCallback onExport,
  required VoidCallback onDelete,
  required VoidCallback onEncryptSelected,
  required VoidCallback onDecryptSelected,
  required void Function({required bool pin}) onTogglePin,
  required void Function({required bool favourite}) onToggleFavourite,
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
  required Future<void> Function() onSettingsClosed,
  required bool isFiltered,
  required VoidCallback? onPaste,
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
    final showPinOption = selectedItems.any((item) => !isPinned(item));
    final showUnpinOption = selectedItems.any((item) => isPinned(item));
    final showFavouriteOption = selectedItems.any((item) => !isFavourite(item));
    final showUnfavouriteOption = selectedItems.any((item) => isFavourite(item));
    // "Encrypt" targets selected files that aren't already app-encrypted
    // output; "Decrypt" targets selected files that are (.vxenc/.aes) --
    // see isAppEncryptedFileName. Folders are never eligible for either,
    // matching the Single File Crypto tool's file-only scope.
    final showEncryptOption = selectedItems
        .any((item) => !item.isDir && !isAppEncryptedFileName(item.name));
    final showDecryptOption = selectedItems
        .any((item) => !item.isDir && isAppEncryptedFileName(item.name));
    final totalBytes = selectedTotalBytes;
    final isPending = hasPendingFolderSizes;
    final sizeLabel = isPending
        ? (totalBytes > 0
              ? context.l10n.sizeCalculatingWithBytesLabel(formatBytes(totalBytes))
              : context.l10n.sizeCalculatingLabel)
        : formatBytes(totalBytes);
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
      BrowserDialogs.showRename(
        context,
        container: container,
        oldEntries: entries,
        existingEntries: allItems,
        currentDirPath: currentDirPath,
        onSuccess: () => onDirectoryReload(currentDirPath),
        readOnly: isReadOnly,
      );
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
      final settings = await AppSettingsService.loadSettings();
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
    if (!isLandscape) {
      return SelectionAppBar(
        selectedCount: selectedItems.length,
        selectionLabel: sizeLabel,
        singleSelected: single,
        singleFileSelected: singleFile,
        singleFolderSelected: singleFolder,
        folderDocumentProviderMounted: folderDocProviderMounted,
        readOnly: isReadOnly,
        showPinOption: showPinOption,
        showUnpinOption: showUnpinOption,
        onPin: () => onTogglePin(pin: true),
        onUnpin: () => onTogglePin(pin: false),
        showFavouriteOption: showFavouriteOption,
        showUnfavouriteOption: showUnfavouriteOption,
        onFavourite: () => onToggleFavourite(favourite: true),
        onUnfavourite: () => onToggleFavourite(favourite: false),
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
        onDelete: onDelete,
        onOpenWithApp: doOpenWithApp,
        onToggleDocumentProvider: doToggleDocProvider,
      );
    }
    return SelectionAppBarWide(
      selectedCount: selectedItems.length,
      selectionLabel: sizeLabel,
      singleFileSelected: singleFile,
      singleFolderSelected: singleFolder,
      folderDocumentProviderMounted: folderDocProviderMounted,
      readOnly: isReadOnly,
      showPinOption: showPinOption,
      showUnpinOption: showUnpinOption,
      showFavouriteOption: showFavouriteOption,
      showUnfavouriteOption: showUnfavouriteOption,
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
      onDelete: onDelete,
      onOpenWithApp: doOpenWithApp,
      onToggleDocumentProvider: doToggleDocProvider,
      onPin: () => onTogglePin(pin: true),
      onUnpin: () => onTogglePin(pin: false),
      onFavourite: () => onToggleFavourite(favourite: true),
      onUnfavourite: () => onToggleFavourite(favourite: false),
      onEncrypt: onEncryptSelected,
      onDecrypt: onDecryptSelected,
    );
  }

  final hasParents = pathStack.length > 1;
  final currentSegment = pathStack.last;
  final currentTitle = pathStack.length == 1
      ? container.displayName
      : currentSegment.label;

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
  });}

  return AppBar(
    leading: IconButton(
      icon: const Icon(Icons.arrow_back),
      tooltip: context.l10n.backToDashboardTooltip,
      onPressed: () => Navigator.of(context).pop(),
    ),
    title: Column(
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
    actions: [
      AppBarClipboardButton(onPaste: onPaste),
      if (isLandscape && showActionBar) ...[
        ...toolbarConfig.visible.map((action) => actionBuilders[action]!(context)),
      ],
      SettingsMenuButton(
        containerUri: container.uri,
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
  required int freeSpace,
}) {
  final cs = Theme.of(context).colorScheme;
  final textTheme = Theme.of(context).textTheme;
  final style = textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant);
  final parts = <String>[
    if (freeSpace >= 0) context.l10n.freeSpaceLabel(formatBytes(freeSpace)),
    if (isFiltered) context.l10n.filteredLabel,
  ];
  return Text(
    parts.join(' · '),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: style,
  );
}