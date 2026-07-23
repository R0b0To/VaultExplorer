import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/core/widgets/activity/floating_activity_stack.dart';
import 'package:vaultexplorer/features/settings/file_manager_toolbar_settings_screen.dart';
import 'package:vaultexplorer/features/browser/archive_file_viewer.dart';
import 'package:vaultexplorer/features/browser/browser_dialogs.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_screen.dart';
import 'package:vaultexplorer/features/browser/viewer/text_editor_screen.dart';
import 'package:vaultexplorer/features/browser/mixins/selection_mixin.dart';
import 'package:vaultexplorer/features/browser/mixins/sort_mixin.dart';
import 'package:vaultexplorer/features/browser/widgets/bottom_search_bar.dart';
import 'package:vaultexplorer/features/browser/widgets/breadcrumb_bar.dart';
import 'package:vaultexplorer/features/browser/widgets/conflict_resolution_sheet.dart';
import 'package:vaultexplorer/features/browser/widgets/file_grid_view.dart';
import 'package:vaultexplorer/features/browser/widgets/file_list_view.dart';
import 'package:vaultexplorer/features/browser/widgets/file_manager_action_bar.dart';
import 'package:vaultexplorer/features/browser/widgets/selection_app_bar.dart';
import 'package:vaultexplorer/features/browser/widgets/stats_bar.dart';
import 'package:vaultexplorer/features/browser/widgets/truncated_banner.dart';
import 'package:vaultexplorer/features/vault_item/vault_item_detail_screen.dart';
import 'package:vaultexplorer/features/vault_item/vault_item_edit_screen.dart';
import 'package:vaultexplorer/core/utils/file_type_utils.dart';
import 'package:vaultexplorer/data/models/browser_layout_mode.dart';


// ── Path segment model ────────────────────────────────────────────────────────

class PathSegment {
  final String label;
  final String fatPath;
  final bool isArchiveRoot;
  const PathSegment(this.label, this.fatPath, {this.isArchiveRoot = false});
}

