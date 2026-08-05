import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/services/playback_throttle_controller.dart';
import 'package:vaultexplorer/data/models/clipboard_item.dart';
import 'package:vaultexplorer/data/models/file_manager_action.dart';
import 'package:vaultexplorer/data/models/file_manager_toolbar_config.dart';
import 'package:vaultexplorer/data/models/file_operation.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/data/models/vault_item.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/services/cross_container_clipboard.dart';
import 'package:vaultexplorer/data/services/file_manager_toolbar_service.dart';
import 'package:vaultexplorer/data/services/vault_items_service.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/data/models/archive_context.dart';
import 'package:vaultexplorer/data/services/archive_service.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/core/widgets/activity/floating_activity_stack.dart';
import 'package:vaultexplorer/features/browser/archive_file_viewer.dart';
import 'package:vaultexplorer/features/browser/browser_dialogs.dart';
import 'package:vaultexplorer/features/browser/viewer/html_viewer_screen.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_screen.dart';
import 'package:vaultexplorer/features/browser/viewer/text_editor_screen.dart';
import 'package:vaultexplorer/features/browser/viewer/pdf_viewer_screen.dart';
import 'package:vaultexplorer/features/browser/mixins/selection_mixin.dart';
import 'package:vaultexplorer/features/browser/mixins/sort_mixin.dart';
import 'package:vaultexplorer/features/browser/widgets/bottom_search_bar.dart';
import 'package:vaultexplorer/features/browser/widgets/breadcrumb_bar.dart';
import 'package:vaultexplorer/features/browser/widgets/conflict_resolution_sheet.dart';
import 'package:vaultexplorer/features/browser/widgets/file_manager_action_bar.dart';
import 'package:vaultexplorer/features/browser/widgets/add_item_menu_button.dart';
import 'package:vaultexplorer/features/browser/widgets/sort_menu_button.dart';
import 'package:vaultexplorer/features/browser/widgets/layout_mode_menu_button.dart';
import 'package:vaultexplorer/features/browser/widgets/browser_app_bar_builder.dart';
import 'package:vaultexplorer/features/browser/widgets/browser_body_builder.dart';
import 'package:vaultexplorer/features/browser/widgets/folder_document_provider_sheet.dart';
import 'package:vaultexplorer/features/camera/camera_capture_screen.dart';
import 'package:vaultexplorer/features/vault_item/vault_item_detail_screen.dart';
import 'package:vaultexplorer/features/vault_item/vault_item_edit_screen.dart';
import 'package:vaultexplorer/data/models/browser_layout_mode.dart';

import '../../core/widgets/thumbnail/thumbnail_concurrency.dart';

class PathSegment {
  final String label;
  final String fatPath;
  final bool isArchiveRoot;
  const PathSegment(this.label, this.fatPath, {this.isArchiveRoot = false});
}

class FileBrowserScreen extends StatefulWidget {
  final MountedContainer container;
  final MountedContainer? Function(int volId)? resolveContainer;
  final ThumbnailCacheMode? thumbnailCacheMode;
  final ThumbnailQuality? thumbnailQuality;
  final VoidCallback? onUserActivity;
  const FileBrowserScreen({
    super.key,
    required this.container,
    this.thumbnailCacheMode,
    this.thumbnailQuality,
    this.onUserActivity,
    this.resolveContainer,
  });
  @override
  State<FileBrowserScreen> createState() => _FileBrowserScreenState();
}

