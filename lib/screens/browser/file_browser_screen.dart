import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/clipboard_item.dart';
import '../../models/file_operation.dart';
import '../../models/mounted_container.dart';
import '../../models/thumbnail_cache_mode.dart';
import '../../models/thumbnail_quality.dart';
import '../../models/vault_item.dart';
import '../../services/app_settings_service.dart';
import '../../services/cross_container_clipboard.dart';
import '../../services/vault_items_service.dart';
import '../../services/vaultexplorer_api.dart';
import '../../theme.dart';
import '../../utils/format_utils.dart';
import '../../utils/raw_entry.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/floating_activity_stack.dart';
import 'browser_dialogs.dart';
import 'viewer/media_viewer_constants.dart';
import 'viewer/media_viewer_screen.dart';
import 'viewer/text_editor_screen.dart';
import 'mixins/selection_mixin.dart';
import 'mixins/sort_mixin.dart';
import 'widgets/breadcrumb_bar.dart';
import 'widgets/conflict_resolution_sheet.dart';
import 'widgets/file_grid_view.dart';
import 'widgets/file_list_view.dart';
import 'widgets/selection_app_bar.dart';
import '../vault/vault_item_detail_screen.dart';
import '../vault/vault_item_edit_screen.dart';
import '../../utils/file_type_utils.dart';

// ── Layout mode ───────────────────────────────────────────────────────────────

enum BrowserLayoutMode { list, grid }

// ── Path segment model ────────────────────────────────────────────────────────

class PathSegment {
  final String label;
  final String fatPath;
  const PathSegment(this.label, this.fatPath);
}

// ── Screen ────────────────────────────────────────────────────────────────────

class FileBrowserScreen extends StatefulWidget {
  final MountedContainer container;
  final MountedContainer? Function(int volId)? resolveContainer;
  final ThumbnailCacheMode? thumbnailCacheMode;
  final VoidCallback? onUserActivity;

  const FileBrowserScreen({
    super.key,
    required this.container,
    this.thumbnailCacheMode,
    this.onUserActivity,
    this.resolveContainer,
  });

  @override
  State<FileBrowserScreen> createState() => _FileBrowserScreenState();
}

