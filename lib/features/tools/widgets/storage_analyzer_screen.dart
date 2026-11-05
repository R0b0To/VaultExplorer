// Storage Analyzer: see where storage space goes, then do something about it.
//
// Four views over one scanned folder tree --
//   Map      the current folder as a treemap; big tiles are big files/folders
//   Folders  the same folder as a sortable list with each item's share
//   Types    usage by file type, drilling into the largest files of one type
//   Cleanup  suggestions (large, stale, temporary, empty) and the biggest files
// -- and one shared selection. Long-press (or the row menu) selects; the bar
// at the bottom deletes, copies a path, or jumps to the file browser.
// File previews open above the analyzer, keeping the current scan intact.
//
// Deleting goes through the same background file operation the browser uses,
// after a confirmation that states how much space it frees and that it cannot
// be undone (storage has no recycle bin).
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:vaultexplorer/core/api/vault_book_api.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area_scope.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/core/utils/path_clipboard.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/data/models/vault_item.dart';
import 'package:vaultexplorer/data/models/vault_marks.dart';
import 'package:vaultexplorer/data/services/vault_items_service.dart';
import 'package:vaultexplorer/features/browser/controllers/bookmark_navigation_request.dart';
import 'package:vaultexplorer/features/browser/viewer/books/comic_pages.dart';
import 'package:vaultexplorer/features/browser/viewer/books/comic_reader_screen.dart';
import 'package:vaultexplorer/features/browser/viewer/books/epub_reader_screen.dart';
import 'package:vaultexplorer/features/browser/viewer/html_viewer_screen.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_screen.dart';
import 'package:vaultexplorer/features/browser/viewer/pdf_viewer_screen.dart';
import 'package:vaultexplorer/features/browser/viewer/text_editor_screen.dart';
import 'package:vaultexplorer/features/vault_item/vault_item_detail_screen.dart';
import 'package:vaultexplorer/features/tools/widgets/storage_analyzer_controller.dart';
import 'package:vaultexplorer/features/tools/widgets/storage_analyzer_views.dart';
import 'package:vaultexplorer/features/tools/widgets/storage_analyzer_widgets.dart';

enum _StorageTab { map, folders, types, cleanup }

class StorageAnalyzerScreen extends ConsumerStatefulWidget {
  final ValueListenable<List<MountedContainer>> mountedContainers;
  final ValueListenable<MountedContainer?>? localStorageContainer;

  /// Opens a storage target in the file browser. When null (the tool was
  /// opened somewhere with no browser to go to) the "show in file browser"
  /// action is hidden.
  final ValueChanged<MountedContainer>? onOpenInBrowser;

  const StorageAnalyzerScreen({
    super.key,
    required this.mountedContainers,
    this.localStorageContainer,
    this.onOpenInBrowser,
  });

  @override
  ConsumerState<StorageAnalyzerScreen> createState() =>
      _StorageAnalyzerScreenState();
}

class _StorageAnalyzerScreenState extends ConsumerState<StorageAnalyzerScreen> {
  _StorageTab _tab = _StorageTab.map;