class _FileBrowserScreenState extends State<FileBrowserScreen>
    with SelectionMixin<FileBrowserScreen>, SortMixin<FileBrowserScreen> {
  final List<PathSegment> _pathStack = [const PathSegment('Root', '')];
  List<RawEntry> _currentItems = [];
  bool _isLoading = false;
  int _freeSpace = 0;
  bool _isListingTruncated = false;
  String? _statusMessage;
  bool _statusIsError = false;
  CrossContainerClipboard get _clip => CrossContainerClipboard.instance;
  FileOperationService get _opSvc => FileOperationService.instance;
  bool _searchActive = false;
  String _searchQuery = '';
  BrowserLayoutMode _layoutMode = BrowserLayoutMode.list;
  String? _currentFilter;
  bool _menuIsOpen = false;
  ArchiveContext? _archiveContext;
  ThumbnailCacheMode _resolvedThumbnailCacheMode = ThumbnailCacheMode.appCache;
  ThumbnailQuality _resolvedThumbnailQuality = ThumbnailQuality.defaultQuality;
  FileManagerToolbarConfig _toolbarConfig = FileManagerToolbarConfig.defaults();
  Set<String> _pinnedPaths = {};
  bool _isContainerLocked = false;

  static const int _maxScanDepth = 20;
  static const _documentExts = {
    'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'rtf',
    'csv', 'zip', 'tar', 'gz', 'json', 'xml',
  };

  bool get _atRoot => _pathStack.length == 1;
  String get _currentDirPath => _pathStack.last.fatPath;
  Set<String> _mountedDocProviderFolders = {};
  String _fullPathOf(RawEntry entry) =>
      _currentDirPath.isEmpty ? entry.name : '$_currentDirPath/${entry.name}';
  bool _isFolderMounted(RawEntry entry) =>
      entry.isDir && _mountedDocProviderFolders.contains(_fullPathOf(entry));
  bool _isPinned(RawEntry entry) => _pinnedPaths.contains(_fullPathOf(entry));

  void _onContainerLockedEvent(int volId) {
    if (volId == widget.container.volId && mounted) {
      setState(() => _isContainerLocked = true);
    }
  }

  @override
  void initState() {
    super.initState();
    VaultExplorerApi.addContainerLockedListener(_onContainerLockedEvent);
    _freeSpace = widget.container.freeSpace;
    _initSettingsAndContents();
    _loadToolbarConfig();
    _refreshMountedDocProviderFolders();
    VaultExplorerApi.addUsbContainerDetachedListener(_onContainerDetached);
  }

  @override
  void dispose() {
    VaultExplorerApi.removeContainerLockedListener(_onContainerLockedEvent);
    _closeArchive();
    VaultExplorerApi.removeUsbContainerDetachedListener(_onContainerDetached);
    super.dispose();
  }

  Future<void> _refreshMountedDocProviderFolders() async {
    final paths =
        await vaultExplorerApi.getMountedContainerFolders(widget.container.uri);
    if (!mounted) return;
    setState(() => _mountedDocProviderFolders = paths.toSet());
  }

  Future<void> _toggleFolderDocumentProvider(RawEntry entry) async {
    final path = _fullPathOf(entry);
    final ok = await vaultExplorerApi.mountContainerFolder(
      widget.container.uri,
      path,
      displayName: entry.name,
    );
    if (!mounted) return;
    if (!ok) {
      showAppSnackBar(context, message: context.l10n.couldNotExpose(entry.name));
      return;
    }
    setState(() => _mountedDocProviderFolders = {..._mountedDocProviderFolders, path});
    await ContainerRepository.instance
        .setFolderExposed(widget.container.uri, path, exposed: true);
    if (!mounted) return;
    showAppSnackBar(
      context,
      message: context.l10n.nowAvailableToOtherApps(entry.name),
    );
  }

  Future<void> _unmountFolderDocumentProvider(RawEntry entry) async {
    final path = _fullPathOf(entry);
    final ok = await vaultExplorerApi.unmountContainerFolder(widget.container.uri, path);
    if (!mounted) return;
    if (!ok) {
      showAppSnackBar(context, message: context.l10n.couldNotUnmount(entry.name));
      return;
    }
    setState(() {
      _mountedDocProviderFolders = {..._mountedDocProviderFolders}..remove(path);
    });
    await ContainerRepository.instance
        .setFolderExposed(widget.container.uri, path, exposed: false);
  }

  Future<void> _setFolderAutoMount(RawEntry entry, bool autoMount) async {
    final path = _fullPathOf(entry);
    await ContainerRepository.instance
        .setFolderAutoMount(widget.container.uri, path, autoMount);
  }

  Future<void> _showFolderDocumentProviderSheet(RawEntry entry) async {
    final path = _fullPathOf(entry);
    final records = await ContainerRepository.instance.loadAll();
    final record = records[widget.container.uri];
    final matches = record?.documentProviderFolders.where((f) => f.path == path) ?? const [];
    final existing = matches.isEmpty ? null : matches.first;
    if (!mounted) return;
    final action = await FolderDocumentProviderSheet.show(
      context,
      folderName: entry.name,
      initialAutoMount: existing?.autoMount ?? false,
      onAutoMountChanged: (value) => _setFolderAutoMount(entry, value),
    );
    if (action == FolderDocumentProviderAction.unmount) {
      await _unmountFolderDocumentProvider(entry);
    }
  }

  Future<void> _togglePinSelected({required bool pin}) async {
    _signalActivity();
    final pathsToToggle = selectedItems.map((e) => _fullPathOf(e)).toList();
    setState(() {
      if (pin) {
        _pinnedPaths.addAll(pathsToToggle);
      } else {
        _pinnedPaths.removeAll(pathsToToggle);
      }
    });
    final records = await ContainerRepository.instance.loadAll();
    var record = records[widget.container.uri];
    record ??= ContainerRecord(
      uri: widget.container.uri,
      label: widget.container.displayName,
      containerFormat: widget.container.containerFormat,
    );
    record = record.copyWith(pinnedPaths: _pinnedPaths.toList());
    await ContainerRepository.instance.save(record);
    final count = pathsToToggle.length;
    _setStatus(
      pin
          ? context.l10n.pinnedCount(count)
          : context.l10n.unpinnedCount(count),
    );
    exitSelectionMode();
  }

  bool get _isReadOnly => widget.container.readOnly;

  void _signalActivity() => widget.onUserActivity?.call();

  void _onContainerDetached(int volId) {
    if (!mounted || volId != widget.container.volId) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _initSettingsAndContents() async {
    setState(() => _isLoading = true);
    try {
      final appSettings = await AppSettingsService.loadSettings();
      final records = await ContainerRepository.instance.loadAll();
      final record = records[widget.container.uri];
      if (mounted) {
        setState(() {
          if (record != null) {
            _pinnedPaths = Set<String>.from(record.pinnedPaths);
          }
          _resolvedThumbnailCacheMode =
              widget.thumbnailCacheMode ??
              record?.thumbnailCacheMode ??
              appSettings.defaultThumbnailCacheMode;
          _resolvedThumbnailQuality =
              widget.thumbnailQuality ??
              record?.thumbnailQuality ??
              appSettings.defaultThumbnailQuality;
          _layoutMode = appSettings.defaultLayoutMode;
          sortBy = appSettings.defaultFileSortBy;
          sortAscending = appSettings.defaultFileSortAscending;
        });
      }
      if (mounted &&
          widget.container.readOnly &&
          _resolvedThumbnailCacheMode == ThumbnailCacheMode.inContainer) {
        showAppSnackBar(
          context,
          message: context.l10n.readOnlyThumbnailWarning,
          tone: AppBannerTone.warning,
        );
      }
    } catch (e) {
      debugPrint('Failed to resolve settings: $e');
    }
    await _loadDirectoryContents(_currentDirPath);
  }

  Future<void> _loadToolbarConfig() async {
    final config = await FileManagerToolbarService.instance.load();
    if (!mounted) return;
    setState(() => _toolbarConfig = config);
  }

  void _setStatus(String msg, {bool error = false, Duration? autoClear}) {
    if (!mounted) return;
    setState(() {
      _statusMessage = msg;
      _statusIsError = error;
    });
    final delay =
        autoClear ??
        (error ? const Duration(seconds: 5) : const Duration(seconds: 3));
    Future.delayed(delay, () {
      if (mounted && _statusMessage == msg) {
        setState(() => _statusMessage = null);
      }
    });
  }

  void _clearStatus() {
    if (mounted) setState(() => _statusMessage = null);
  }

  Future<void> _loadDirectoryContents(String path) async {
    setState(() => _isLoading = true);
    _signalActivity();
    if (_archiveContext != null) {
      _loadArchiveContents(path);
      return;
    }
    try {
      final items = await vaultExplorerApi.listDirectory(widget.container, path);
      List<int>? space;
      try {
        space = await vaultExplorerApi.getSpaceInfo(widget.container);
      } catch (_) {
        space = null;
      }
      if (mounted) {
        final isTruncated = items?.any((f) => f == 'System:TRUNCATED') ?? false;
        setState(() {
          _currentItems = items
                  ?.where((f) => !f.startsWith('System:'))
                  .map(RawEntry.parse)
                  .toList() ??
              [];
          _isListingTruncated = isTruncated;
          if (space != null && space.length > 1 && space[1] >= 0) _freeSpace = space[1];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _setStatus(context.l10n.failedLoadingFolder('${e.runtimeType}'), error: true);
      }
    }
  }

  void _loadArchiveContents(String path) {
    if (_archiveContext == null) return;
    final archiveRootPath = _pathStack[_archiveContext!.pathStackEntryIndex].fatPath;
    String subPath = '';
    if (path.length > archiveRootPath.length) {
      subPath = path.substring(archiveRootPath.length);
      if (subPath.startsWith('/')) subPath = subPath.substring(1);
    }
    final items = _archiveContext!.listDirectory(subPath);
    if (mounted) {
      setState(() {
        _currentItems = items.map(RawEntry.parse).toList();
        _isListingTruncated = false;
        _isLoading = false;
      });
    }
  }

  Future<void> _openArchive(String fullPath, String archiveName) async {
    setState(() => _isLoading = true);
    _signalActivity();
    try {
      final ctx = await ArchiveService.open(
        container: widget.container,
        archivePathInContainer: fullPath,
        pathStackEntryIndex: _pathStack.length,
      );
      setState(() {
        _archiveContext = ctx;
        _pathStack.add(PathSegment(archiveName, fullPath, isArchiveRoot: true));
        _clearSearch();
        _currentFilter = null;
      });
      _loadArchiveContents(fullPath);
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _setStatus(context.l10n.failedToReadArchive('${e.runtimeType}'), error: true);
      }
    }
  }

  void _closeArchive() {
    _archiveContext?.dispose();
    _archiveContext = null;
  }

  void _clearSearch() {
    _searchActive = false;
    _searchQuery = '';
  }

  void _enterDirectory(RawEntry entry) {
    final newPath = _currentDirPath.isEmpty
        ? entry.name
        : '$_currentDirPath/${entry.name}';
    setState(() {
      _pathStack.add(PathSegment(entry.name, newPath));
      _clearSearch();
      _currentFilter = null;
    });
    _loadDirectoryContents(newPath);
  }

  void _navigateUp() {
    if (_atRoot) return;
    if (_archiveContext != null &&
        _pathStack.length - 1 <= _archiveContext!.pathStackEntryIndex) {
      _closeArchive();
    }
    setState(() {
      _pathStack.removeLast();
      _clearSearch();
      _currentFilter = null;
    });
    _loadDirectoryContents(_currentDirPath);
  }

  void _jumpTo(int index) {
    if (index == _pathStack.length - 1) return;
    if (_archiveContext != null && index < _archiveContext!.pathStackEntryIndex) {
      _closeArchive();
    }
    setState(() {
      _pathStack.removeRange(index + 1, _pathStack.length);
      _clearSearch();
      _currentFilter = null;
    });
    _loadDirectoryContents(_currentDirPath);
  }

  @override
  void toggleSelectItem(RawEntry item) {
    super.toggleSelectItem(item);
    if (selectedFolderCount > 0) {
      fetchFolderSizes(widget.container, _currentDirPath);
    }
  }

  void _handleDirTap(RawEntry entry) {
    _signalActivity();
    if (isSelectionMode) {
      toggleSelectItem(entry);
    } else {
      _enterDirectory(entry);
    }
  }

  Future<void> _handleFileTap(RawEntry entry) async {
    ThumbnailConcurrency.videoLimiter.cancelAll();
    if (MediaViewerConstants.isVideo(entry.name)) {
      await PlaybackThrottleController.setActive(true);
    }
    _signalActivity();
    if (isSelectionMode) {
      toggleSelectItem(entry);
      return;
    }

    final fullPath = _currentDirPath.isEmpty
        ? entry.name
        : '$_currentDirPath/${entry.name}';
    final parts = entry.name.split('.');
    final ext = parts.length > 1 ? parts.last.toLowerCase() : '';
    if (ArchiveService.isArchive(ext)) {
      if (ArchiveService.isSupported(ext)) {
        await _openArchive(fullPath, entry.name);
      } else {
        _setStatus(context.l10n.archiveFormatNotSupported(ext), error: true);
      }
      return;
    }
    if (_archiveContext != null) {
      _signalActivity();
      setState(() => _isLoading = true);
      try {
        final archiveRootPath = _pathStack[_archiveContext!.pathStackEntryIndex].fatPath;
        String subPath = '';
        if (fullPath.length > archiveRootPath.length) {
          subPath = fullPath.substring(archiveRootPath.length);
          if (subPath.startsWith('/')) subPath = subPath.substring(1);
        }
        final tempFilePath = await _archiveContext!.extractEntry(subPath);
        if (mounted) {
          setState(() => _isLoading = false);
          if (tempFilePath != null) {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ArchiveFileViewer(
                  file: File(tempFilePath),
                  fileName: entry.name,
                ),
              ),
            );
          } else {
            _setStatus(context.l10n.failedToReadFileFromArchive, error: true);
          }
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isLoading = false);
          _setStatus(context.l10n.failedToExtractFile('${e.runtimeType}'), error: true);
        }
      }
      return;
    }
    if (VaultItemType.values.any((t) => t.name.toLowerCase() == ext)) {
      final item = await VaultItemsService.instance.loadItem(widget.container, fullPath);
      if (item != null) {
        final baseName = entry.name.substring(0, entry.name.lastIndexOf('.'));
        item.title = baseName;
        if (mounted) {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => VaultItemDetailScreen(
                container: widget.container,
                item: item,
                filePath: fullPath,
              ),
            ),
          );
          _loadDirectoryContents(_currentDirPath);
        }
      } else {
        _setStatus(context.l10n.failedToReadSecureItem, error: true);
      }
      return;
    }
    final settings = await AppSettingsService.loadSettings();
    final pref = settings.extensionPreferences[ext];
    if (pref == 'editor') {
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              TextEditorScreen(container: widget.container, filePath: fullPath),
        ),
      );
      _loadDirectoryContents(_currentDirPath);
    } else if (pref == 'media') {
      _openMediaViewer(entry.name, fullPath);
    } else if (pref == 'pdf') {
      await _openPdfViewer(fullPath);
    } else if (pref == 'html') {
      _openHtmlViewer(fullPath);
    } else if (pref != null && pref.startsWith('package:')) {
      _openFileWithApp(entry.name, fullPath, packageName: pref.substring(8));
    } else if (pref == 'external') {
      _openFileWithApp(entry.name, fullPath);
    } else {
      if (_isSupportedMedia(entry.name)) {
        _openMediaViewer(entry.name, fullPath);
      } else if (ext == 'pdf') {
        await _openPdfViewer(fullPath);
      } else if (ext == 'html' || ext == 'htm') {
        _openHtmlViewer(fullPath);
      } else {
        if (!mounted) return;
        await _showOpenWithDialog(entry.name, fullPath, ext, settings);
      }
    }
  }

  Future<void> _openPdfViewer(String fullPath) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            PdfViewerScreen(container: widget.container, filePath: fullPath),
      ),
    );
    _loadDirectoryContents(_currentDirPath);
  }

  void _openHtmlViewer(String fullPath) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            HtmlViewerScreen(container: widget.container, filePath: fullPath),
      ),
    );
  }

  void _openMediaViewer(String fileName, String fullPath) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MediaViewerScreen(
          container: widget.container,
          mediaFiles: [fullPath],
          initialIndex: 0,
          startingFolder: _currentDirPath,
          thumbnailQuality: _resolvedThumbnailQuality,
          thumbnailCacheMode: _resolvedThumbnailCacheMode,
        ),
      ),
    );
  }

  Future<void> _showOpenWithDialog(
    String fileName,
    String fullPath,
    String ext,
    AppSettings settings,
  ) async {
    bool remember = false;
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isMedia = _isSupportedMedia(fileName);
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(context.l10n.openFileDialogTitle),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    context.l10n.chooseHowToOpen(fileName),
                    style: textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: () =>
                        Navigator.of(context).pop(isMedia ? 'media' : 'editor'),
                    borderRadius: BorderRadius.circular(12),
                    child: Ink(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerLow,
                        border: Border.all(color: cs.outlineVariant),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isMedia
                                ? Icons.play_circle_outline_rounded
                                : Icons.edit_note_rounded,
                            color: cs.primary,
                            size: 28,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isMedia
                                      ? context.l10n.fileAssocInAppMediaViewer
                                      : context.l10n.fileAssocInAppTextEditor,
                                  style: textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  isMedia
                                      ? context.l10n.playVideoAudioViewImageInApp
                                      : context.l10n.viewEditTextMarkdownCode,
                                  style: textTheme.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: cs.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () => Navigator.of(context).pop('external'),
                    borderRadius: BorderRadius.circular(12),
                    child: Ink(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerLow,
                        border: Border.all(color: cs.outlineVariant),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.open_in_new_rounded,
                            color: cs.secondary,
                            size: 28,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  context.l10n.fileAssocExternalApp,
                                  style: textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  context.l10n.sendFileToThirdPartyApp,
                                  style: textTheme.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: cs.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () => Navigator.of(context).pop('open_as'),
                    borderRadius: BorderRadius.circular(12),
                    child: Ink(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerLow,
                        border: Border.all(color: cs.outlineVariant),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.app_registration_rounded,
                            color: cs.secondary,
                            size: 28,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  context.l10n.openAsEllipsis,
                                  style: textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  context.l10n.chooseFileTypeToOpenAs,
                                  style: textTheme.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: cs.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Checkbox(
                        value: remember,
                        onChanged: (val) {
                          setDialogState(() {
                            remember = val ?? false;
                          });
                        },
                      ),
                      Expanded(
                        child: Text(
                          ext.isNotEmpty
                              ? context.l10n.alwaysRememberChoiceExt(ext)
                              : context.l10n.alwaysRememberChoiceNoExt,
                          style: textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(context.l10n.cancel),
                ),
              ],
            );
          },
        );
      },
    );
    if (result == 'editor') {
      if (remember) {
        settings.extensionPreferences[ext] = 'editor';
        await AppSettingsService.saveSettings(settings);
      }
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              TextEditorScreen(container: widget.container, filePath: fullPath),
        ),
      );
      _loadDirectoryContents(_currentDirPath);
    } else if (result == 'media') {
      if (remember) {
        settings.extensionPreferences[ext] = 'media';
        await AppSettingsService.saveSettings(settings);
      }
      _openMediaViewer(fileName, fullPath);
    } else if (result == 'external') {
      if (remember) {
        VaultExplorerApi.onAppSelectedCallback = (selectedExt, pkg) {
          if (selectedExt.toLowerCase() == ext.toLowerCase()) {
            settings.extensionPreferences[ext] = 'package:$pkg';
            AppSettingsService.saveSettings(settings);
            VaultExplorerApi.onAppSelectedCallback = null;
          }
        };
      }
      _openFileWithApp(fileName, fullPath);
    } else if (result == 'open_as') {
      if (!mounted) return;
      final mimeType = await showDialog<String>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text(context.l10n.openAsDialogTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.text_fields_rounded),
                  title: Text(context.l10n.mimeTypeText),
                  onTap: () => Navigator.of(context).pop('text/plain'),
                ),
                ListTile(
                  leading: const Icon(Icons.image_outlined),
                  title: Text(context.l10n.mimeTypeImage),
                  onTap: () => Navigator.of(context).pop('image/*'),
                ),
                ListTile(
                  leading: const Icon(Icons.ondemand_video_outlined),
                  title: Text(context.l10n.mimeTypeVideo),
                  onTap: () => Navigator.of(context).pop('video/*'),
                ),
                ListTile(
                  leading: const Icon(Icons.audio_file_outlined),
                  title: Text(context.l10n.mimeTypeAudio),
                  onTap: () => Navigator.of(context).pop('audio/*'),
                ),
                ListTile(
                  leading: const Icon(Icons.archive_outlined),
                  title: Text(context.l10n.mimeTypeArchive),
                  onTap: () => Navigator.of(context).pop('application/zip'),
                ),
                ListTile(
                  leading: const Icon(Icons.insert_drive_file_outlined),
                  title: Text(context.l10n.mimeTypeOther),
                  onTap: () => Navigator.of(context).pop('*/*'),
                ),
              ],
            ),
          );
        },
      );
      if (mimeType != null) {
        _openFileWithApp(
          fileName,
          fullPath,
          mimeType: mimeType,
        );
      }
    }
  }

  Future<void> _startMediaViewerFromCurrentLocation() async {
    _signalActivity();
    int compareOverall(RawEntry ea, RawEntry eb) {
      final aPinned = _isPinned(ea);
      final bPinned = _isPinned(eb);
      if (aPinned != bPinned) {
        return aPinned ? -1 : 1;
      }
      if (ea.isDir != eb.isDir) {
        return ea.isDir ? -1 : 1;
      }
      return compareItems(ea, eb);
    }
    final sortedItems = _currentItems.where((e) => !e.isDir).toList()
      ..sort(compareOverall);
    final localMedia = sortedItems
        .map((e) => e.name)
        .where(_isSupportedMedia)
        .toList();
    if (localMedia.isNotEmpty) {
      final resolvedPaths = localMedia
          .map((f) => _currentDirPath.isEmpty ? f : '$_currentDirPath/$f')
          .toList();
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MediaViewerScreen(
            container: widget.container,
            mediaFiles: resolvedPaths,
            initialIndex: 0,
            startingFolder: _currentDirPath,
            thumbnailQuality: _resolvedThumbnailQuality,
            thumbnailCacheMode: _resolvedThumbnailCacheMode,
          ),
        ),
      );
      return;
    }
    setState(() => _isLoading = true);
    _setStatus(
      context.l10n.scanningSubfoldersForMedia,
      autoClear: const Duration(seconds: 15),
    );
    try {
      final recursiveMedia = await _scanMediaRecursively(_currentDirPath);
      if (!mounted) return;
      if (recursiveMedia.isNotEmpty) {
        _clearStatus();
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MediaViewerScreen(
              container: widget.container,
              mediaFiles: recursiveMedia,
              initialIndex: 0,
              startingFolder: _currentDirPath,
              thumbnailQuality: _resolvedThumbnailQuality,
              thumbnailCacheMode: _resolvedThumbnailCacheMode,
            ),
          ),
        );
      } else {
        _setStatus(
          context.l10n.noMediaFilesFoundRecursive,
          error: true,
        );
      }
    } catch (e) {
      _setStatus(context.l10n.failedToScanSubfolders('$e'), error: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _handleItemLongPress(RawEntry entry) {
    HapticFeedback.selectionClick();
    _signalActivity();
    if (!isSelectionMode) {
      setState(() {
        isSelectionMode = true;
        selectedItems.add(entry);
      });
      if (selectedFolderCount > 0) {
        fetchFolderSizes(widget.container, _currentDirPath);
      }
    } else {
      toggleSelectItem(entry);
    }
  }

  bool _isSupportedMedia(String fileName) =>
      MediaViewerConstants.isSupported(fileName);

  Future<List<String>> _scanMediaRecursively(
    String dirPath, {
    int depth = 0,
  }) async {
    if (depth > _maxScanDepth) return [];
    final foundFiles = <String>[];
    final subdirNames = <String>[];
    try {
      final items = await vaultExplorerApi.listDirectory(
        widget.container,
        dirPath,
      );
      if (items != null) {
        for (final item in items) {
          if (item.startsWith('System:')) continue;
          final e = RawEntry.parse(item);
          if (e.isDir) {
            subdirNames.add(e.name);
          } else if (_isSupportedMedia(e.name)) {
            foundFiles.add(dirPath.isEmpty ? e.name : '$dirPath/${e.name}');
          }
        }
        if (subdirNames.isNotEmpty) {
          final nested = await Future.wait(
            subdirNames.map((name) {
              final subPath = dirPath.isEmpty ? name : '$dirPath/$name';
              return _scanMediaRecursively(subPath, depth: depth + 1);
            }),
          );
          for (final list in nested) {
            foundFiles.addAll(list);
          }
        }
      }
    } catch (e) {
      debugPrint('Error scanning subfolder for media: $e');
    }
    return foundFiles;
  }

  Future<void> _openFileWithApp(
    String cleanName,
    String fullPath, {
    String? packageName,
    String? mimeType,
  }) async {
    _signalActivity();
    try {
      final ok = await vaultExplorerApi.openWithApp(
        widget.container,
        fullPath,
        packageName: packageName,
        mimeType: mimeType,
      );
      if (!ok && mounted) {
        _setStatus(context.l10n.noAppFoundForFileType, error: true);
      }
    } catch (_) {
      if (mounted) _setStatus(context.l10n.couldNotOpenFile(cleanName), error: true);
    }
  }

  Future<void> _addVaultItem(VaultItemType type) async {
    if (_isReadOnly) {
      _setStatus(context.l10n.readOnlyContainerWarning, error: true);
      return;
    }
    _signalActivity();
    await Navigator.push<String?>(
      context,
      MaterialPageRoute(
        builder: (_) => VaultItemEditScreen(
          container: widget.container,
          type: type,
          currentDirPath: _currentDirPath,
        ),
      ),
    );
    _loadDirectoryContents(_currentDirPath);
  }

  void _initClipboard({required bool cut}) {
    if (cut && _isReadOnly) {
      _setStatus(
        context.l10n.readOnlyCantMove,
        error: true,
      );
      return;
    }
    _signalActivity();
    final clipItems = selectedItems.map((entry) {
      final path = _currentDirPath.isEmpty
          ? entry.name
          : '$_currentDirPath/${entry.name}';
      return ClipboardItem(
        path: path,
        isDir: entry.isDir,
        sizeBytes: entry.isDir ? 0 : entry.sizeBytes,
        modifiedSecs: entry.modifiedSecs,
      );
    }).toList();
    _clip.set(
      volId: widget.container.volId,
      displayName: widget.container.displayName,
      cut: cut,
      clipItems: clipItems,
    );
    exitSelectionMode();
  }

  Future<void> _paste() async {
    if (!_clip.hasItems) return;
    if (_isReadOnly) {
      _setStatus(
        context.l10n.readOnlyCantPaste,
        error: true,
      );
      return;
    }
    _signalActivity();
    final srcVolId = _clip.sourceVolId;
    if (srcVolId == null) {
      _setStatus(context.l10n.clipboardSourceInvalid, error: true);
      _clip.clear();
      return;
    }
    final isCrossContainer = !_clip.isFromVolume(widget.container.volId);
    MountedContainer? srcContainer;
    if (isCrossContainer) {
      if (widget.resolveContainer == null) {
        _setStatus(context.l10n.crossContainerPasteNotConfigured, error: true);
        return;
      }
      srcContainer = widget.resolveContainer!(srcVolId);
      if (srcContainer == null) {
        _setStatus(
          context.l10n.crossContainerPasteRequiresBothMounted,
          error: true,
          autoClear: const Duration(seconds: 6),
        );
        _clip.clear();
        return;
      }
    } else {
      srcContainer = widget.container;
    }
    final items = List<ClipboardItem>.from(_clip.items);
    final isCut = _clip.isCutOperation;
    final existingRaw =
        await vaultExplorerApi.listDirectory(
          widget.container,
          _currentDirPath,
        ) ??
        [];
    if (!mounted) return;
    final existingNames = <String>{};
    final existingDirs = <String>{};
    for (final raw in existingRaw) {
      if (raw.startsWith('System:')) continue;
      final e = RawEntry.parse(raw);
      existingNames.add(e.name.toLowerCase());
      if (e.isDir) existingDirs.add(e.name.toLowerCase());
    }
    final conflicts = <ConflictEntry>[];
    for (final item in items) {
      final fileName = item.name;
      if (!existingNames.contains(fileName.toLowerCase())) continue;
      final wouldBeSamePath =
          !isCrossContainer &&
          item.path ==
              (_currentDirPath.isEmpty
                  ? fileName
                  : '$_currentDirPath/$fileName');
      if (wouldBeSamePath) continue;
      conflicts.add(
        ConflictEntry(
          item: item,
          destIsDir: existingDirs.contains(fileName.toLowerCase()),
        ),
      );
    }
    ConflictPlan conflictPlan = const {};
    if (conflicts.isNotEmpty) {
      if (!mounted) return;
      final result = await ConflictResolutionSheet.show(
        context,
        conflicts: conflicts,
      );
      if (!mounted) return;
      if (result == null) return;
      conflictPlan = result;
    }
    final op = _opSvc.enqueue(
      isCut: isCut,
      source: srcContainer,
      dest: widget.container,
      destDirPath: _currentDirPath,
      items: items,
      conflictPlan: conflictPlan,
    );
    _clip.clear();
    void listener() {
      if (!mounted) {
        op.removeListener(listener);
        return;
      }
      final done =
          op.status != FileOperationStatus.running &&
          op.status != FileOperationStatus.pending;
      if (done) {
        op.removeListener(listener);
        if (op.destDirPath == _currentDirPath) {
          _loadDirectoryContents(_currentDirPath);
        }
      }
    }
    op.addListener(listener);
  }

  void _batchDelete() {
    if (_isReadOnly) {
      _setStatus(
        context.l10n.readOnlyCantDelete,
        error: true,
      );
      return;
    }
    HapticFeedback.heavyImpact();
    _signalActivity();
    BrowserDialogs.showBatchDelete(
      context,
      toDelete: List<RawEntry>.from(selectedItems),
      onConfirmed: (entries) async {
        setState(() => _isLoading = true);
        final clipItems = entries.map((e) {
          final path = _currentDirPath.isEmpty
              ? e.name
              : '$_currentDirPath/${e.name}';
          return ClipboardItem(path: path, isDir: e.isDir);
        }).toList();
        int failCount = 0;
        final deleted = await _opSvc.deleteItems(
          container: widget.container,
          items: clipItems,
          onProgress: (done, total) {},
        );
        failCount = clipItems.length - deleted;
        final deletedPaths = clipItems.map((i) => i.path).toSet();
        if (_pinnedPaths.any((p) => deletedPaths.contains(p))) {
          _pinnedPaths.removeWhere((p) => deletedPaths.contains(p));
          final records = await ContainerRepository.instance.loadAll();
          var record = records[widget.container.uri];
          if (record != null) {
            await ContainerRepository.instance.save(
              record.copyWith(pinnedPaths: _pinnedPaths.toList()),
            );
          }
        }
        exitSelectionMode();
        await _loadDirectoryContents(_currentDirPath);
        _setStatus(
          failCount == 0
              ? context.l10n.deletedCount(deleted)
              : context.l10n.deletedWithFailures(deleted, failCount),
          error: failCount > 0,
        );
      },
    );
  }

  Future<void> _exportSelectedToStorage() async {
    _signalActivity();
    final items = selectedItems.map((e) {
      final path = _currentDirPath.isEmpty
          ? e.name
          : '$_currentDirPath/${e.name}';
      return <String, dynamic>{'path': path, 'isDir': e.isDir};
    }).toList();
    if (items.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      final count = await vaultExplorerApi.exportSelectedToFolder(
        widget.container,
        items,
      );
      _setStatus(
        count > 0 ? context.l10n.exportedCount(count) : context.l10n.exportCancelledOrFailed,
        error: count == 0,
      );
    } catch (e) {
      _setStatus(context.l10n.exportError('${e.runtimeType}'), error: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
    exitSelectionMode();
  }

  Future<void> _importFilesFromDevice() async {
    if (_isReadOnly) {
      _setStatus(context.l10n.readOnlyContainerWarning, error: true);
      return;
    }
    _signalActivity();
    final op = _opSvc.enqueueImport(
      dest: widget.container,
      destDirPath: _currentDirPath,
      isFolder: false,
      performImport: (opId) => vaultExplorerApi.importFiles(
        widget.container,
        _currentDirPath,
        opId,
      ),
    );
    void listener() {
      if (!mounted) {
        op.removeListener(listener);
        return;
      }
      final done =
          op.status != FileOperationStatus.running &&
          op.status != FileOperationStatus.pending;
      if (done) {
        op.removeListener(listener);
        if (op.status == FileOperationStatus.completed &&
            op.destDirPath == _currentDirPath) {
          _loadDirectoryContents(_currentDirPath);
        }
        if (op.status == FileOperationStatus.completed ||
            op.status == FileOperationStatus.completedWithErrors) {
          _maybeDeleteImportSources(op, isFolder: false);
        }
      }
    }
    op.addListener(listener);
  }

  Future<void> _maybeDeleteImportSources(
    FileOperation op, {
    required bool isFolder,
  }) async {
    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.deleteOriginalTitle),
        content: Text(
          isFolder
              ? context.l10n.deleteOriginalFolderMessage
              : context.l10n.deleteOriginalFilesMessage,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.keepOriginal),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.deleteOriginalButton),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final deleted = await vaultExplorerApi.deleteImportSources(op.id);
    if (!mounted) return;
    _setStatus(
      deleted > 0
          ? context.l10n.deletedOriginalCount(deleted)
          : context.l10n.couldNotDeleteOriginals,
      error: deleted == 0,
      autoClear: const Duration(seconds: 3),
    );
  }

  Future<void> _importFolderFromDevice() async {
    if (_isReadOnly) {
      _setStatus(context.l10n.readOnlyContainerWarning, error: true);
      return;
    }
    _signalActivity();
    final op = _opSvc.enqueueImport(
      dest: widget.container,
      destDirPath: _currentDirPath,
      isFolder: true,
      performImport: (opId) => vaultExplorerApi.importFolder(
        widget.container,
        _currentDirPath,
        opId,
      ),
    );
    void listener() {
      if (!mounted) {
        op.removeListener(listener);
        return;
      }
      final done =
          op.status != FileOperationStatus.running &&
          op.status != FileOperationStatus.pending;
      if (done) {
        op.removeListener(listener);
        if (op.status == FileOperationStatus.completed &&
            op.destDirPath == _currentDirPath) {
          _loadDirectoryContents(_currentDirPath);
        }
        if (op.status == FileOperationStatus.completed ||
            op.status == FileOperationStatus.completedWithErrors) {
          _maybeDeleteImportSources(op, isFolder: true);
        }
      }
    }
    op.addListener(listener);
  }

  Future<void> _captureFromCamera() async {
    if (_isReadOnly) {
      _setStatus(context.l10n.readOnlyContainerWarning, error: true);
      return;
    }
    _signalActivity();
    try {
      final captured = await Navigator.push<({String savedName, bool isVideo})>(
        context,
        MaterialPageRoute(
          builder: (_) => CameraCaptureScreen(
            container: widget.container,
            targetDirPath: _currentDirPath,
          ),
        ),
      );
      if (captured == null || !mounted) return;
      await _loadDirectoryContents(_currentDirPath);
      _setStatus(
        captured.isVideo
            ? context.l10n.videoCapturedEncrypted
            : context.l10n.photoCapturedEncrypted,
        autoClear: const Duration(seconds: 3),
      );
    } catch (e) {
      if (mounted) {
        _setStatus(context.l10n.cameraCaptureFailed('${e.runtimeType}'), error: true);
      }
    }
  }

  bool _matchesFilter(String fileName) {
    if (_currentFilter == null) return true;
    switch (_currentFilter) {
      case 'image':
        return MediaViewerConstants.isImage(fileName);
      case 'video':
        return MediaViewerConstants.isVideo(fileName);
      case 'audio':
        return MediaViewerConstants.isAudio(fileName);
      case 'document':
        return _documentExts
            .contains(fileName.split('.').last.toLowerCase());
      default:
        return true;
    }
  }

  Future<void> _extractArchive() async {
    if (_archiveContext == null) return;
    if (_isReadOnly) {
      _setStatus(context.l10n.readOnlyContainerWarning, error: true);
      return;
    }
    final archivePath = _pathStack[_archiveContext!.pathStackEntryIndex].fatPath;
    final parentDir = archivePath.contains('/')
        ? archivePath.substring(0, archivePath.lastIndexOf('/'))
        : '';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.extractArchive),
        content: Text(context.l10n.extractAllFilesToFolder(parentDir.isEmpty ? context.l10n.rootFolderLabel : parentDir)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.l10n.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(context.l10n.extract)),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _isLoading = true);
    try {
      final count = await ArchiveService.extractAllToContainer(
        container: widget.container,
        archiveContext: _archiveContext!,
        targetDirInContainer: parentDir,
      );
      if (mounted) {
        _setStatus(context.l10n.extractedCount(count), autoClear: const Duration(seconds: 3));
      }
    } catch (e) {
      if (mounted) {
        _setStatus(context.l10n.failedToExtractGeneric('${e.runtimeType}'), error: true);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _onLayoutModeChanged(BrowserLayoutMode mode) async {
    setState(() => _layoutMode = mode);
    try {
      final settings = await AppSettingsService.loadSettings();
      final updatedSettings = settings.copyWith(defaultLayoutMode: mode);
      await AppSettingsService.saveSettings(updatedSettings);
    } catch (e) {
      debugPrint('Failed to save layout mode: $e');
    }
  }

  Future<void> _onSortChanged(SortBy field) async {
    setSort(field);
    try {
      final settings = await AppSettingsService.loadSettings();
      final updatedSettings = settings.copyWith(
        defaultFileSortBy: sortBy,
        defaultFileSortAscending: sortAscending,
      );
      await AppSettingsService.saveSettings(updatedSettings);
    } catch (e) {
      debugPrint('Failed to save sort settings: $e');
    }
  }

  Map<FileManagerAction, WidgetBuilder> _buildActionBuilders() {
    final hasLocalMedia = _currentItems
        .where((e) => !e.isDir)
        .map((e) => e.name)
        .any(_isSupportedMedia);
    final hasSubfolders = _currentItems.any((e) => e.isDir);
    final canPlayMedia = hasLocalMedia || hasSubfolders;
    return {
      FileManagerAction.search: (context) => IconButton(
            icon: Icon(_searchActive ? Icons.search_off_rounded : Icons.search_rounded),
            tooltip: _searchActive ? context.l10n.closeSearchTooltip : context.l10n.searchInThisFolderTooltip,
            onPressed: () => setState(() {
              _searchActive = !_searchActive;
              if (!_searchActive) _searchQuery = '';
            }),
          ),
      FileManagerAction.add: (context) => AddItemMenuButton(
            isReadOnly: _isReadOnly,
            hasArchiveContext: _archiveContext != null,
            container: widget.container,
            currentDirPath: _currentDirPath,
            currentItems: _currentItems,
            onSetStatus: _setStatus,
            onExtractArchive: _extractArchive,
            onSignalActivity: _signalActivity,
            onLoadDirectoryContents: _loadDirectoryContents,
            onCaptureFromCamera: _captureFromCamera,
            onImportFilesFromDevice: _importFilesFromDevice,
            onImportFolderFromDevice: _importFolderFromDevice,
            onAddVaultItem: _addVaultItem,
          ),
      FileManagerAction.viewToggle: (context) => LayoutModeMenuButton(
            layoutMode: _layoutMode,
            onLayoutModeChanged: _onLayoutModeChanged,
          ),
      FileManagerAction.sort: (context) => SortMenuButton(
            sortBy: sortBy,
            sortAscending: sortAscending,
            onSortChanged: _onSortChanged,
          ),
      FileManagerAction.playMedia: (context) => IconButton(
            icon: const Icon(Icons.play_circle_outline_rounded),
            tooltip: context.l10n.playMediaHereTooltip,
            onPressed: canPlayMedia ? _startMediaViewerFromCurrentLocation : null,
          ),
    };
  }

  @override
  Widget build(BuildContext context) {
    if (_isContainerLocked) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.expand(),
      );
    }

    int compareOverall(RawEntry ea, RawEntry eb) {
      final aPinned = _isPinned(ea);
      final bPinned = _isPinned(eb);
      if (aPinned != bPinned) {
        return aPinned ? -1 : 1;
      }
      if (ea.isDir != eb.isDir) {
        return ea.isDir ? -1 : 1;
      }
      return compareItems(ea, eb);
    }

    final query = _searchQuery.trim().toLowerCase();
    final filteredItems = _currentItems.where((item) {
      final name = item.name;
      if (query.isNotEmpty && !name.toLowerCase().contains(query)) return false;
      if (item.isDir) {
        if (query.isEmpty && _currentFilter != null) return false;
        return true;
      }
      return _matchesFilter(name);
    }).toList()
      ..sort(compareOverall);

    final dirCount = filteredItems.where((e) => e.isDir).length;
    final fileCount = filteredItems.where((e) => !e.isDir).length;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final showActionBar = !_searchActive;
    final actionBuilders = _buildActionBuilders();
    // Same computation _buildAppBar used to do internally; needed here now
    // since it's a parameter to buildBrowserAppBar rather than something
    // that function can read off private state itself.
    final isFiltered = query.isNotEmpty || _currentFilter != null;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        if (isSelectionMode) {
          exitSelectionMode();
        } else if (_searchActive) {
          setState(() => _clearSearch());
        } else if (!_atRoot) {
          _navigateUp();
        } else {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: buildBrowserAppBar(
          context,
          container: widget.container,
          filteredItems: filteredItems,
          dirCount: dirCount,
          fileCount: fileCount,
          isSelectionMode: isSelectionMode,
          selectedItems: selectedItems,
          isReadOnly: _isReadOnly,
          searchActive: _searchActive,
          currentDirPath: _currentDirPath,
          toolbarConfig: _toolbarConfig,
          currentFilter: _currentFilter,
          freeSpace: _freeSpace,
          selectedTotalBytes: selectedTotalBytes,
          hasPendingFolderSizes: hasPendingFolderSizes,
          actionBuilders: actionBuilders,
          isFolderMounted: _isFolderMounted,
          isPinned: _isPinned,
          onExitSelectionMode: exitSelectionMode,
          onSelectAll: () => setState(() => selectedItems.addAll(filteredItems)),
          onCopy: () => _initClipboard(cut: false),
          onCut: () => _initClipboard(cut: true),
          onExport: _exportSelectedToStorage,
          onDelete: _batchDelete,
          onTogglePin: _togglePinSelected,
          onDirectoryReload: _loadDirectoryContents,
          onSetStatus: (msg, {required bool error}) => _setStatus(msg, error: error),
          onShowOpenWithDialog: _showOpenWithDialog,
          onShowFolderDocumentProviderSheet: _showFolderDocumentProviderSheet,
          onToggleFolderDocumentProvider: _toggleFolderDocumentProvider,
          onFilterChanged: (value) => setState(() => _currentFilter = value),
          onSettingsClosed: _loadToolbarConfig,
          isFiltered: isFiltered,
          onPaste: _isReadOnly ? null : _paste,
        ),
        bottomNavigationBar: (!isLandscape && showActionBar)
            ? FileManagerActionBar(
                axis: Axis.horizontal,
                actions: _toolbarConfig.visible,
                builders: actionBuilders,
              )
            : null,
        body: Stack(
          children: [
            Column(
              children: [
                if (_toolbarConfig.showBreadcrumbBar) ...[
                  BreadcrumbBar(stack: _pathStack, onTap: _jumpTo),
                  const Divider(),
                ],
                Expanded(
                  child: buildBrowserBody(
                    context,
                    filteredItems,
                    isLoading: _isLoading,
                    currentItems: _currentItems,
                    atRoot: _atRoot,
                    onNavigateUp: _atRoot ? null : _navigateUp,
                    searchQuery: _searchQuery,
                    layoutMode: _layoutMode,
                    container: widget.container,
                    currentDirPath: _currentDirPath,
                    thumbnailCacheMode: _resolvedThumbnailCacheMode,
                    thumbnailQuality: _resolvedThumbnailQuality,
                    toolbarConfig: _toolbarConfig,
                    isSelectionMode: isSelectionMode,
                    selectedItems: selectedItems,
                    searchActive: _searchActive,
                    mountedDocProviderFolders: _mountedDocProviderFolders,
                    isFolderMounted: _isFolderMounted,
                    isPinned: _isPinned,
                    onDirTap: _handleDirTap,
                    onFileTap: _handleFileTap,
                    onItemLongPress: _handleItemLongPress,
                    // Exact original closure bodies, just relocated from
                    // inside _buildBody to here -- see the doc comment on
                    // buildBrowserBody for why these weren't rewritten.
                    onGridColumnCountChanged: (count) {
                      _toolbarConfig = isLandscape
                          ? _toolbarConfig.copyWith(gridColumnsLandscape: count)
                          : _toolbarConfig.copyWith(gridColumnsPortrait: count);
                      FileManagerToolbarService.instance.save(_toolbarConfig);
                    },
                    onMasonryColumnCountChanged: (count) {
                      _toolbarConfig = isLandscape
                          ? _toolbarConfig.copyWith(masonryColumnsLandscape: count)
                          : _toolbarConfig.copyWith(masonryColumnsPortrait: count);
                      FileManagerToolbarService.instance.save(_toolbarConfig);
                    },
                    onListZoomLevelChanged: (newZoom) {
                      _toolbarConfig = _toolbarConfig.copyWith(listZoomLevel: newZoom);
                      FileManagerToolbarService.instance.save(_toolbarConfig);
                    },
                    onRefresh: () => _loadDirectoryContents(_currentDirPath),
                    isListingTruncated: _isListingTruncated,
                  ),
                ),
              ],
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: _searchActive ? 0 : 16,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_statusMessage != null)
                    Padding(
                      padding: EdgeInsets.only(bottom: _searchActive ? 16 : 8, left: 16, right: 16),
                      child: AnimatedSwitcher(
                        duration: AppMotion.short2,
                        child: InlineBanner(
                          _statusMessage!,
                          key: ValueKey(_statusMessage),
                          tone: _statusIsError ? AppBannerTone.error : AppBannerTone.info,
                          trailing: IconButton(
                            icon: const Icon(Icons.close_rounded, size: AppIconSize.small),
                            onPressed: _clearStatus,
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            padding: EdgeInsets.zero,
                          ),
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
                    )
                  else
                    const Align(
                      alignment: Alignment.centerRight,
                      child: FloatingActivityStack(),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}