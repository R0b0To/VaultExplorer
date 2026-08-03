import 'package:flutter/material.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/core/widgets/activity/app_bar_clipboard_chip.dart';
import 'package:vaultexplorer/data/models/file_manager_action.dart';
import 'package:vaultexplorer/data/models/file_manager_toolbar_config.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/vault_item.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/features/browser/browser_dialogs.dart';
import 'package:vaultexplorer/features/browser/widgets/selection_app_bar.dart';
import 'package:vaultexplorer/features/browser/widgets/selection_app_bar_wide.dart';
import 'package:vaultexplorer/features/browser/widgets/settings_menu_button.dart';


PreferredSizeWidget buildBrowserAppBar(
  BuildContext context, {
  required MountedContainer container,
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
  required VoidCallback onExitSelectionMode,
  required VoidCallback onSelectAll,
  required VoidCallback onCopy,
  required VoidCallback onCut,
  required VoidCallback onExport,
  required VoidCallback onDelete,
  required void Function({required bool pin}) onTogglePin,
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
  required ValueChanged<String?> onFilterChanged,
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
    final totalBytes = selectedTotalBytes;
    final isPending = hasPendingFolderSizes;
    final sizeLabel = isPending
        ? (totalBytes > 0
              ? '${formatBytes(totalBytes)} (calculating…)'
              : 'calculating…')
        : formatBytes(totalBytes);
    void doRename() {
      final entries = selectedItems.toList();
      for (final entry in entries) {
        final parts = entry.name.split('.');
        final ext = parts.length > 1 ? parts.last.toLowerCase() : '';
        if (VaultItemType.values.any((t) => t.name.toLowerCase() == ext)) {
          onSetStatus('Edit secure items to rename them', error: false);
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
        onSetStatus('Vault items cannot be opened in external apps', error: true);
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
    );
  }
  return AppBar(
    leading: IconButton(
      icon: const Icon(Icons.arrow_back),
      tooltip: 'Back to dashboard',
      onPressed: () => Navigator.of(context).pop(),
    ),
    title: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                container.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isReadOnly) ...[
              const SizedBox(width: 8),
              Tooltip(
                message: 'Mounted read-only',
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
                        'RO',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
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
        currentFilter: currentFilter,
        onFilterChanged: onFilterChanged,
        onSettingsClosed: onSettingsClosed,
      ),
    ],
  );
}

/// TD-8: extracted alongside [buildBrowserAppBar] -- was already a small,
/// self-contained method (`_buildAppBarStatsSubtitle`), just given
/// `freeSpace` as an explicit parameter instead of reading `_freeSpace`
/// directly, since it no longer has privileged access to the State object.
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
    if (freeSpace >= 0) '${formatBytes(freeSpace)} free',
    if (isFiltered) 'filtered',
  ];
  return Text(
    parts.join(' · '),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: style,
  );
}