class _FileBrowserScreenState extends State<FileBrowserScreen>
    with SelectionMixin<FileBrowserScreen>, SortMixin<FileBrowserScreen> {
  final List<PathSegment> _pathStack = [const PathSegment('Root', '')];
  List<String> _currentItems = [];
  bool _isLoading = false;
  int _freeSpace = 0;
  bool _isListingTruncated = false;
  String? _statusMessage;
  bool _statusIsError = false;

  CrossContainerClipboard get _clip => CrossContainerClipboard.instance;
  FileOperationService get _opSvc => FileOperationService.instance;

  bool _isSearchActive = false;
  String _searchQuery = '';
  final _searchController = TextEditingController();

  BrowserLayoutMode _layoutMode = BrowserLayoutMode.list;
  String? _currentFilter;
  double _sidebarWidth = 200.0;

  ThumbnailCacheMode _resolvedThumbnailCacheMode = ThumbnailCacheMode.appCache;
  ThumbnailQuality _resolvedThumbnailQuality = ThumbnailQuality.medium;

  static const int _maxScanDepth = 20;

  // Document-type extensions used only by _matchesFilter; has no media
  // equivalent in MediaViewerConstants so it stays local.
  static const _documentExts = {
    'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'rtf',
    'csv', 'zip', 'tar', 'gz', 'json', 'xml',
  };

  bool get _atRoot => _pathStack.length == 1;
  String get _currentDirPath => _pathStack.last.fatPath;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _freeSpace = widget.container.freeSpace;
    _initSettingsAndContents();
    VaultExplorerApi.addUsbContainerDetachedListener(_onContainerDetached);
  }

  @override
  void dispose() {
    VaultExplorerApi.removeUsbContainerDetachedListener(_onContainerDetached);
    _searchController.dispose();
    super.dispose();
  }

  void _signalActivity() => widget.onUserActivity?.call();


  void _onContainerDetached(int volId) {
    if (!mounted || volId != widget.container.volId) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  // ── Init ──────────────────────────────────────────────────────────────────

  Future<void> _initSettingsAndContents() async {
    setState(() => _isLoading = true);
    try {
      if (widget.thumbnailCacheMode != null) {
        _resolvedThumbnailCacheMode = widget.thumbnailCacheMode!;
      } else {
        final appSettings = await AppSettingsService.loadSettings();
        final records = await ContainerRepository.instance.loadAll();
        final record = records[widget.container.uri];
        if (mounted) {
          setState(() {
            _resolvedThumbnailCacheMode =
                record?.thumbnailCacheMode ??
                appSettings.defaultThumbnailCacheMode;
            _resolvedThumbnailQuality =
                record?.thumbnailQuality ??
                appSettings.defaultThumbnailQuality;
          });
        }
      }
    } catch (e) {
      debugPrint('Failed to resolve settings: $e');
    }
    await _loadDirectoryContents(_currentDirPath);
  }

  // ── Inline status ─────────────────────────────────────────────────────────

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

  // ── Directory loading ─────────────────────────────────────────────────────

  Future<void> _loadDirectoryContents(String path) async {
    setState(() => _isLoading = true);
    _signalActivity();
    try {
      final items = await vaultExplorerApi.listDirectory(
        widget.container,
        path,
      );
      final space = await vaultExplorerApi.getSpaceInfo(widget.container);
      
      if (mounted) {
        final isTruncated = items?.any((f) => f == 'System:TRUNCATED') ?? false;
        
        setState(() {
            _currentItems = items?.where((f) => !f.startsWith('System:')).toList() ?? [];
            _isListingTruncated = isTruncated;
            if (space != null && space.length > 1) _freeSpace = space[1];
            _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _setStatus('Failed loading folder: ${e.runtimeType}', error: true);
      }
    }
  }

  // ── Search ────────────────────────────────────────────────────────────────

  void _clearSearch() {
    _isSearchActive = false;
    _searchQuery = '';
    _searchController.clear();
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  void _enterDirectory(String rawDirEntry) {
    final entry = RawEntry.parse(rawDirEntry);
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
    setState(() {
      _pathStack.removeLast();
      _clearSearch();
      _currentFilter = null;
    });
    _loadDirectoryContents(_currentDirPath);
  }

  void _jumpTo(int index) {
    if (index == _pathStack.length - 1) return;
    setState(() {
      _pathStack.removeRange(index + 1, _pathStack.length);
      _clearSearch();
      _currentFilter = null;
    });
    _loadDirectoryContents(_currentDirPath);
  }

  // ── SelectionMixin override ───────────────────────────────────────────────

  @override
  void toggleSelectItem(String item) {
    super.toggleSelectItem(item);
    if (selectedFolderCount > 0) {
      fetchFolderSizes(widget.container, _currentDirPath);
    }
  }

  // ── Item interaction ──────────────────────────────────────────────────────

  void _handleDirTap(String rawItem) {
    _signalActivity();
    if (isSelectionMode) {
      toggleSelectItem(rawItem);
    } else {
      _enterDirectory(rawItem);
    }
  }

  Future<void> _handleFileTap(String rawItem) async {
    _signalActivity();
    if (isSelectionMode) {
      toggleSelectItem(rawItem);
      return;
    }

    final entry = RawEntry.parse(rawItem);
    final fullPath = _currentDirPath.isEmpty
        ? entry.name
        : '$_currentDirPath/${entry.name}';

    final parts = entry.name.split('.');
    final ext = parts.length > 1 ? parts.last.toLowerCase() : '';

    // Check if it's a VaultItem (secure item)
    if (VaultItemType.values.any((t) => t.name.toLowerCase() == ext)) {
      final item = await VaultItemsService.instance.loadItem(widget.container, fullPath);

      if (item != null) {
        // Force the title to perfectly match the file's base name in case it was renamed externally
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
        _setStatus('Failed to read secure item', error: true);
      }
      return;
    }

    // Normal files
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
    } else if (pref != null && pref.startsWith('package:')) {
      _openFileWithApp(entry.name, fullPath, packageName: pref.substring(8));
    } else if (pref == 'external') {
      _openFileWithApp(entry.name, fullPath);
    } else {
      if (_isSupportedMedia(entry.name)) {
        _openMediaViewer(entry.name, fullPath);
      } else {
        if (!mounted) return;
        await _showOpenWithDialog(entry.name, fullPath, ext, settings);
      }
    }
  }

  void _openMediaViewer(String fileName, String fullPath) {
    // Opens just the tapped file. The viewer's own "Playlist" menu lets the
    // user opt into scanning this folder (or all subfolders) afterward.
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
              title: const Text('Open File'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Choose how to open "$fileName":',
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
                                      ? 'In-app Media Viewer'
                                      : 'In-app Text Editor',
                                  style: textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  isMedia
                                      ? 'Play video/audio or view image in-app'
                                      : 'View/edit text, markdown, code',
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
                                  'External App',
                                  style: textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  'Send file to third-party app',
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
                              ? 'Always remember choice for .$ext files'
                              : 'Always remember choice for files without extension',
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
                  child: const Text('Cancel'),
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
    }
  }

  Future<void> _startMediaViewerFromCurrentLocation() async {
    _signalActivity();
    final sortedItems = _currentItems
        .where((f) => !f.startsWith('[DIR]') && !f.startsWith('System:'))
        .toList()
      ..sort(compareItems);
    final localMedia = sortedItems
        .map((f) => RawEntry.parse(f).name)
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
      'Scanning subfolders for media…',
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
          'No media files found in this folder or its subfolders',
          error: true,
        );
      }
    } catch (e) {
      _setStatus('Failed to scan subfolders: $e', error: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _handleItemLongPress(String rawItem) {
    HapticFeedback.selectionClick();
    _signalActivity();
    if (!isSelectionMode) {
      setState(() {
        isSelectionMode = true;
        selectedItems.add(rawItem);
      });
      if (selectedFolderCount > 0) {
        fetchFolderSizes(widget.container, _currentDirPath);
      }
    } else {
      toggleSelectItem(rawItem);
    }
  }

  // ── Media helpers ─────────────────────────────────────────────────────────

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
  }) async {
    _signalActivity();
    try {
      final ok = await vaultExplorerApi.openWithApp(
        widget.container,
        fullPath,
        packageName: packageName,
      );
      if (!ok && mounted) {
        _setStatus('No app found for this file type', error: true);
      }
    } catch (_) {
      if (mounted) _setStatus('Could not open "$cleanName"', error: true);
    }
  }

  // ── Vault items ───────────────────────────────────────────────────────────

  Future<void> _addVaultItem(VaultItemType type) async {
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
    // Refresh directory as VaultItems natively exist in the filesystem now
    _loadDirectoryContents(_currentDirPath);
  }

  // ── Clipboard ─────────────────────────────────────────────────────────────

  void _initClipboard({required bool cut}) {
    _signalActivity();

    final clipItems = selectedItems.map((rawItem) {
      final entry = RawEntry.parse(rawItem);
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
    _signalActivity();

    final srcVolId = _clip.sourceVolId;
    if (srcVolId == null) {
      _setStatus('Clipboard source is invalid', error: true);
      _clip.clear();
      return;
    }

    final isCrossContainer = !_clip.isFromVolume(widget.container.volId);
    MountedContainer? srcContainer;

    if (isCrossContainer) {
      if (widget.resolveContainer == null) {
        _setStatus('Cross-container paste is not configured.', error: true);
        return;
      }
      srcContainer = widget.resolveContainer!(srcVolId);
      if (srcContainer == null) {
        _setStatus(
          'Cross-container paste requires both containers to remain mounted.',
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
          op.status != FileOperationStatus.pending &&
          op.status != FileOperationStatus.running;
      if (done) {
        op.removeListener(listener);
        _loadDirectoryContents(_currentDirPath);
      }
    }

    op.addListener(listener);
  }

  void _batchDelete() {
    HapticFeedback.heavyImpact();
    _signalActivity();
    BrowserDialogs.showBatchDelete(
      context,
      toDelete: List<String>.from(selectedItems),
      onConfirmed: (rawItems) async {
        setState(() => _isLoading = true);

        final clipItems = rawItems.map((raw) {
          final e = RawEntry.parse(raw);
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

        exitSelectionMode();
        await _loadDirectoryContents(_currentDirPath);
        _setStatus(
          failCount == 0
              ? 'Deleted $deleted item(s)'
              : '$deleted deleted · $failCount failed',
          error: failCount > 0,
        );
      },
    );
  }

  Future<void> _exportSelectedToStorage() async {
    _signalActivity();
    
    final items = selectedItems.map((raw) {
      final e = RawEntry.parse(raw);
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
        count > 0 ? 'Exported $count file(s)' : 'Export cancelled or failed',
        error: count == 0,
      );
    } catch (e) {
      _setStatus('Export error: ${e.runtimeType}', error: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
    exitSelectionMode();
  }

  Future<void> _importFilesFromDevice() async {
    _signalActivity();
    final op = _opSvc.enqueueImport(
      dest: widget.container,
      destDirPath: _currentDirPath,
      isFolder: false,
      performImport: () => vaultExplorerApi.importFiles(
        widget.container,
        _currentDirPath,
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
      }
    }

    op.addListener(listener);
  }

  Future<void> _importFolderFromDevice() async {
    _signalActivity();
    final op = _opSvc.enqueueImport(
      dest: widget.container,
      destDirPath: _currentDirPath,
      isFolder: true,
      performImport: () => vaultExplorerApi.importFolder(
        widget.container,
        _currentDirPath,
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
      }
    }

    op.addListener(listener);
  }

  // ── Filter helpers ────────────────────────────────────────────────────────

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

  Widget _buildSortMenuButton(
    SortBy value,
    String label,
    ColorScheme cs,
    TextTheme textTheme,
  ) {
    final isActive = sortBy == value;
    return MenuItemButton(
      onPressed: () => setSort(value),
      leadingIcon: Icon(
        isActive
            ? (sortAscending
                  ? Icons.arrow_upward_rounded
                  : Icons.arrow_downward_rounded)
            : Icons.sort_rounded,
        size: 16,
        color: isActive ? cs.primary : cs.onSurfaceVariant,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontWeight: isActive ? FontWeight.w700 : FontWeight.normal,
        ),
      ),
    );
  }

  Widget _buildFilterMenuButton(
    String? value,
    String label,
    IconData icon,
    ColorScheme cs,
    TextTheme textTheme,
  ) {
    final isActive = _currentFilter == value;
    return MenuItemButton(
      onPressed: () => setState(() => _currentFilter = value),
      leadingIcon: Icon(
        icon,
        size: 16,
        color: isActive ? cs.primary : cs.onSurfaceVariant,
      ),
      trailingIcon: isActive
          ? Icon(Icons.check_rounded, size: 16, color: cs.primary)
          : null,
      child: Text(
        label,
        style: TextStyle(
          fontWeight: isActive ? FontWeight.w700 : FontWeight.normal,
        ),
      ),
    );
  }

  void _showCreateOptionsSheet() {
    _signalActivity();
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => AppBottomSheet(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 4),
                child: Text(
                  'New item',
                  style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 4),
              SheetOptionTile(
                icon: Icons.create_new_folder_outlined,
                iconColor: cs.primary,
                title: 'New Folder',
                onTap: () {
                  Navigator.pop(sheetContext);
                  BrowserDialogs.showCreateFolder(
                    context,
                    container: widget.container,
                    currentDirPath: _currentDirPath,
                    onSuccess: () => _loadDirectoryContents(_currentDirPath),
                  );
                },
              ),
              SheetOptionTile(
                icon: Icons.insert_drive_file_outlined,
                iconColor: cs.primary,
                title: 'New Text File',
                onTap: () {
                  Navigator.pop(sheetContext);
                  BrowserDialogs.showCreateFile(
                    context,
                    container: widget.container,
                    currentDirPath: _currentDirPath,
                    onSuccess: () => _loadDirectoryContents(_currentDirPath),
                  );
                },
              ),
              SheetOptionTile(
                icon: Icons.upload_file_outlined,
                iconColor: cs.secondary,
                title: 'Import Files',
                subtitle: 'Copy files in from your device',
                onTap: () {
                  Navigator.pop(sheetContext);
                  _importFilesFromDevice();
                },
              ),
              SheetOptionTile(
                icon: Icons.drive_folder_upload_outlined,
                iconColor: cs.secondary,
                title: 'Import Folder',
                subtitle: 'Copy an entire folder in from your device',
                onTap: () {
                  Navigator.pop(sheetContext);
                  _importFolderFromDevice();
                },
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 4),
                child: Text(
                  'SECURE ITEM',
                  style: textTheme.labelSmall?.copyWith(
                    color: cs.primary,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              ...VaultItemType.values.map(
                (type) => SheetOptionTile(
                  icon: vaultIconForExt(type.name) ?? Icons.lock_rounded,
                  iconColor: vaultColorForExt(type.name) ?? cs.primary,
                  title: type.label,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _addVaultItem(type);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

 @override
  Widget build(BuildContext context) {
    final dirs = _currentItems.where((f) => f.startsWith('[DIR]')).toList()
      ..sort(compareItems);
    final files =
        _currentItems
            .where((f) => !f.startsWith('[DIR]') && !f.startsWith('System:'))
            .toList()
          ..sort(compareItems);

    final query = _searchQuery.trim().toLowerCase();

    final filteredDirs = (query.isEmpty && _currentFilter == null)
        ? dirs
        : (query.isEmpty
              ? <String>[]
              : dirs
                    .where(
                      (d) =>
                          RawEntry.parse(d).name.toLowerCase().contains(query),
                    )
                    .toList());

    final filteredFiles = files.where((f) {
      final name = RawEntry.parse(f).name;
      if (query.isNotEmpty && !name.toLowerCase().contains(query)) return false;
      return _matchesFilter(name);
    }).toList();

    final cs = Theme.of(context).colorScheme;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        if (isSelectionMode) {
          exitSelectionMode();
        } else if (_clip.hasItems &&
            _clip.isFromVolume(widget.container.volId)) {
          _clip.clear();
          setState(() {});
        } else if (_isSearchActive) {
          setState(() => _clearSearch());
        } else if (!_atRoot) {
          _navigateUp();
        } else {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: _buildAppBar(context, filteredDirs, filteredFiles),

        // ── Floating activity stack ───────────────────────────────────────
        //
        // FIX: previously the clipboard pill was a `floatingActionButton`
        // (centerFloat) while the operation progress bar was a *different*,
        // differently-styled widget docked in-flow inside the body Column
        // above the status bar. The two could overlap unpredictably and
        // shared no color language. Both now live in one FloatingActivityStack
        // overlaid via Stack, matching the exact pattern used on the
        // dashboard, so the two screens now feel like one coherent system.
        body: Stack(
          children: [
            isLandscape
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Sidebar on the left
                      Container(
                        width: _sidebarWidth,
                        color: cs.surfaceContainerLow,
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _StatsBar(
                                dirCount: filteredDirs.length,
                                fileCount: filteredFiles.length,
                                freeSpaceBytes: _freeSpace,
                                isFiltered: query.isNotEmpty || _currentFilter != null,
                                isVertical: true,
                              ),
                            ],
                          ),
                        ),
                      ),
                      GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onHorizontalDragUpdate: (details) {
                          setState(() {
                            _sidebarWidth = (_sidebarWidth + details.delta.dx)
                                .clamp(160.0, 300.0);
                          });
                        },
                        child: MouseRegion(
                          cursor: SystemMouseCursors.resizeLeftRight,
                          child: Container(
                            width: 8,
                            color: Colors.transparent,
                            child: const Center(
                              child: VerticalDivider(
                                width: 1,
                                thickness: 1,
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Main content area on the right
                      Expanded(
                        child: Column(
                          children: [
                            BreadcrumbBar(stack: _pathStack, onTap: _jumpTo),
                            const Divider(),
                            Expanded(child: _buildBody(filteredDirs, filteredFiles)),
                            if (_statusMessage != null)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
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
                          ],
                        ),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      BreadcrumbBar(stack: _pathStack, onTap: _jumpTo),
                      _StatsBar(
                        dirCount: filteredDirs.length,
                        fileCount: filteredFiles.length,
                        freeSpaceBytes: _freeSpace,
                        isFiltered: query.isNotEmpty || _currentFilter != null,
                      ),
                      const Divider(),
                      Expanded(child: _buildBody(filteredDirs, filteredFiles)),
                      if (_statusMessage != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
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
                    ],
                  ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 16,
              child: Center(
                child: FloatingActivityStack(onPaste: _paste),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── App bar ───────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    List<String> dirs,
    List<String> files,
  ) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final allItems = [...dirs, ...files];

    if (isSelectionMode) {
      final single = selectedItems.length == 1;
      final singleFile = single && !selectedItems.first.startsWith('[DIR] ');

      final totalBytes = selectedTotalBytes;
      final isPending = hasPendingFolderSizes;
      final sizeLabel = isPending
          ? (totalBytes > 0
                ? '${formatBytes(totalBytes)} (calculating…)'
                : 'calculating…')
          : formatBytes(totalBytes);

      return SelectionAppBar(
        selectedCount: selectedItems.length,
        selectionLabel: sizeLabel,
        singleSelected: single,
        singleFileSelected: singleFile,
        onClose: exitSelectionMode,
        onSelectAll: () => setState(() => selectedItems.addAll(allItems)),
        onRename: () {
          final raw = selectedItems.first;
          final entry = RawEntry.parse(raw);
          final parts = entry.name.split('.');
          final ext = parts.length > 1 ? parts.last.toLowerCase() : '';
          
          if (VaultItemType.values.any((t) => t.name.toLowerCase() == ext)) {
             _setStatus('Edit secure items to rename them');
             exitSelectionMode();
             return;
          }
          
          BrowserDialogs.showRename(
            context,
            container: widget.container,
            oldName: entry.name,
            currentDirPath: _currentDirPath,
            onSuccess: () => _loadDirectoryContents(_currentDirPath),
          );
          exitSelectionMode();
        },
        onCopy: () => _initClipboard(cut: false),
        onCut: () => _initClipboard(cut: true),
        onExport: _exportSelectedToStorage,
        onDelete: _batchDelete,
        onOpenWithApp: () async {
          final raw = selectedItems.first;
          final entry = RawEntry.parse(raw);
          final path = _currentDirPath.isEmpty
              ? entry.name
              : '$_currentDirPath/${entry.name}';
          final parts = entry.name.split('.');
          final ext = parts.length > 1 ? parts.last.toLowerCase() : '';
          exitSelectionMode();
          
          if (VaultItemType.values.any((t) => t.name.toLowerCase() == ext)) {
             _setStatus('Vault items cannot be opened in external apps', error: true);
             return;
          }
          
          final settings = await AppSettingsService.loadSettings();
          if (mounted) {
            await _showOpenWithDialog(entry.name, path, ext, settings);
          }
        },
      );
    }

    if (_isSearchActive) {
      return AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Close search',
          onPressed: () => setState(() => _clearSearch()),
        ),
        title: TextField(
          controller: _searchController,
          autofocus: true,
          onChanged: (val) => setState(() => _searchQuery = val),
          style: textTheme.bodyMedium?.copyWith(color: cs.onSurface),
          decoration: InputDecoration(
            hintText: 'Search in this folder…',
            hintStyle: TextStyle(color: cs.outline, fontSize: 14),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
            contentPadding: EdgeInsets.zero,
          ),
        ),
        actions: [
          if (_searchQuery.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              tooltip: 'Clear',
              onPressed: () => setState(() {
                _searchQuery = '';
                _searchController.clear();
              }),
            ),
        ],
      );
    }

    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        tooltip: 'Back to dashboard',
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Text(widget.container.displayName),
      actions: [
        IconButton(
          icon: const Icon(Icons.search),
          tooltip: 'Search in this folder',
          onPressed: () => setState(() => _isSearchActive = true),
        ),
        // ── + menu ────────────────────────────────────────────────────────
        // FIX (audit C3): previously a flat PopupMenuButton mixing New
        // Folder/New File/Import Files/Import Folder with all six vault item
        // types in one 10+ item menu. VaultDashboard already solved this
        // exact "too many creation choices" problem with a grouped
        // AppBottomSheet of SheetOptionTiles (_showAddOptionsSheet) — this
        // now reuses that same pattern instead of a second, differently
        // shaped solution to the same UX problem.
        IconButton(
          icon: const Icon(Icons.add),
          tooltip: 'New item',
          onPressed: _showCreateOptionsSheet,
        ),
        MenuAnchor(
          builder: (ctx, controller, child) => IconButton(
            onPressed: () =>
                controller.isOpen ? controller.close() : controller.open(),
            icon: const Icon(Icons.more_vert_rounded),
            tooltip: 'Folder options',
          ),
          menuChildren: [
            MenuItemButton(
              onPressed: () {
                final hasLocalMedia = _currentItems
                    .where(
                      (f) => !f.startsWith('[DIR]') && !f.startsWith('System:'),
                    )
                    .map((f) => RawEntry.parse(f).name)
                    .any(_isSupportedMedia);
                final hasSubfolders = _currentItems.any(
                  (f) => f.startsWith('[DIR] '),
                );
                if (hasLocalMedia || hasSubfolders) {
                  _startMediaViewerFromCurrentLocation();
                }
              },
              leadingIcon: Icon(
                Icons.play_circle_outline_rounded,
                color: cs.primary,
              ),
              child: const Text('Play Media Here'),
            ),
            const PopupMenuDivider(),
            MenuItemButton(
              onPressed: () => setState(() {
                _layoutMode = _layoutMode == BrowserLayoutMode.list
                    ? BrowserLayoutMode.grid
                    : BrowserLayoutMode.list;
              }),
              leadingIcon: Icon(
                _layoutMode == BrowserLayoutMode.list
                    ? Icons.grid_view_rounded
                    : Icons.view_list_rounded,
              ),
              child: Text(
                _layoutMode == BrowserLayoutMode.list
                    ? 'Switch to Gallery'
                    : 'Switch to List',
              ),
            ),
            const PopupMenuDivider(),
            SubmenuButton(
              menuChildren: [
                _buildSortMenuButton(SortBy.name, 'Name', cs, textTheme),
                _buildSortMenuButton(SortBy.size, 'Size', cs, textTheme),
                _buildSortMenuButton(SortBy.extension, 'Type', cs, textTheme),
                _buildSortMenuButton(SortBy.date, 'Date', cs, textTheme),
              ],
              child: const Text('Sort By'),
            ),
            const PopupMenuDivider(),
            SubmenuButton(
              menuChildren: [
                _buildFilterMenuButton(null, 'All Files', Icons.all_inclusive_rounded, cs, textTheme),
                _buildFilterMenuButton('image', 'Images', Icons.image_outlined, cs, textTheme),
                _buildFilterMenuButton('video', 'Videos', Icons.videocam_outlined, cs, textTheme),
                _buildFilterMenuButton('audio', 'Audio', Icons.audiotrack_rounded, cs, textTheme),
                _buildFilterMenuButton('document', 'Documents', Icons.description_outlined, cs, textTheme),
              ],
              child: const Text('Filter By'),
            ),
          ],
        ),
      ],
    );
  }

  // ── Body ──────────────────────────────────────────────────────────────────

  Widget _buildBody(List<String> dirs, List<String> files) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.5));
    }
    if (_currentItems.isEmpty) {
      return AppEmptyState(
        icon: Icons.folder_open_rounded,
        title: 'Empty Folder',
        message: 'Tap + to create files or import from device.',
        actionLabel: _atRoot ? null : 'Go back',
        actionIcon: Icons.arrow_upward_rounded,
        onAction: _atRoot ? null : _navigateUp,
      );
    }
    if (_searchQuery.trim().isNotEmpty && dirs.isEmpty && files.isEmpty) {
      return AppEmptyState(
        icon: Icons.search_off_rounded,
        title: 'No results',
        message: 'Nothing in this folder matches "${_searchQuery.trim()}".',
      );
    }

    final content = _layoutMode == BrowserLayoutMode.grid
        ? FileGridView(
            container: widget.container,
            dirs: dirs,
            files: files,
            isSelectionMode: isSelectionMode,
            selectedItems: selectedItems,
            currentDirPath: _currentDirPath,
            thumbnailCacheMode: _resolvedThumbnailCacheMode,
            thumbnailQuality: _resolvedThumbnailQuality,
            onDirTap: _handleDirTap,
            onFileTap: _handleFileTap,
            onItemLongPress: _handleItemLongPress,
          )
        : FileListView(
            dirs: dirs,
            files: files,
            isSelectionMode: isSelectionMode,
            selectedItems: selectedItems,
            onDirTap: _handleDirTap,
            onFileTap: _handleFileTap,
            onItemLongPress: _handleItemLongPress,
          );

    if (!_isListingTruncated) return content;

    return Column(
      children: [
        const _TruncatedBanner(),
        Expanded(child: content),
      ],
    );
  }
}

// ── Truncated banner ──────────────────────────────────────────────────────────

class _TruncatedBanner extends StatelessWidget {
  const _TruncatedBanner();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      color: cs.tertiaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(children: [
        Icon(Icons.warning_amber_rounded, size: AppIconSize.small, color: cs.onTertiaryContainer),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Showing first 50,000 items — this folder has more files.',
            style: textTheme.bodySmall?.copyWith(
              color: cs.onTertiaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ]),
    );
  }
}

// ── Filter chips bar ──────────────────────────────────────────────────────────


// ── Stats bar ─────────────────────────────────────────────────────────────────

class _StatsBar extends StatelessWidget {
  final int dirCount;
  final int fileCount;
  final int freeSpaceBytes;
  final bool isFiltered;
  final bool isVertical;
  const _StatsBar({
    required this.dirCount,
    required this.fileCount,
    required this.freeSpaceBytes,
    this.isFiltered = false,
    this.isVertical = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (isVertical) {
      return Container(
        color: cs.surfaceContainerLow,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'STORAGE',
              style: textTheme.labelSmall?.copyWith(
                color: cs.primary,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            _stat(context, Icons.folder_rounded, '$dirCount folders'),
            const SizedBox(height: 8),
            _stat(context, Icons.description_rounded, '$fileCount files'),
            const SizedBox(height: 8),
            _stat(context, Icons.storage_rounded, '${formatBytes(freeSpaceBytes)} free'),
            if (isFiltered) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  'filtered',
                  style: textTheme.labelSmall?.copyWith(
                    color: cs.onPrimaryContainer,
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return Container(
      color: cs.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          _stat(context, Icons.folder_rounded, '$dirCount folders'),
          const SizedBox(width: 12),
          _stat(context, Icons.description_rounded, '$fileCount files'),
          const Spacer(),
          if (isFiltered) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                'filtered',
                style: textTheme.labelSmall?.copyWith(
                  color: cs.onPrimaryContainer,
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          _stat(context, Icons.storage_rounded, '${formatBytes(freeSpaceBytes)} free'),
        ],
      ),
    );
  }

  Widget _stat(BuildContext context, IconData icon, String text) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: AppIconSize.inline, color: cs.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(text, style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
      ],
    );
  }
}

// ── Stats bar ─────────────────────────────────────────────────────────────────