// ── Screen ────────────────────────────────────────────────────────────────────
//
// Layout philosophy (modularity):
//   - The app bar is deliberately minimal: back button, container name, and
//     a single "settings" menu holding Filters + a link to the toolbar
//     customization screen. It never turns into a search field.
//   - Every functional action (search, add, view mode, sort, play media)
//     lives in one reusable [FileManagerActionBar] — rendered horizontally
//     as the portrait bottom bar, and vertically as the landscape sidebar
//     rail — driven by a user-editable [FileManagerToolbarConfig] so people
//     can reorder or hide entries from FileManagerToolbarSettingsScreen.
//   - Search results in a bottom-docked field (see [BottomSearchBar]) that
//     rides above the keyboard instead of replacing the app bar.
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
  ThumbnailQuality _resolvedThumbnailQuality = ThumbnailQuality.medium;

  // User-customizable ordering/visibility of the action bar — see
  // FileManagerToolbarSettingsScreen.
  FileManagerToolbarConfig _toolbarConfig = FileManagerToolbarConfig.defaults();

  static const int _maxScanDepth = 20;

  // Document-type extensions used only by _matchesFilter; has no media
  // equivalent in MediaViewerConstants so it stays local.
  static const _documentExts = {
    'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'rtf',
    'csv', 'zip', 'tar', 'gz', 'json', 'xml',
  };

  bool get _atRoot => _pathStack.length == 1;
  String get _currentDirPath => _pathStack.last.fatPath;
  bool get _isReadOnly => widget.container.readOnly;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _freeSpace = widget.container.freeSpace;
    _initSettingsAndContents();
    _loadToolbarConfig();
    VaultExplorerApi.addUsbContainerDetachedListener(_onContainerDetached);
  }

  @override
  void dispose() {
    _closeArchive();
    VaultExplorerApi.removeUsbContainerDetachedListener(_onContainerDetached);
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
      final appSettings = await AppSettingsService.loadSettings();
      
      if (widget.thumbnailCacheMode != null) {
        _resolvedThumbnailCacheMode = widget.thumbnailCacheMode!;
      } else {
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

      // Load default layout mode here
      if (mounted) {
        setState(() {
          _layoutMode = appSettings.defaultLayoutMode;
        });
      }

      // A read-only mount refuses every write native-side (physicalWrite()'s
      // hard readOnly check), including the .thumbcache/ writes
      // ThumbnailCacheService.put() makes for ThumbnailCacheMode.inContainer.
      // Those writes already fail silently (caught + debugPrint'd) rather
      // than surfacing anywhere — thumbnails still render fine from native
      // generation + the in-memory LRU tier, they're just regenerated every
      // session instead of persisting — but the person chose "inside
      // container" specifically for that persistence, so say so once up
      // front instead of letting it fail invisibly.
      if (mounted &&
          widget.container.readOnly &&
          _resolvedThumbnailCacheMode == ThumbnailCacheMode.inContainer) {
        showAppSnackBar(
          context,
          message:
              'Read-only mount — thumbnails will show but won\'t be saved '
              'inside the container this session.',
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
        space = null; // e.g. Cryptomator vault with no reportable free space
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
        _setStatus('Failed loading folder: ${e.runtimeType}', error: true);
      }
    }
  }

  void _loadArchiveContents(String path) {
    if (_archiveContext == null) return;
    
    // The subPath we pass to archiveContext should be relative to the archive root
    // To calculate this, we take the current fatPath and strip the archive root's fatPath
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
        _setStatus('Failed to read archive: ${e.runtimeType}', error: true);
      }
    }
  }

  void _closeArchive() {
    _archiveContext?.dispose();
    _archiveContext = null;
  }

  // ── Search ────────────────────────────────────────────────────────────────

  void _clearSearch() {
    _searchActive = false;
    _searchQuery = '';
  }

  // ── Navigation ────────────────────────────────────────────────────────────

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
    
    // Check if we're about to leave the archive
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
    
    // Check if we jumped out of the archive
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

  // ── SelectionMixin override ───────────────────────────────────────────────

  @override
  void toggleSelectItem(RawEntry item) {
    super.toggleSelectItem(item);
    if (selectedFolderCount > 0) {
      fetchFolderSizes(widget.container, _currentDirPath);
    }
  }

  // ── Item interaction ──────────────────────────────────────────────────────

  void _handleDirTap(RawEntry entry) {
    _signalActivity();
    if (isSelectionMode) {
      toggleSelectItem(entry);
    } else {
      _enterDirectory(entry);
    }
  }

  Future<void> _handleFileTap(RawEntry entry) async {
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

    // Check if it's an archive we can browse
    if (ArchiveService.isArchive(ext)) {
      if (ArchiveService.isSupported(ext)) {
        await _openArchive(fullPath, entry.name);
      } else {
        _setStatus('Archive format .$ext is not yet supported', error: true);
      }
      return;
    }

    // Check if we are inside an archive
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
            _setStatus('Failed to read file from archive', error: true);
          }
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isLoading = false);
          _setStatus('Failed to extract file: ${e.runtimeType}', error: true);
        }
      }
      return;
    }

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
                'Open As...',
                style: textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'Choose file type to open as',
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
} else if (result == 'open_as') {
  if (!mounted) return;

  final mimeType = await showDialog<String>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Open As'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
  leading: const Icon(Icons.text_fields_rounded),
  title: const Text('Text'),
  onTap: () => Navigator.of(context).pop('text/plain'),
),
ListTile(
  leading: const Icon(Icons.image_outlined),
  title: const Text('Image'),
  onTap: () => Navigator.of(context).pop('image/*'),
),
ListTile(
  leading: const Icon(Icons.ondemand_video_outlined),
  title: const Text('Video'),
  onTap: () => Navigator.of(context).pop('video/*'),
),
ListTile(
  leading: const Icon(Icons.audio_file_outlined),
  title: const Text('Audio'),
  onTap: () => Navigator.of(context).pop('audio/*'),
),
ListTile(
  leading: const Icon(Icons.archive_outlined),
  title: const Text('Archive'),
  onTap: () => Navigator.of(context).pop('application/zip'),
),
ListTile(
  leading: const Icon(Icons.insert_drive_file_outlined),
  title: const Text('Other'),
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
    final sortedItems = _currentItems.where((e) => !e.isDir).toList()
      ..sort(compareItems);
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
      _setStatus('No app found for this file type', error: true);
    }
  } catch (_) {
    if (mounted) _setStatus('Could not open "$cleanName"', error: true);
  }
}

  // ── Vault items ───────────────────────────────────────────────────────────

  Future<void> _addVaultItem(VaultItemType type) async {
    if (_isReadOnly) {
      _setStatus('This container is mounted read-only.', error: true);
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
    // Refresh directory as VaultItems natively exist in the filesystem now
    _loadDirectoryContents(_currentDirPath);
  }

  // ── Clipboard ─────────────────────────────────────────────────────────────

  void _initClipboard({required bool cut}) {
    if (cut && _isReadOnly) {
      _setStatus(
        'This container is mounted read-only — items can\'t be moved from here.',
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
        'This container is mounted read-only — items can\'t be pasted here.',
        error: true,
      );
      return;
    }
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
        'This container is mounted read-only — items can\'t be deleted.',
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
    if (_isReadOnly) {
      _setStatus('This container is mounted read-only.', error: true);
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
      }
    }

    op.addListener(listener);
  }

  Future<void> _importFolderFromDevice() async {
    if (_isReadOnly) {
      _setStatus('This container is mounted read-only.', error: true);
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

  Future<void> _extractArchive() async {
    if (_archiveContext == null) return;
    if (_isReadOnly) {
      _setStatus('This container is mounted read-only.', error: true);
      return;
    }
    
    final archivePath = _pathStack[_archiveContext!.pathStackEntryIndex].fatPath;
    final parentDir = archivePath.contains('/') 
        ? archivePath.substring(0, archivePath.lastIndexOf('/')) 
        : '';
        
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Extract Archive'),
        content: Text('Extract all files to the folder "${parentDir.isEmpty ? 'Root' : parentDir}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Extract')),
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
        _setStatus('Extracted $count files', autoClear: const Duration(seconds: 3));
      }
    } catch (e) {
      if (mounted) {
        _setStatus('Failed to extract: ${e.runtimeType}', error: true);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Add / Sort popup buttons ──────────────────────────────────────────────

  Widget _buildAddPopupButton(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_isReadOnly) {
      return IconButton(
        icon: Icon(
          Icons.lock_outline_rounded,
          color: cs.onSurfaceVariant.withValues(alpha: 0.5),
        ),
        tooltip: 'Read-only — can\'t add items',
        onPressed: () => _setStatus(
          'This container is mounted read-only.',
          error: true,
        ),
      );
    }

    if (_archiveContext != null) {
      return IconButton(
        icon: const Icon(Icons.unarchive_rounded, size: 28),
        tooltip: 'Extract Archive',
        onPressed: _extractArchive,
      );
    }

    return MenuAnchor(
      builder: (context, controller, child) => IconButton(
        icon: const Icon(Icons.add_rounded, size: 28),
        tooltip: 'New item',
        onPressed: () {
          _signalActivity();
          if (controller.isOpen) {
            controller.close();
          } else {
            controller.open();
          }
        },
      ),
      onOpen: () => setState(() => _menuIsOpen = true),
      onClose: () => setState(() => _menuIsOpen = false),
      menuChildren: [
        MenuItemButton(
          leadingIcon: Icon(Icons.create_new_folder_outlined, color: cs.primary),
          child: const Text('New Folder'),
          onPressed: () {
            BrowserDialogs.showCreateFolder(
              context,
              container: widget.container,
              currentDirPath: _currentDirPath,
              onSuccess: () => _loadDirectoryContents(_currentDirPath),
              readOnly: _isReadOnly,
            );
          },
        ),
        MenuItemButton(
          leadingIcon: Icon(Icons.insert_drive_file_outlined, color: cs.primary),
          child: const Text('New Text File'),
          onPressed: () {
            BrowserDialogs.showCreateFile(
              context,
              container: widget.container,
              currentDirPath: _currentDirPath,
              onSuccess: () => _loadDirectoryContents(_currentDirPath),
              readOnly: _isReadOnly,
            );
          },
        ),
        MenuItemButton(
          leadingIcon: Icon(Icons.upload_file_outlined, color: cs.secondary),
          child: const Text('Import Files'),
          onPressed: _importFilesFromDevice,
        ),
        MenuItemButton(
          leadingIcon: Icon(Icons.drive_folder_upload_outlined, color: cs.secondary),
          child: const Text('Import Folder'),
          onPressed: _importFolderFromDevice,
        ),
        const PopupMenuDivider(),
        SubmenuButton(
          leadingIcon: Icon(Icons.lock_rounded, color: cs.primary),
          menuChildren: [
            ...VaultItemType.values.map(
              (type) => MenuItemButton(
                leadingIcon: Icon(
                  vaultIconForExt(type.name) ?? Icons.lock_rounded,
                  color: vaultColorForExt(type.name) ?? cs.primary,
                ),
                child: Text(type.label),
                onPressed: () => _addVaultItem(type),
              ),
            ),
          ],
          child: const Text('Secure Item'),
        ),
      ],
    );
  }
  
  Widget _buildViewTogglePopupButton(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final currentIcon = _layoutMode == BrowserLayoutMode.list
        ? Icons.view_list_rounded
        : _layoutMode == BrowserLayoutMode.compact
            ? Icons.list_rounded
            : Icons.grid_view_rounded;

    return MenuAnchor(
      builder: (context, controller, child) => IconButton(
        icon: Icon(currentIcon),
        tooltip: 'Layout options',
        onPressed: () {
          if (controller.isOpen) {
            controller.close();
          } else {
            controller.open();
          }
        },
      ),
      onOpen: () => setState(() => _menuIsOpen = true),
      onClose: () => setState(() => _menuIsOpen = false),
      menuChildren: [
        for (final (mode, label, icon) in const [
          (BrowserLayoutMode.list, 'Detailed List', Icons.view_list_rounded),
          (BrowserLayoutMode.compact, 'Compact List', Icons.list_rounded),
          (BrowserLayoutMode.grid, 'Gallery Grid', Icons.grid_view_rounded),
        ])
          MenuItemButton(
            leadingIcon: Icon(icon, color: _layoutMode == mode ? cs.primary : cs.onSurfaceVariant),
            trailingIcon: _layoutMode == mode
                ? Icon(Icons.check_rounded, size: 16, color: cs.primary)
                : null,
            onPressed: () async {
              setState(() => _layoutMode = mode);
              try {
                final settings = await AppSettingsService.loadSettings();
                final updatedSettings = settings.copyWith(defaultLayoutMode: mode);
                await AppSettingsService.saveSettings(updatedSettings);
              } catch (e) {
                debugPrint('Failed to save layout mode: $e');
              }
            },
            child: Text(
              label,
              style: TextStyle(
                fontWeight: _layoutMode == mode ? FontWeight.bold : FontWeight.normal,
                color: _layoutMode == mode ? cs.primary : null,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSortPopupButton(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return MenuAnchor(
      builder: (context, controller, child) => IconButton(
        icon: const Icon(Icons.sort_by_alpha_rounded),
        tooltip: 'Sort options',
        onPressed: () {
          if (controller.isOpen) {
            controller.close();
          } else {
            controller.open();
          }
        },
      ),
      onOpen: () => setState(() => _menuIsOpen = true),
      onClose: () => setState(() => _menuIsOpen = false),
      menuChildren: [
        for (final (field, label, icon) in const [
          (SortBy.name, 'Name', Icons.sort_by_alpha_rounded),
          (SortBy.size, 'Size', Icons.data_usage_rounded),
          (SortBy.extension, 'Type', Icons.category_outlined),
          (SortBy.date, 'Date', Icons.schedule_rounded),
        ])
          MenuItemButton(
            leadingIcon: Icon(icon, color: sortBy == field ? cs.primary : cs.onSurfaceVariant),
            trailingIcon: sortBy == field
                ? Icon(
                    sortAscending ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                    size: 16,
                    color: cs.primary,
                  )
                : null,
            onPressed: () => setSort(field),
            child: Text(
              label,
              style: TextStyle(
                fontWeight: sortBy == field ? FontWeight.bold : FontWeight.normal,
                color: sortBy == field ? cs.primary : null,
              ),
            ),
          ),
      ],
    );
  }

  // ── Action bar wiring ─────────────────────────────────────────────────────

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
            tooltip: _searchActive ? 'Close search' : 'Search in this folder',
            onPressed: () => setState(() {
              _searchActive = !_searchActive;
              if (!_searchActive) _searchQuery = '';
            }),
          ),
      FileManagerAction.add: (context) => _buildAddPopupButton(context),
      FileManagerAction.viewToggle: (context) => _buildViewTogglePopupButton(context),
      FileManagerAction.sort: (context) => _buildSortPopupButton(context),
      FileManagerAction.playMedia: (context) => IconButton(
            icon: const Icon(Icons.play_circle_outline_rounded),
            tooltip: 'Play media here',
            onPressed: canPlayMedia ? _startMediaViewerFromCurrentLocation : null,
          ),
    };
  }

  // ── Settings menu (app bar) ───────────────────────────────────────────────
  //
  // The app bar's only action: Filters + a link to the toolbar customize
  // screen. Everything functional (search/add/sort/view/play) lives in the
  // action bar instead.

  Widget _buildSettingsMenuButton(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return MenuAnchor(
      builder: (ctx, controller, child) => IconButton(
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        icon: const Icon(Icons.settings_outlined),
        tooltip: 'Settings',
      ),
      menuChildren: [
        SubmenuButton(
          leadingIcon: Icon(Icons.filter_alt_outlined, color: cs.onSurfaceVariant),
          menuChildren: [
            _buildFilterMenuButton(null, 'All Files', Icons.all_inclusive_rounded, cs, textTheme),
            _buildFilterMenuButton('image', 'Images', Icons.image_outlined, cs, textTheme),
            _buildFilterMenuButton('video', 'Videos', Icons.videocam_outlined, cs, textTheme),
            _buildFilterMenuButton('audio', 'Audio', Icons.audiotrack_rounded, cs, textTheme),
            _buildFilterMenuButton('document', 'Documents', Icons.description_outlined, cs, textTheme),
          ],
          child: const Text('Filters'),
        ),
        const PopupMenuDivider(),
        MenuItemButton(
          leadingIcon: Icon(Icons.tune_rounded, color: cs.onSurfaceVariant),
          onPressed: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FileManagerToolbarSettingsScreen()),
            );
            await _loadToolbarConfig();
          },
          child: const Text('Settings'),
        ),
      ],
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final dirs = _currentItems.where((e) => e.isDir).toList()
      ..sort(compareItems);
    final files = _currentItems.where((e) => !e.isDir).toList()
      ..sort(compareItems);

    final query = _searchQuery.trim().toLowerCase();

    final filteredDirs = (query.isEmpty && _currentFilter == null)
        ? dirs
        : (query.isEmpty
              ? <RawEntry>[]
              : dirs
                    .where(
                      (d) => d.name.toLowerCase().contains(query),
                    )
                    .toList());

    final filteredFiles = files.where((f) {
      final name = f.name;
      if (query.isNotEmpty && !name.toLowerCase().contains(query)) return false;
      return _matchesFilter(name);
    }).toList();

    final cs = Theme.of(context).colorScheme;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final actionBuilders = _buildActionBuilders();
    final showActionBar = !_searchActive;

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
        // Handled manually by BottomSearchBar via MediaQuery.viewInsets, so
        // the search bar's own positioning stays deterministic instead of
        // fighting with Scaffold's automatic resize.
        resizeToAvoidBottomInset: false,
        appBar: _buildAppBar(context, filteredDirs, filteredFiles),
        bottomNavigationBar: (!isLandscape && showActionBar)
            ? FileManagerActionBar(
                axis: Axis.horizontal,
                actions: _toolbarConfig.visible,
                builders: actionBuilders,
              )
            : null,

        // ── Floating activity stack / search bar ────────────────────────
        body: Stack(
          children: [
            Column(
              children: [
                if (_toolbarConfig.showBreadcrumbBar) ...[
                  BreadcrumbBar(stack: _pathStack, onTap: _jumpTo),
                  const Divider(),
                ],
                Expanded(child: _buildBody(filteredDirs, filteredFiles)),
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
                    Align(
                      alignment: Alignment.centerRight,
                      child: FloatingActivityStack(onPaste: _paste),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── App bar ───────────────────────────────────────────────────────────────
  //
  // Deliberately minimal: back button, container name, and one settings
  // menu (Filters + "Customize toolbar"). It never swaps into a search
  // field — see BottomSearchBar for where search actually lives.

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    List<RawEntry> dirs,
    List<RawEntry> files,
  ) {
    final allItems = [...dirs, ...files];
    final cs = Theme.of(context).colorScheme;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final showActionBar = !_searchActive;
    final actionBuilders = _buildActionBuilders();

    if (isSelectionMode) {
      final single = selectedItems.length == 1;
      final singleFile = single && !selectedItems.first.isDir;

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
             _setStatus('Edit secure items to rename them');
             exitSelectionMode();
             return;
          }
        }

        final oldNames = entries.map((e) => e.name).toList();
        final existingNames = allItems.map((e) => e.name).toSet();

        BrowserDialogs.showRename(
          context,
          container: widget.container,
          oldNames: oldNames,
          existingNamesInDir: existingNames,
          currentDirPath: _currentDirPath,
          onSuccess: () => _loadDirectoryContents(_currentDirPath),
          readOnly: _isReadOnly,
        );
        exitSelectionMode();
      }

      Future<void> doOpenWithApp() async {
        final entry = selectedItems.first;
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
      }

      if (!isLandscape) {
        return SelectionAppBar(
          selectedCount: selectedItems.length,
          selectionLabel: sizeLabel,
          singleSelected: single,
          singleFileSelected: singleFile,
          readOnly: _isReadOnly,
          onClose: exitSelectionMode,
          onSelectAll: () => setState(() => selectedItems.addAll(allItems)),
          onRename: doRename,
          onCopy: () => _initClipboard(cut: false),
          onCut: () => _initClipboard(cut: true),
          onExport: _exportSelectedToStorage,
          onDelete: _batchDelete,
          onOpenWithApp: doOpenWithApp,
        );
      }

      // Landscape: one AppBar split into two zones — selection operations
      // on the left, the regular toolbar actions on the right — instead of
      // swapping in a full-width SelectionAppBar that would otherwise
      // cover/replace the toolbar rail entirely.
      final textTheme = Theme.of(context).textTheme;

      return AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          tooltip: 'Clear selection',
          onPressed: exitSelectionMode,
        ),
        titleSpacing: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
              child: Text(
                '${selectedItems.length}',
                style: textTheme.labelLarge?.copyWith(
                  color: cs.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                sizeLabel,
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleSmall,
              ),
            ),
          ],
        ),
        actions: [
          // ── Left zone: selection operations ──────────────────────────
          IconButton(
            icon: Icon(
              Icons.delete_outline_rounded,
              color: _isReadOnly ? cs.onSurfaceVariant.withValues(alpha: 0.5) : cs.error,
            ),
            tooltip: _isReadOnly ? 'Read-only — can\'t delete' : 'Delete',
            onPressed: _batchDelete,
          ),
          IconButton(
            icon: const Icon(Icons.copy_rounded),
            tooltip: 'Copy',
            onPressed: () => _initClipboard(cut: false),
          ),
          IconButton(
            icon: Icon(
              Icons.cut_rounded,
              color: _isReadOnly ? cs.onSurfaceVariant.withValues(alpha: 0.5) : null,
            ),
            tooltip: _isReadOnly ? 'Read-only — can\'t move' : 'Move',
            onPressed: () => _initClipboard(cut: true),
          ),
          IconButton(
            icon: Icon(
              Icons.drive_file_rename_outline_rounded,
              color: _isReadOnly ? cs.onSurfaceVariant.withValues(alpha: 0.5) : null,
            ),
            tooltip: _isReadOnly ? 'Read-only — can\'t rename' : 'Rename',
            onPressed: doRename,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            tooltip: 'More options',
            onSelected: (value) {
              if (value == 'export') _exportSelectedToStorage();
              if (value == 'open_with_app') doOpenWithApp();
              if (value == 'select_all') {
                setState(() => selectedItems.addAll(allItems));
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem<String>(
                value: 'select_all',
                child: Text('Select All'),
              ),
              PopupMenuItem<String>(
                value: 'export',
                child: Row(
                  children: [
                    Icon(
                      Icons.drive_folder_upload_rounded,
                      color: cs.onSurfaceVariant,
                      size: AppIconSize.small,
                    ),
                    const SizedBox(width: 12),
                    const Text('Export to device'),
                  ],
                ),
              ),
              if (singleFile)
                PopupMenuItem<String>(
                  value: 'open_with_app',
                  child: Row(
                    children: [
                      Icon(
                        Icons.open_in_new_rounded,
                        color: cs.onSurfaceVariant,
                        size: AppIconSize.small,
                      ),
                      const SizedBox(width: 12),
                      const Text('Open with App'),
                    ],
                  ),
                ),
            ],
          ),

          // ── Divider between the two zones ────────────────────────────
          const SizedBox(width: 8),
          VerticalDivider(width: 1, indent: 12, endIndent: 12, color: cs.outlineVariant),
          const SizedBox(width: 4),

          // ── Right zone: regular toolbar actions ──────────────────────
          if (showActionBar)
            ..._toolbarConfig.visible.map((action) => actionBuilders[action]!(context)),

          const SizedBox(width: 4),
        ],
      );
    }

    final query = _searchQuery.trim().toLowerCase();
    final isFiltered = query.isNotEmpty || _currentFilter != null;

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
                  widget.container.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_isReadOnly) ...[
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
          if (_toolbarConfig.showStatsBar)
            _buildAppBarStatsSubtitle(
              dirCount: dirs.length,
              fileCount: files.length,
              isFiltered: isFiltered,
            ),
        ],
      ),
      actions: [
        if (isLandscape && showActionBar) ...[
          ..._toolbarConfig.visible.map((action) => actionBuilders[action]!(context)),
        ],
        _buildSettingsMenuButton(context),
      ],
    );
  }

  /// Compact "N folders · N files · free space [· filtered]" line shown
  /// under the container name in the app bar — same information as
  /// [StatsBar], condensed to fit as a title subtitle.
  Widget _buildAppBarStatsSubtitle({
    required int dirCount,
    required int fileCount,
    required bool isFiltered,
  }) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final style = textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant);

    final parts = <String>[
      '$dirCount folder${dirCount == 1 ? '' : 's'}',
      '$fileCount file${fileCount == 1 ? '' : 's'}',
      if (_freeSpace >= 0) '${formatBytes(_freeSpace)} free',
      if (isFiltered) 'filtered',
    ];

    return Text(
      parts.join(' · '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }

  // ── Body ──────────────────────────────────────────────────────────────────

  Widget _buildBody(List<RawEntry> dirs, List<RawEntry> files) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.5));
    }
    if (_currentItems.isEmpty) {
      // FIX (audit, Duplicate Components): was a private _EmptyPlaceholder
      // class reimplementing the same icon/title/message/action pattern
      // AppEmptyState already generalizes (and animates).
      return AppEmptyState(
        icon: Icons.folder_open_rounded,
        title: 'Empty Folder',
        message: 'Use the Add action to create files or import from device.',
        actionLabel: _atRoot ? null : 'Go back',
        actionIcon: Icons.arrow_upward_rounded,
        onAction: _atRoot ? null : _navigateUp,
      );
    }
    if (_searchQuery.trim().isNotEmpty && dirs.isEmpty && files.isEmpty) {
      // FIX (audit, Duplicate Components): was a private _SearchEmptyState
      // class — same consolidation as above.
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
            searchQuery: _searchActive ? _searchQuery.trim().toLowerCase() : null,
          )
        : FileListView(
            dirs: dirs,
            files: files,
            isSelectionMode: isSelectionMode,
            isCompact: _layoutMode == BrowserLayoutMode.compact,
            selectedItems: selectedItems,
            onDirTap: _handleDirTap,
            onFileTap: _handleFileTap,
            onItemLongPress: _handleItemLongPress,
            searchQuery: _searchActive ? _searchQuery.trim().toLowerCase() : null,
          );

    final refreshable = RefreshIndicator(
      onRefresh: () => _loadDirectoryContents(_currentDirPath),
      child: content,
    );

    if (!_isListingTruncated) return refreshable;

    return Column(
      children: [
        const TruncatedBanner(),
        Expanded(child: refreshable),
      ],
    );
  }
}