  /// Which cleanup suggestion is open for review (a [CleanupKind] name or
  /// [storageReviewBiggest]); null shows the list of suggestions.
  String? _review;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final notifier = ref.read(storageAnalyzerProvider.notifier);
      notifier.watchContentChanges();
      notifier.onTargetsChanged(_availableTargets());
    });
    widget.mountedContainers.addListener(_onMountedChanged);
    widget.localStorageContainer?.addListener(_onMountedChanged);
  }

  @override
  void dispose() {
    widget.mountedContainers.removeListener(_onMountedChanged);
    widget.localStorageContainer?.removeListener(_onMountedChanged);
    super.dispose();
  }

  List<MountedContainer> _availableTargets() {
    final localStorage = widget.localStorageContainer?.value;
    return [
      ...widget.mountedContainers.value,
      if (localStorage != null) localStorage,
    ];
  }

  void _onMountedChanged() {
    ref
        .read(storageAnalyzerProvider.notifier)
        .onTargetsChanged(_availableTargets());
  }

  Future<void> _showTargetPickerSheet(
    BuildContext context,
    List<MountedContainer> targets,
    StorageAnalyzerState st,
    StorageAnalyzer notifier,
  ) async {
    final l10n = context.l10n;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: Text(
                  l10n.storageAnalyzerTargetLabel,
                  style: context.typography.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Divider(height: 1),
              for (final target in targets)
                ListTile(
                  leading: const Icon(Icons.storage_rounded),
                  title: Text(target.displayName),
                  selected: st.selected?.volId == target.volId,
                  trailing: st.selected?.volId == target.volId
                      ? Icon(Icons.check_rounded, color: context.colors.primary)
                      : null,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    unawaited(notifier.selectTarget(target));
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _setTab(_StorageTab tab) {
    if (tab == _tab) return;
    setState(() {
      _tab = tab;
      _review = null;
    });
  }

  // ── Interaction ────────────────────────────────────────────────────────────

  StorageActions _actions(StorageAnalyzer notifier) {
    return StorageActions(
      onTap: _onTapNode,
      onLongPress: (node) {
        if (ref.read(storageAnalyzerProvider).busy) return;
        unawaited(HapticFeedback.selectionClick());
        notifier.toggleSelected(node.path);
      },
      onMore: (node) => unawaited(_showNodeSheet(node)),
      onNavigate: notifier.openFolder,
    );
  }

  void _onTapNode(StorageNode node, bool drill) {
    final st = ref.read(storageAnalyzerProvider);
    final notifier = ref.read(storageAnalyzerProvider.notifier);
    if (st.busy) return;
    // Once something is ticked, taps keep ticking.
    if (st.hasSelection) {
      notifier.toggleSelected(node.path);
      return;
    }
    if (node.isDir && drill) {
      notifier.openFolder(node.path);
      return;
    }
    unawaited(_showNodeSheet(node));
  }

  Future<void> _showNodeSheet(StorageNode node) async {
    final st = ref.read(storageAnalyzerProvider);
    if (st.busy) return;
    final notifier = ref.read(storageAnalyzerProvider.notifier);
    final l10n = context.l10n;
    final cs = context.colors;
    final textTheme = context.typography;
    final canBrowse = widget.onOpenInBrowser != null;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        void closeThen(VoidCallback action) {
          Navigator.of(sheetContext).pop();
          action();
        }

        return AppBottomSheet(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                node.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                node.isDir
                    ? '${formatBytes(node.sizeBytes)} · ${l10n.storageAnalyzerFileCount(node.fileCount)}'
                    : '${formatBytes(node.sizeBytes)} · ${storageCategoryLabel(context, node.category)}',
                style: textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 1),
              Row(
                children: [
                  Icon(
                    Icons.folder_outlined,
                    size: 14,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      node.isDir
                          ? (node.path.isEmpty ? '/' : node.path)
                          : (node.parentPath.isEmpty ? '/' : node.parentPath),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              if (node.isDir)
                SheetOptionTile(
                  icon: Icons.folder_open_rounded,
                  title: l10n.storageAnalyzerOpenFolder,
                  onTap: () => closeThen(() {
                    notifier.openFolder(node.path);
                    // Flat lists have no folder to open into, so go where
                    // there is one.
                    if (_tab != _StorageTab.map &&
                        _tab != _StorageTab.folders) {
                      _setTab(_StorageTab.folders);
                    }
                  }),
                ),
              if (node.isDir)
                SheetOptionTile(
                  icon: Icons.refresh_rounded,
                  title: l10n.storageAnalyzerRescanFolder,
                  onTap: () => closeThen(
                    () => unawaited(notifier.refreshFolder(node.path)),
                  ),
                ),
              if (!node.isDir)
                SheetOptionTile(
                  icon: Icons.open_in_new_rounded,
                  title: l10n.openAction,
                  onTap: () => closeThen(() => unawaited(_openItem(node))),
                ),
              if (canBrowse)
                SheetOptionTile(
                  icon: Icons.drive_file_move_outline,
                  title: l10n.goToLocationAction,
                  onTap: () => closeThen(() => _showInBrowser(node)),
                ),
              SheetOptionTile(
                icon: Icons.content_copy_rounded,
                title: l10n.copyPathAction,
                onTap: () => closeThen(
                  () => unawaited(copyPathToClipboard(context, node.path)),
                ),
              ),
              SheetOptionTile(
                icon: Icons.check_circle_outline_rounded,
                title: l10n.storageAnalyzerSelectAction,
                onTap: () =>
                    closeThen(() => notifier.toggleSelected(node.path)),
              ),
              SheetOptionTile(
                icon: Icons.delete_outline_rounded,
                iconColor: cs.error,
                title: l10n.delete,
                onTap: () =>
                    closeThen(() => unawaited(_confirmAndDelete([node]))),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Leaves the analyzer for the file browser, opened on the folder holding
  /// [node] (or on [node] itself if it is a folder).
  void _showInBrowser(StorageNode node) => _openInBrowser(node);

  void _openInBrowser(StorageNode node) {
    final open = widget.onOpenInBrowser;
    final container = ref.read(storageAnalyzerProvider).selected;
    if (open == null || container == null) return;
    final requests = ref.read(bookmarkNavigationRequestsProvider.notifier);
    final navigator = Navigator.of(context);
    final dir = node.isDir ? node.path : node.parentPath;
    final bookmark = VaultBookmark(dir, isDir: true);
    navigator.pop();
    open(container);
    requests.request(container.volId, bookmark);
  }

  /// Opens a file above the analyzer route so Back returns to the same scan,
  /// folder, tab, and selection. The browser hand-off is reserved for the
  /// separate "Go to location" action.
  Future<void> _openItem(StorageNode node) async {
    final container = ref.read(storageAnalyzerProvider).selected;
    if (container == null || node.isDir) return;

    final extension = node.name.contains('.')
        ? node.name.split('.').last.toLowerCase().trim()
        : '';
    try {
      if (!container.isLocalStorage &&
          VaultItemType.values.any(
            (type) => type.name.toLowerCase() == extension,
          )) {
        final item = await ref
            .read(vaultItemsServiceProvider)
            .loadItem(container, node.path);
        if (!mounted) return;
        if (item == null) {
          _showOpenError(context.l10n.failedToReadSecureItem);
          return;
        }
        final dot = node.name.lastIndexOf('.');
        item.title = dot > 0 ? node.name.substring(0, dot) : node.name;
        await _pushItemViewer(
          VaultItemDetailScreen(
            container: container,
            item: item,
            filePath: node.path,
          ),
        );
        return;
      }

      if (MediaViewerConstants.isSupported(node.name)) {
        await _pushMediaViewer(container, node.path);
        return;
      }
      if (extension == 'pdf') {
        await _pushItemViewer(
          PdfViewerScreen(container: container, filePath: node.path),
        );
        return;
      }
      if (const {
        'txt',
        'md',
        'markdown',
        'csv',
        'json',
        'xml',
      }.contains(extension)) {
        await _pushItemViewer(
          TextEditorScreen(container: container, filePath: node.path),
        );
        return;
      }
      if ((extension == 'html' || extension == 'htm') &&
          !container.isLocalStorage) {
        await _pushItemViewer(
          HtmlViewerScreen(container: container, filePath: node.path),
        );
        return;
      }
      if (extension == 'epub' ||
          const {'cbz', 'cbr', 'cb7', 'cbt'}.contains(extension)) {
        await _openBookItem(container, node, extension == 'epub');
        return;
      }

      await _openWithSystemApp(container, node);
    } catch (_) {
      if (!mounted) return;
      _showOpenError(context.l10n.couldNotOpenFile(node.name));
    }
  }

  Future<void> _pushItemViewer(Widget viewer) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SkinAreaScope(area: SkinArea.files, child: viewer),
      ),
    );
  }

  Future<void> _pushMediaViewer(
    MountedContainer container,
    String filePath,
  ) async {
    await Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.transparent,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: const Duration(milliseconds: 250),
        pageBuilder: (_, _, _) => SkinAreaScope(
          area: SkinArea.files,
          child: MediaViewerScreen(
            container: container,
            mediaFiles: [filePath],
            initialIndex: 0,
            startingFolder: filePath.contains('/')
                ? filePath.substring(0, filePath.lastIndexOf('/'))
                : '',
            thumbnailQuality: ThumbnailQuality.defaultQuality,
            thumbnailCacheMode: ThumbnailCacheMode.appCache,
          ),
        ),
        transitionsBuilder: (_, animation, _, child) => FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          ),
          child: child,
        ),
      ),
    );
  }

  Future<void> _openBookItem(
    MountedContainer container,
    StorageNode node,
    bool isEpub,
  ) async {
    final api = ref.read(vaultBookApiProvider);
    final result = await api.open(
      container: container,
      path: node.path,
      kind: isEpub ? BookKind.epub : BookKind.comic,
    );
    final token = result.token;
    if (result.status == BookOpenStatus.ok && token != null) {
      if (isEpub && result.epub != null && result.epub!.spine.isNotEmpty) {
        await _pushItemViewer(
          EpubReaderScreen(
            container: container,
            fallbackTitle: node.name,
            filePath: node.path,
            token: token,
            info: result.epub!,
          ),
        );
        return;
      }
      if (!isEpub && !result.hasEncryptedEntries) {
        final pages = comicPageNames(result.entries);
        if (pages.isNotEmpty) {
          await _pushItemViewer(
            ComicReaderScreen(
              container: container,
              title: node.name,
              filePath: node.path,
              token: token,
              pages: pages,
            ),
          );
          return;
        }
      }
      unawaited(api.close(token));
    }
    await _openWithSystemApp(container, node);
  }

  Future<void> _openWithSystemApp(
    MountedContainer container,
    StorageNode node,
  ) async {
    final ok = container.isRawLocal
        ? await ref
              .read(vaultLocalShareApiProvider)
              .openLocalFileWithApp(p.join(container.uri, node.path))
        : await ref
              .read(vaultFileIoApiProvider)
              .openWithApp(container, node.path);
    if (!ok && mounted) _showOpenError(context.l10n.noAppFoundForFileType);
  }

  void _showOpenError(String message) {
    showAppSnackBar(context, message: message, tone: AppBannerTone.error);
  }

  Future<void> _confirmAndDelete(List<StorageNode> nodes) async {
    final st = ref.read(storageAnalyzerProvider);
    final tree = st.tree;
    if (nodes.isEmpty || tree == null || st.busy) return;
    final l10n = context.l10n;

    if (!st.canModify) {
      showAppSnackBar(
        context,
        message: l10n.readOnlyCantDelete,
        tone: AppBannerTone.warning,
      );
      return;
    }

    // Collapse nested picks exactly as the delete itself will, so the dialog
    // describes what will really happen.
    final selection = tree.resolveSelection(nodes.map((n) => n.path));
    if (selection.isEmpty) return;

    unawaited(HapticFeedback.heavyImpact());
    final message = selection.hasFolder
        ? l10n.storageAnalyzerDeleteFoldersMessage(
            '${selection.files}',
            formatBytes(selection.bytes),
          )
        : l10n.storageAnalyzerDeleteFilesMessage(formatBytes(selection.bytes));
    final confirmed = await showAppConfirmDialog(
      context,
      title: l10n.deleteItemsTitle(selection.nodes.length),
      message: message,
      confirmLabel: l10n.delete,
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;

    try {
      final result = await ref
          .read(storageAnalyzerProvider.notifier)
          .deleteNodes(selection.nodes, l10n);
      if (!mounted) return;
      _reportDelete(result);
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: l10n.storageAnalyzerDeleteError,
        tone: AppBannerTone.error,
      );
    }
  }

  void _reportDelete(StorageDeleteResult r) {
    final l10n = context.l10n;
    if (r.readOnly) {
      showAppSnackBar(
        context,
        message: l10n.readOnlyCantDelete,
        tone: AppBannerTone.warning,
      );
    } else if (r.deleted == 0 && r.failed == 0) {
      return; // superseded by a rescan or the screen closing
    } else if (r.failed == 0) {
      showAppSnackBar(
        context,
        message: l10n.storageAnalyzerDeleteDone(formatBytes(r.freedBytes)),
        tone: AppBannerTone.success,
      );
    } else if (r.deleted == 0) {
      showAppSnackBar(
        context,
        message: l10n.storageAnalyzerDeleteNone,
        tone: AppBannerTone.error,
      );
    } else {
      showAppSnackBar(
        context,
        message: l10n.storageAnalyzerDeletePartial(
          '${r.deleted}',
          '${r.failed}',
          formatBytes(r.freedBytes),
        ),
        tone: AppBannerTone.warning,
      );
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(storageAnalyzerProvider);
    final notifier = ref.read(storageAnalyzerProvider.notifier);
    final l10n = context.l10n;
    final selection = st.selection;
    final showBar = st.hasSelection && !selection.isEmpty;
    final mountedTargets = _availableTargets();

    return PopScope(
      // Back leaves selection mode before it leaves the screen.
      canPop: !st.hasSelection,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) notifier.clearSelection();
      },
      child: Scaffold(
        appBar: AppBar(
          title: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            onTap: (!st.busy && mountedTargets.length > 1)
                ? () => _showTargetPickerSheet(
                    context,
                    mountedTargets,
                    st,
                    notifier,
                  )
                : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.toolStorageAnalyzerTitle,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  if (st.selected != null) ...[
                    const SizedBox(height: 2),
                    if (mountedTargets.length > 1)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: context.colors.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(AppRadius.full),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.storage_rounded,
                              size: 13,
                              color: context.colors.primary,
                            ),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                st.selected!.displayName,
                                style: context.typography.labelSmall?.copyWith(
                                  color: context.colors.onSurface,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 2),
                            Icon(
                              Icons.arrow_drop_down_rounded,
                              size: 16,
                              color: context.colors.onSurfaceVariant,
                            ),
                          ],
                        ),
                      )
                    else
                      Text(
                        st.selected!.displayName,
                        style: context.typography.bodySmall?.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: l10n.duplicateFinderRescan,
              onPressed: st.selected == null || st.loading || st.busy
                  ? null
                  : () => unawaited(notifier.rescan()),
            ),
          ],
        ),
        bottomNavigationBar: showBar
            ? _SelectionBar(
                selection: selection,
                busy: st.busy,
                canBrowse: widget.onOpenInBrowser != null,
                onClear: notifier.clearSelection,
                onDelete: () => unawaited(_confirmAndDelete(selection.nodes)),
                onBrowse: () => _showInBrowser(selection.nodes.first),
                onCopyPath: () => unawaited(
                  copyPathToClipboard(context, selection.nodes.first.path),
                ),
              )
            : null,
        body: ValueListenableBuilder<List<MountedContainer>>(
          valueListenable: widget.mountedContainers,
          builder: (context, mountedList, _) {
            final localStorageListenable = widget.localStorageContainer;
            if (localStorageListenable == null) {
              return _buildTargetsBody(
                context,
                mountedList,
                null,
                st,
                notifier,
              );
            }
            return ValueListenableBuilder<MountedContainer?>(
              valueListenable: localStorageListenable,
              builder: (context, localStorage, _) => _buildTargetsBody(
                context,
                mountedList,
                localStorage,
                st,
                notifier,
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTargetsBody(
    BuildContext context,
    List<MountedContainer> mountedList,
    MountedContainer? localStorage,
    StorageAnalyzerState st,
    StorageAnalyzer notifier,
  ) {
    final targets = [...mountedList, if (localStorage != null) localStorage];
    if (targets.isEmpty) {
      return AppEmptyState(
        icon: Icons.pie_chart_outline_rounded,
        title: context.l10n.storageAnalyzerNoTargetsTitle,
        message: context.l10n.storageAnalyzerNoTargetsMessage,
      );
    }
    return _buildBody(context, targets, st, notifier);
  }

  Widget _buildBody(
    BuildContext context,
    List<MountedContainer> mountedList,
    StorageAnalyzerState st,
    StorageAnalyzer notifier,
  ) {
    final l10n = context.l10n;
    final cs = context.colors;
    final selected = st.selected;
    final actions = _actions(notifier);
    final rootLabel = selected?.displayName ?? '';

    final slivers = <Widget>[];

    final tree = st.tree;
    if (st.loading || (selected != null && tree == null)) {
      slivers.add(SliverToBoxAdapter(child: _ScanningPanel(st.progress)));
    } else if (selected != null && tree != null) {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _UsageSummary(state: st),
          ),
        ),
      );
      if (st.stale) {
        slivers.add(
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: InlineBanner(
                l10n.storageAnalyzerStaleNotice,
                icon: Icons.sync_problem_rounded,
                trailing: TextButton(
                  onPressed: st.busy
                      ? null
                      : () => unawaited(notifier.rescan()),
                  child: Text(l10n.duplicateFinderRescan),
                ),
              ),
            ),
          ),
        );
      }
      if (st.truncated || st.hasUnreadable) {
        slivers.add(
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: InlineBanner(
                st.truncated
                    ? l10n.storageAnalyzerScanTruncatedNotice(
                        '${st.scannedCount}',
                      )
                    : l10n.storageAnalyzerPartialNotice,
                tone: AppBannerTone.warning,
              ),
            ),
          ),
        );
      }
      slivers.add(SliverToBoxAdapter(child: _buildTabs(context)));

      switch (_tab) {
        case _StorageTab.map:
          slivers.addAll(
            buildStorageMapSlivers(
              context,
              state: st,
              notifier: notifier,
              actions: actions,
              rootLabel: rootLabel,
              onShowList: () => _setTab(_StorageTab.folders),
            ),
          );
        case _StorageTab.folders:
          slivers.addAll(
            buildStorageFoldersSlivers(
              context,
              state: st,
              notifier: notifier,
              actions: actions,
              rootLabel: rootLabel,
            ),
          );
        case _StorageTab.types:
          slivers.addAll(
            buildStorageTypesSlivers(
              context,
              state: st,
              notifier: notifier,
              actions: actions,
            ),
          );
        case _StorageTab.cleanup:
          slivers.addAll(
            buildStorageCleanupSlivers(
              context,
              state: st,
              notifier: notifier,
              actions: actions,
              review: _review,
              onReview: (key) => setState(() => _review = key),
            ),
          );
      }
    }

    slivers.add(
      const SliverToBoxAdapter(
        child: SizedBox(height: AppSpacing.floatingStackClearance),
      ),
    );

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: CustomScrollView(slivers: slivers),
      ),
    );
  }

  Widget _buildTabs(BuildContext context) {
    final l10n = context.l10n;
    final textTheme = context.typography;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<_StorageTab>(
          showSelectedIcon: false,
          style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          segments: [
            ButtonSegment<_StorageTab>(
              value: _StorageTab.map,
              label: Text(
                l10n.storageAnalyzerTabMap,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.labelMedium,
              ),
            ),
            ButtonSegment<_StorageTab>(
              value: _StorageTab.folders,
              label: Text(
                l10n.storageAnalyzerTabFolders,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.labelMedium,
              ),
            ),
            ButtonSegment<_StorageTab>(
              value: _StorageTab.types,
              label: Text(
                l10n.storageAnalyzerTabTypes,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.labelMedium,
              ),
            ),
            ButtonSegment<_StorageTab>(
              value: _StorageTab.cleanup,
              label: Text(
                l10n.storageAnalyzerTabCleanup,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.labelMedium,
              ),
            ),
          ],
          selected: {_tab},
          onSelectionChanged: (selectedSet) {
            if (selectedSet.isNotEmpty) _setTab(selectedSet.first);
          },
        ),
      ),
    );
  }
}

