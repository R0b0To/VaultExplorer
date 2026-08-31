import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/core/widgets/feedback/app_empty_state.dart';
import 'package:vaultexplorer/core/widgets/feedback/app_feedback.dart';
import 'package:vaultexplorer/core/widgets/activity/app_bar_clipboard_chip.dart';
import 'package:vaultexplorer/core/widgets/activity/app_bar_transfer_button.dart';
import 'package:vaultexplorer/core/widgets/feedback/inline_banner.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/core/providers/legacy_services_providers.dart';
import 'package:vaultexplorer/data/models/browser_layout_mode.dart';
import 'package:vaultexplorer/data/models/clipboard_item.dart';
import 'package:vaultexplorer/data/models/file_operation.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/cross_container_clipboard.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/features/browser/browser_dialogs.dart';
import 'package:vaultexplorer/features/browser/controllers/file_browser_selection_controller.dart';
import 'package:vaultexplorer/features/browser/controllers/file_browser_sort_controller.dart';
import 'package:vaultexplorer/features/browser/file_browser_screen.dart' show PathSegment;
import 'package:vaultexplorer/features/browser/mixins/sort_mixin.dart' show SortBy, compareEntriesWithPinned;
import 'package:vaultexplorer/features/browser/paste_conflict_detection.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';
import 'package:vaultexplorer/features/browser/widgets/bottom_search_bar.dart';
import 'package:vaultexplorer/features/browser/widgets/breadcrumb_bar.dart';
import 'package:vaultexplorer/features/browser/widgets/conflict_resolution_sheet.dart';
import 'package:vaultexplorer/features/browser/widgets/file_list_view.dart';
import 'package:vaultexplorer/features/browser/widgets/layout_mode_menu_button.dart';
import 'package:vaultexplorer/features/browser/widgets/sort_menu_button.dart';
import 'package:vaultexplorer/features/decoy/local/decoy_archive_browse_screen.dart';
import 'package:vaultexplorer/features/decoy/local/decoy_local_repository.dart';
import 'package:vaultexplorer/features/decoy/local/decoy_local_repository_provider.dart';
import 'package:vaultexplorer/features/decoy/local/local_image_viewer_screen.dart';
import 'package:vaultexplorer/features/decoy/local/local_text_viewer_screen.dart';
import 'package:vaultexplorer/features/decoy/local/widgets/local_media_grid_view.dart';
import 'package:vaultexplorer/features/decoy/local/widgets/local_type_filter_button.dart';
import 'package:vaultexplorer/features/decoy/widgets/hidden_vault_trigger.dart';

class DecoyLocalExplorerScreen extends ConsumerStatefulWidget {
  const DecoyLocalExplorerScreen({super.key});

  @override
  ConsumerState<DecoyLocalExplorerScreen> createState() => _DecoyLocalExplorerScreenState();
}

class _DecoyLocalExplorerScreenState extends ConsumerState<DecoyLocalExplorerScreen> {
  static const _api = VaultExplorerApi();
  DecoyLocalRepository get _repo => ref.read(decoyLocalRepositoryProvider);
  FileOperationService get _opSvc => ref.read(fileOperationServiceProvider);

  static const _documentExtensions = {
    '.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx',
    '.txt', '.md', '.csv', '.json', '.xml', '.rtf', '.odt', '.log',
  };
  static const _inAppTextExtensions = {
    '.txt', '.md', '.log', '.json', '.xml', '.csv', '.ini', '.conf', '.yaml', '.yml',
  };

  bool _checkingAccess = true;
  bool _hasAccess = false;
  bool _loading = false;
  String? _rootPath;
  bool _pathStackInitialized = false;
  late List<PathSegment> _pathStack;
  List<RawEntry> _allEntries = [];
  BrowserLayoutMode _layoutMode = BrowserLayoutMode.list;
  LocalTypeFilter _typeFilter = LocalTypeFilter.all;
  bool _searchActive = false;
  String _searchQuery = '';
  String? _statusMessage;
  bool _statusIsError = false;

  String get _currentPath => _pathStack.isEmpty ? (_rootPath ?? '') : _pathStack.last.fatPath;