/// Used / free at a glance. A compact ring plus text rather than the former
/// full-width gauge, so the interactive views start higher on the screen.
class _UsageSummary extends StatelessWidget {
  const _UsageSummary({required this.state});

  final StorageAnalyzerState state;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;
    final l10n = context.l10n;

    final total = state.totalBytes ?? -1;
    final free = state.freeBytes ?? -1;
    final scanned = state.tree?.totalBytes ?? 0;
    final files = state.tree?.fileCount ?? 0;
    final hasCapacity = total > 0 && free >= 0;
    final used = hasCapacity ? (total - free).clamp(0, total) : 0;
    final double fraction = hasCapacity
        ? (used / total).clamp(0.0, 1.0).toDouble()
        : 1.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            height: 72,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: fraction,
                    strokeWidth: 8,
                    backgroundColor: cs.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation(cs.primary),
                  ),
                ),
                if (hasCapacity)
                  Text(
                    '${(fraction * 100).round()}%',
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  )
                else
                  Icon(Icons.folder_shared_rounded, color: cs.primary),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasCapacity
                      ? l10n.storageAnalyzerUsedOfTotal(
                          formatBytes(used),
                          formatBytes(total),
                        )
                      : l10n.storageAnalyzerContentSize(formatBytes(scanned)),
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (hasCapacity)
                  Text(
                    l10n.storageAnalyzerFreeSpace(formatBytes(free)),
                    style: textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                Text(
                  hasCapacity
                      ? '${l10n.storageAnalyzerFileCount(files)} · '
                            '${formatBytes(scanned)}'
                      : l10n.storageAnalyzerFileCount(files),
                  style: textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown while scanning: a spinner and a live count, so a big vault reads as
/// working rather than stuck.
class _ScanningPanel extends StatelessWidget {
  const _ScanningPanel(this.progress);

  final StorageScanProgress? progress;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;
    final l10n = context.l10n;
    final p = progress;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Column(
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: AppSpacing.md),
          Text(l10n.storageAnalyzerScanningMessage),
          if (p != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.storageAnalyzerScanProgress(
                '${p.files}',
                formatBytes(p.bytes),
              ),
              style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

/// The bar that appears once anything is ticked: how much, and what to do.
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.selection,
    required this.busy,
    required this.canBrowse,
    required this.onClear,
    required this.onDelete,
    required this.onBrowse,
    required this.onCopyPath,
  });

  final StorageSelection selection;
  final bool busy;
  final bool canBrowse;
  final VoidCallback onClear;
  final VoidCallback onDelete;
  final VoidCallback onBrowse;
  final VoidCallback onCopyPath;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;
    final l10n = context.l10n;
    final single = selection.nodes.length == 1;

    return Material(
      color: cs.surfaceContainerHigh,
      elevation: 3,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 12, 6),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.close_rounded),
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: busy ? null : onClear,
              ),
              Expanded(
                child: Text(
                  l10n.storageAnalyzerSelectedSummary(
                    selection.nodes.length,
                    formatBytes(selection.bytes),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (single && canBrowse)
                IconButton(
                  icon: const Icon(Icons.drive_file_move_outline),
                  tooltip: l10n.goToLocationAction,
                  onPressed: busy ? null : onBrowse,
                ),
              if (single)
                IconButton(
                  icon: const Icon(Icons.content_copy_rounded),
                  tooltip: l10n.copyPathAction,
                  onPressed: busy ? null : onCopyPath,
                ),
              const SizedBox(width: 4),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: cs.error,
                  foregroundColor: cs.onError,
                ),
                onPressed: busy ? null : onDelete,
                icon: const Icon(Icons.delete_outline_rounded),
                label: Text(l10n.delete),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