  FileBrowserSelection get _selectionNotifier =>
      ref.read(fileBrowserSelectionProvider(kDecoyLocalVolId).notifier);

  FileBrowserSelectionState get _selectionState =>
      ref.read(fileBrowserSelectionProvider(kDecoyLocalVolId));

  FileBrowserSort get _sortNotifier =>
      ref.read(fileBrowserSortProvider(kDecoyLocalVolId).notifier);

  FileBrowserSortState get _sortState =>
      ref.read(fileBrowserSortProvider(kDecoyLocalVolId));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_pathStackInitialized) {
      _pathStackInitialized = true;
      _pathStack = [PathSegment(context.l10n.rootFolderLabel, '')];
      _init();
    }
  }

  Future<void> _init() async {
    final hasAccess = await _api.hasAllFilesAccess();
    if (!mounted) return;
    if (!hasAccess) {
      setState(() {
        _hasAccess = false;
        _checkingAccess = false;
      });
      return;
    }
    final root = await _repo.primaryRoot();
    if (!mounted) return;
    setState(() {
      _rootPath = root.path;
      _pathStack = [PathSegment(context.l10n.rootFolderLabel, root.path)];
      _hasAccess = true;
      _checkingAccess = false;
    });
    _load(root.path);
  }

  Future<void> _requestAccess() async {
    await _api.requestAllFilesAccess(openSettings: true);
    if (mounted) {
      setState(() => _checkingAccess = true);
      await _init();
    }
  }

  Future<void> _load(String path) async {
    setState(() => _loading = true);
    final entries = await _repo.listDirectory(path);
    if (!mounted) return;
    setState(() {
      _allEntries = entries;
      _loading = false;
    });
  }

  Future<void> _refresh() => _load(_currentPath);

  void _setStatus(String msg, {bool error = false, Duration? autoClear}) {
    if (!mounted) return;
    setState(() {
      _statusMessage = msg;
      _statusIsError = error;
    });
    final delay = autoClear ?? (error ? const Duration(seconds: 5) : const Duration(seconds: 3));
    Future.delayed(delay, () {
      if (mounted && _statusMessage == msg) {
        setState(() => _statusMessage = null);
      }
    });
  }

  bool _matchesTypeFilter(RawEntry e) {
    if (e.isDir) return false;
    switch (_typeFilter) {
      case LocalTypeFilter.all:
        return true;
      case LocalTypeFilter.image:
        return MediaViewerConstants.isImage(e.name);
      case LocalTypeFilter.video:
        return MediaViewerConstants.isVideo(e.name);
      case LocalTypeFilter.audio:
        return MediaViewerConstants.isAudio(e.name);
      case LocalTypeFilter.document:
        return _documentExtensions.contains(p.extension(e.name).toLowerCase());
    }
  }

  List<RawEntry> get _visibleEntries {
    Iterable<RawEntry> entries = _allEntries;
    if (_typeFilter != LocalTypeFilter.all) {
      entries = entries.where(_matchesTypeFilter);
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      entries = entries.where((e) => e.name.toLowerCase().contains(q));
    }
    final sortState = _sortState;
    final list = entries.toList()
      ..sort((a, b) => compareEntriesWithPinned(
            a,
            b,
            sortBy: sortState.sortBy,
            sortAscending: sortState.sortAscending,
            directoriesFirst: true,
          ));
    return list;
  }

  void _enterDirectory(RawEntry entry) {
    final newPath = p.join(_currentPath, entry.name);
    setState(() {
      _pathStack.add(PathSegment(entry.name, newPath));
      _searchQuery = '';
      _searchActive = false;
    });
    _load(newPath);
  }

  void _jumpTo(int index) {
    if (index == _pathStack.length - 1) return;
    setState(() {
      _pathStack.removeRange(index + 1, _pathStack.length);
      _searchQuery = '';
      _searchActive = false;
    });
    _load(_currentPath);
  }

  Future<bool> _handleBack() async {
    if (_selectionState.isSelectionMode) {
      _selectionNotifier.exitSelectionMode();
      return false;
    }
    if (_searchActive) {
      setState(() {
        _searchActive = false;
        _searchQuery = '';
      });
      return false;
    }
    if (_pathStack.length > 1) {
      _jumpTo(_pathStack.length - 2);
      return false;
    }
    return true;
  }

  void _openFile(RawEntry entry) {
    final path = p.join(_currentPath, entry.name);
    if (MediaViewerConstants.isImage(entry.name)) {
      final images = _visibleEntries.where((e) => !e.isDir && MediaViewerConstants.isImage(e.name)).toList();
      final paths = images.map((e) => p.join(_currentPath, e.name)).toList();
      final index = images.indexOf(entry);
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => LocalImageViewerScreen(imagePaths: paths, initialIndex: index < 0 ? 0 : index),
      ));
      return;
    }
    if (_inAppTextExtensions.contains(p.extension(entry.name).toLowerCase())) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => LocalTextViewerScreen(filePath: path),
      ));
      return;
    }
    if (p.extension(entry.name).toLowerCase() == '.zip') {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => DecoyArchiveBrowseScreen(
          archiveFile: File(path),
          archiveName: entry.name,
        ),
      ));
      return;
    }
    _openWithSystemApp(path);
  }

  Future<void> _openWithSystemApp(String path) async {
    final ok = await _api.openLocalFileWithApp(path);
    if (!ok && mounted) {
      showAppSnackBar(context, message: context.l10n.filesOpenFailed, tone: AppBannerTone.error);
    }
  }

  Future<void> _shareSelected() async {
    final paths = _selectionState.items.map((e) => p.join(_currentPath, e.name)).toList();
    final ok = await _api.shareLocalFiles(paths);
    if (!ok && mounted) {
      showAppSnackBar(context, message: context.l10n.filesShareFailed, tone: AppBannerTone.error);
    }
  }

  Future<void> _renameSelected() async {
    final selectedItems = _selectionState.items;
    if (selectedItems.length != 1) return;
    final entry = selectedItems.first;
    // Same rename dialog the vault file manager uses -- live name
    // validation, conflict checking, illegal-character filtering -- via
    // the local storage sentinel container. Advanced (batch/pattern)
    // rename is hidden for it; see browser_dialogs.dart.
    await BrowserDialogs.showRename(
      context,
      container: _localContainer,
      oldEntries: [entry],
      existingEntries: _allEntries,
      currentDirPath: _currentPath,
      onSuccess: () {
        _selectionNotifier.exitSelectionMode();
        _refresh();
      },
    );
  }

  Future<void> _deleteSelected() async {
    final items = _selectionState.items.toList();
    if (items.isEmpty) return;
    HapticFeedback.heavyImpact();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final cs = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          title: Text(dialogContext.l10n.filesDeleteConfirmTitle),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(MaterialLocalizations.of(dialogContext).cancelButtonLabel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: cs.error,
                foregroundColor: cs.onError,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(dialogContext.l10n.filesDelete),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    // Same FileOperationService progress tracking (app bar transfer button,
    // cancellation) the vault's own batch-delete uses -- see
    // FileBrowserScreen._batchDelete. Deliberately keeps its own
    // confirmation dialog above rather than BrowserDialogs.showBatchDelete:
    // that dialog's warning text explicitly says "your encrypted volume",
    // which has no business appearing in the decoy.
    final clipItems = items.map((entry) {
      return ClipboardItem(
        path: p.join(_currentPath, entry.name),
        isDir: entry.isDir,
        sizeBytes: entry.isDir ? 0 : entry.sizeBytes,
        modifiedSecs: entry.modifiedSecs,
      );
    }).toList();
    final op = _opSvc.enqueueDelete(
      container: _localContainer,
      items: clipItems,
      locationLabel: _currentPath,
      l10n: context.l10n,
    );
    _selectionNotifier.exitSelectionMode();
    void listener() {
      if (!mounted) {
        op.removeListener(listener);
        return;
      }
      final done =
          op.status != FileOperationStatus.running && op.status != FileOperationStatus.pending;
      if (!done) return;
      op.removeListener(listener);
      _refresh().then((_) {
        showAppSnackBar(
          context,
          message: op.failCount > 0 ? context.l10n.filesDeleteFailed : context.l10n.filesDeleted,
          tone: op.failCount > 0 ? AppBannerTone.error : AppBannerTone.success,
        );
        _opSvc.dismiss(op.id);
      });
    }

    op.addListener(listener);
  }

  // ── Clipboard cut/copy/paste ─────────────────────────────────────────────
  //
  // Same CrossContainerClipboard singleton, ClipboardItem model, conflict
  // detection/resolution UI, and FileOperationService progress tracking the
  // vault file manager uses (see FileBrowserScreen._initClipboard/_paste) --
  // only the actual transfer, in FileOperationService.enqueueLocalTransfer,
  // is local-storage-specific, since there's no container on either end.
  // This replaces the earlier "push a destination-picker screen, copy
  // immediately" flow with the same stage-then-paste-anywhere interaction
  // the vault uses: Copy/Move just stages the clipboard, and paste happens
  // via the app bar's clipboard chip once you've navigated to where you
  // want the items to land.

  MountedContainer get _localContainer => buildLocalStorageContainer(
        rootPath: _rootPath ?? '',
        displayName: context.l10n.filesTabLabel,
      );

  // Imperative check for _paste()'s early return -- ref.read, not watch,
  // since this runs from a button-press callback, not build(). The
  // reactive equivalent used to decide whether the app bar's paste action
  // is enabled lives in build()/​_buildNormalAppBar via the watched
  // `clipboard` param instead (see build()).
  bool get _canPaste {
    final clip = ref.read(crossContainerClipboardProvider);
    return clip.hasItems && clip.isFromVolume(kDecoyLocalVolId);
  }

  void _stageClipboard({required bool cut}) {
    final items = _selectionState.items.map((entry) {
      return ClipboardItem(
        path: p.join(_currentPath, entry.name),
        isDir: entry.isDir,
        sizeBytes: entry.isDir ? 0 : entry.sizeBytes,
        modifiedSecs: entry.modifiedSecs,
      );
    }).toList();
    if (items.isEmpty) return;
    ref.read(crossContainerClipboardProvider.notifier).set(
      volId: kDecoyLocalVolId,
      displayName: context.l10n.filesTabLabel,
      cut: cut,
      clipItems: items,
    );
    _selectionNotifier.exitSelectionMode();
  }

  Future<void> _paste() async {
    if (!_canPaste) return;
    final clip = ref.read(crossContainerClipboardProvider);
    final items = List<ClipboardItem>.from(clip.items);
    final isCut = clip.isCutOperation;
    final existing = await _repo.listDirectory(_currentPath);
    if (!mounted) return;
    final existingNamesLower = existing.map((e) => e.name.toLowerCase()).toSet();
    final existingDirsLower =
        existing.where((e) => e.isDir).map((e) => e.name.toLowerCase()).toSet();
    final conflicts = detectPasteConflicts(
      items: items,
      existingNamesLower: existingNamesLower,
      existingDirsLower: existingDirsLower,
      isCrossContainer: false,
      currentDirPath: _currentPath,
    );
    ConflictPlan conflictPlan = const {};
    if (conflicts.isNotEmpty) {
      final result = await ConflictResolutionSheet.show(context, conflicts: conflicts);
      if (!mounted) return;
      if (result == null) return;
      conflictPlan = result;
    }
    final container = _localContainer;
    final destDirPath = _currentPath;
    final op = _opSvc.enqueueLocalTransfer(
      isCut: isCut,
      source: container,
      dest: container,
      destDirPath: destDirPath,
      items: items,
      conflictPlan: conflictPlan,
      l10n: context.l10n,
    );
    ref.read(crossContainerClipboardProvider.notifier).clear();
    void listener() {
      if (!mounted) {
        op.removeListener(listener);
        return;
      }
      final done =
          op.status != FileOperationStatus.running && op.status != FileOperationStatus.pending;
      if (done) {
        op.removeListener(listener);
        if (destDirPath == _currentPath) {
          _refresh().then((_) => _opSvc.dismiss(op.id));
        } else {
          _opSvc.dismiss(op.id);
        }
      }
    }

    op.addListener(listener);
  }

  Future<void> _createFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final cs = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          title: Text(dialogContext.l10n.filesNewFolderDialogTitle),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              hintText: dialogContext.l10n.filesNameHint,
              filled: true,
              fillColor: cs.surfaceContainerLow,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: cs.outlineVariant),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(MaterialLocalizations.of(dialogContext).cancelButtonLabel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
              child: Text(dialogContext.l10n.filesCreate),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (!mounted || name == null || name.isEmpty) return;
    try {
      await _repo.createFolder(_currentPath, name);
      await _refresh();
      if (mounted) showAppSnackBar(context, message: context.l10n.filesFolderCreated, tone: AppBannerTone.success);
    } catch (_) {
      if (mounted) showAppSnackBar(context, message: context.l10n.filesCreateFolderFailed, tone: AppBannerTone.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selection = ref.watch(fileBrowserSelectionProvider(kDecoyLocalVolId));
    final sort = ref.watch(fileBrowserSortProvider(kDecoyLocalVolId));
    final clipboard = ref.watch(crossContainerClipboardProvider);
    final isSelectionMode = selection.isSelectionMode;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final canPop = await _handleBack();
        if (canPop && mounted) Navigator.of(context).maybePop();
      },
      child: Scaffold(
        appBar: isSelectionMode
            ? _buildSelectionAppBar(context, selection)
            : _buildNormalAppBar(context, sort, clipboard),
        body: _buildBody(context, selection),
        bottomNavigationBar: isSelectionMode
            ? _buildSelectionActionBar(context, selection)
            : null,
      ),
    );
  }

  PreferredSizeWidget _buildNormalAppBar(
    BuildContext context,
    FileBrowserSortState sort,
    ClipboardState clipboard,
  ) {
    return AppBar(
      title: HiddenVaultTrigger(child: Text(context.l10n.filesTabLabel)),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(41),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BreadcrumbBar(stack: _pathStack, onTap: _jumpTo),
            const Divider(height: 1),
          ],
        ),
      ),
      actions: [
        const AppBarTransferButton(),
        AppBarClipboardButton(
          onPaste: (clipboard.hasItems && clipboard.isFromVolume(kDecoyLocalVolId)) ? _paste : null,
        ),
        if (!_searchActive)
          IconButton(
            icon: const Icon(Icons.search_rounded),
            tooltip: context.l10n.searchInThisFolderHint,
            onPressed: () => setState(() => _searchActive = true),
          ),
        LocalTypeFilterButton(value: _typeFilter, onChanged: (v) => setState(() => _typeFilter = v)),
        SortMenuButton(
          sortBy: sort.sortBy,
          sortAscending: sort.sortAscending,
          onSortChanged: _sortNotifier.setSort,
        ),
        LayoutModeMenuButton(layoutMode: _layoutMode, onLayoutModeChanged: (v) => setState(() => _layoutMode = v)),
        IconButton(
          icon: const Icon(Icons.create_new_folder_rounded),
          tooltip: context.l10n.filesNewFolderTooltip,
          onPressed: _createFolder,
        ),
      ],
    );
  }

  PreferredSizeWidget _buildSelectionAppBar(
    BuildContext context,
    FileBrowserSelectionState selection,
  ) {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close_rounded),
        tooltip: context.l10n.filesCloseSelectionTooltip,
        onPressed: _selectionNotifier.exitSelectionMode,
      ),
      title: Text(selection.selectionSummary(context.l10n)),
      actions: [
        IconButton(
          icon: const Icon(Icons.select_all_rounded),
          tooltip: context.l10n.filesSelectAllTooltip,
          onPressed: () {
            HapticFeedback.selectionClick();
            _selectionNotifier.setSelectedItems(_visibleEntries.toSet());
          },
        ),
      ],
    );
  }

  Widget _buildSelectionActionBar(
    BuildContext context,
    FileBrowserSelectionState selection,
  ) {
    final cs = Theme.of(context).colorScheme;
    final singleSelected = selection.items.length == 1;

    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainer,
          border: Border(
            top: BorderSide(
              color: cs.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
        ),
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _actionButton(
              context,
              icon: Icons.share_rounded,
              label: context.l10n.filesShare,
              onTap: _shareSelected,
            ),
            if (singleSelected)
              _actionButton(
                context,
                icon: Icons.drive_file_rename_outline_rounded,
                label: context.l10n.filesRename,
                onTap: _renameSelected,
              ),
            _actionButton(
              context,
              icon: Icons.content_copy_rounded,
              label: context.l10n.filesCopy,
              onTap: () => _stageClipboard(cut: false),
            ),
            _actionButton(
              context,
              icon: Icons.drive_file_move_rounded,
              label: context.l10n.filesMove,
              onTap: () => _stageClipboard(cut: true),
            ),
            _actionButton(
              context,
              icon: Icons.delete_outline_rounded,
              label: context.l10n.filesDelete,
              onTap: _deleteSelected,
              isDestructive: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final itemColor = isDestructive ? cs.error : cs.onSurfaceVariant;

    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: itemColor),
            const SizedBox(height: 4),
            Text(
              label,
              style: textTheme.labelSmall?.copyWith(
                color: itemColor,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, FileBrowserSelectionState selection) {
    if (_checkingAccess) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_hasAccess) {
      return AppEmptyState(
        icon: Icons.folder_off_outlined,
        title: context.l10n.archiveExplorerPermissionTitle,
        message: context.l10n.filesPermissionMessage,
        actionLabel: context.l10n.archiveExplorerGrantAccess,
        actionIcon: Icons.lock_open_rounded,
        onAction: _requestAccess,
      );
    }
    return Stack(
      children: [
        Positioned.fill(child: _buildListArea(context, selection)),
        Positioned(
          left: 0,
          right: 0,
          bottom: _searchActive ? 0 : 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_statusMessage != null)
                Padding(
                  padding: EdgeInsets.only(
                    bottom: _searchActive ? 16 : 8,
                    left: 16,
                    right: 16,
                  ),
                  child: AnimatedSwitcher(
                    duration: AppMotion.short2,
                    child: InlineBanner(
                      _statusMessage!,
                      key: ValueKey(_statusMessage),
                      tone: _statusIsError
                          ? AppBannerTone.error
                          : AppBannerTone.info,
                    ),
                  ),
                ),
              if (_searchActive)
                BottomSearchBar(
                  initialQuery: _searchQuery,
                  onChanged: (q) => setState(() => _searchQuery = q),
                  onClose: () => setState(() {
                    _searchActive = false;
                    _searchQuery = '';
                  }),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildListArea(
    BuildContext context,
    FileBrowserSelectionState selection,
  ) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final items = _visibleEntries;
    if (items.isEmpty) {
      return AppEmptyState(
        icon: Icons.folder_open_outlined,
        title: context.l10n.filesEmptyTitle,
        message: context.l10n.filesEmptyMessage,
      );
    }
    final isGrid = _layoutMode == BrowserLayoutMode.grid || _layoutMode == BrowserLayoutMode.masonry;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: isGrid
          ? LocalMediaGridView(
              currentDirPath: _currentPath,
              items: items,
              isSelectionMode: selection.isSelectionMode,
              selectedItems: selection.items,
              masonry: _layoutMode == BrowserLayoutMode.masonry,
              onDirTap: _enterDirectory,
              onFileTap: _openFile,
              onItemLongPress: (e) {
                HapticFeedback.selectionClick();
                _selectionNotifier.toggleSelectItem(e);
              },
              onSelectionChanged: _selectionNotifier.setSelectedItems,
              searchQuery: _searchQuery.isEmpty ? null : _searchQuery,
            )
          : FileListView(
              items: items,
              isSelectionMode: selection.isSelectionMode,
              selectedItems: selection.items,
              isCompact: _layoutMode == BrowserLayoutMode.compact,
              onDirTap: _enterDirectory,
              onFileTap: _openFile,
              onItemLongPress: (e) {
                HapticFeedback.selectionClick();
                _selectionNotifier.toggleSelectItem(e);
              },
              onSelectionChanged: _selectionNotifier.setSelectedItems,
              searchQuery: _searchQuery.isEmpty ? null : _searchQuery,
              currentDirPath: _currentPath,
            ),
    );
  }
}