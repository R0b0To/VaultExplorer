import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../../models/mounted_container.dart';
import '../../services/vaultexplorer_api.dart';
import '../../utils/format_utils.dart';
import 'browser_dialogs.dart';
import 'media_viewer_screen.dart';
import 'mixins/selection_mixin.dart';
import 'mixins/sort_mixin.dart';
import 'widgets/breadcrumb_bar.dart';
import 'widgets/clipboard_app_bar.dart';
import 'widgets/file_list_view.dart';
import 'widgets/selection_app_bar.dart';

class PathSegment {
  final String label;
  final String fatPath;
  const PathSegment(this.label, this.fatPath);
}

class FileBrowserScreen extends StatefulWidget {
  final MountedContainer container;
  const FileBrowserScreen({Key? key, required this.container})
      : super(key: key);

  @override
  State<FileBrowserScreen> createState() => _FileBrowserScreenState();
}

class _FileBrowserScreenState extends State<FileBrowserScreen>
    with SelectionMixin<FileBrowserScreen>, SortMixin<FileBrowserScreen> {

  // ── Core state ─────────────────────────────────────────────────────────────
  final List<PathSegment> _pathStack = [const PathSegment('Root', '')];
  List<String> _currentItems = [];
  bool _isLoading = false;
  int _freeSpace = 0;

  // ── Clipboard state ────────────────────────────────────────────────────────
  bool _isClipboardMode = false;
  bool _isCutOperation = false;
  List<Map<String, dynamic>> _clipboardSourceItems = [];

  bool get _atRoot => _pathStack.length == 1;
  String get _currentDirPath => _pathStack.last.fatPath;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _freeSpace = widget.container.freeSpace;
    _loadDirectoryContents('');
  }

  // ── Directory loading ──────────────────────────────────────────────────────

  Future<void> _loadDirectoryContents(String path) async {
    setState(() => _isLoading = true);
    try {
      final items = await vaultExplorerApi.listDirectory(widget.container, path);
      final space = await vaultExplorerApi.getSpaceInfo(widget.container);
      if (mounted) {
        setState(() {
          _currentItems = items ?? [];
          if (space != null && space.length > 1) _freeSpace = space[1];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed loading folder: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  // ── Navigation ─────────────────────────────────────────────────────────────

  void _enterDirectory(String rawDirEntry) {
    final name = rawDirEntry.replaceFirst('[DIR] ', '');
    final newPath =
        _currentDirPath.isEmpty ? name : '$_currentDirPath/$name';
    setState(() => _pathStack.add(PathSegment(name, newPath)));
    _loadDirectoryContents(newPath);
  }

  void _navigateUp() {
    if (_atRoot) return;
    setState(() => _pathStack.removeLast());
    _loadDirectoryContents(_currentDirPath);
  }

  void _jumpTo(int index) {
    if (index == _pathStack.length - 1) return;
    setState(() => _pathStack.removeRange(index + 1, _pathStack.length));
    _loadDirectoryContents(_currentDirPath);
  }

  // ── Item tap / long-press ──────────────────────────────────────────────────

  void _handleDirTap(String rawItem) {
    if (isSelectionMode) {
      toggleSelectItem(rawItem);
    } else {
      _enterDirectory(rawItem);
    }
  }

  void _handleFileTap(String rawItem) {
    if (isSelectionMode) {
      toggleSelectItem(rawItem);
      return;
    }
    final cleanName = rawItem.split('|').first;
    final fullPath =
        _currentDirPath.isEmpty ? cleanName : '$_currentDirPath/$cleanName';

    if (_isSupportedMedia(cleanName)) {
      final mediaNames = _currentItems
          .where((f) => !f.startsWith('[DIR]') && !f.startsWith('System:'))
          .map((f) => f.split('|').first)
          .where(_isSupportedMedia)
          .toList();
      final resolvedPaths = mediaNames
          .map((f) => _currentDirPath.isEmpty ? f : '$_currentDirPath/$f')
          .toList();
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MediaViewerScreen(
            container: widget.container,
            mediaFiles: resolvedPaths,
            initialIndex: mediaNames.indexOf(cleanName),
          ),
        ),
      );
    } else {
      _openFileWithApp(cleanName, fullPath);
    }
  }

  void _handleItemLongPress(String rawItem) {
    if (!isSelectionMode) {
      setState(() {
        isSelectionMode = true;
        selectedItems.add(rawItem);
      });
    } else {
      toggleSelectItem(rawItem);
    }
  }

  // ── Media helpers ──────────────────────────────────────────────────────────

  bool _isSupportedMedia(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    return ['jpg', 'jpeg', 'png', 'gif', 'webp',
            'mp4', 'm4v', 'webm', 'mov', 'avi', 'mkv'].contains(ext);
  }

  Future<void> _openFileWithApp(String cleanName, String fullPath) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ok = await vaultExplorerApi.openWithApp(widget.container, fullPath);
      if (!ok && mounted) {
        messenger.showSnackBar(const SnackBar(
          content: Text('No app found that can open this file type'),
        ));
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(
          content: Text('Could not open "$cleanName": $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  // ── Clipboard ──────────────────────────────────────────────────────────────

  void _initClipboard({required bool cut}) {
    final sources = selectedItems.map((item) {
      final isDir = item.startsWith('[DIR] ');
      final name =
          isDir ? item.replaceFirst('[DIR] ', '') : item.split('|').first;
      final path =
          _currentDirPath.isEmpty ? name : '$_currentDirPath/$name';
      return <String, dynamic>{'path': path, 'isDir': isDir};
    }).toList();

    // Merge clipboard + selection reset into one setState.
    setState(() {
      _isClipboardMode = true;
      _isCutOperation = cut;
      _clipboardSourceItems = sources;
      isSelectionMode = false;
      selectedItems.clear();
    });

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(cut
          ? 'Cut ${sources.length} item(s) — navigate and tap Paste'
          : 'Copied ${sources.length} item(s) — navigate and tap Paste'),
      duration: const Duration(seconds: 4),
    ));
  }

  void _cancelClipboard() => setState(() {
        _isClipboardMode = false;
        _clipboardSourceItems.clear();
      });

  /// Recursively copies [srcPath] to [destPath]; handles files and folder trees.
  Future<void> _copyEntryRecursive(
    String srcPath,
    String destPath,
    bool isDir,
    Directory tmpDir,
  ) async {
    if (!isDir) {
      final tempFile = File(
          '${tmpDir.path}/cb_${DateTime.now().microsecondsSinceEpoch}_${srcPath.hashCode}');
      try {
        final ok = await vaultExplorerApi.decryptFile(
            widget.container, srcPath, tempFile.path);
        if (ok) {
          await vaultExplorerApi.writeBackFile(
              widget.container, destPath, tempFile.path);
        }
      } finally {
        if (await tempFile.exists()) await tempFile.delete();
      }
      return;
    }

    // Directory: create dest, then recurse into children.
    await vaultExplorerApi.createDirectory(widget.container, destPath);
    final children =
        await vaultExplorerApi.listDirectory(widget.container, srcPath) ?? [];
    for (final entry in children) {
      if (entry.startsWith('System:')) continue;
      final childIsDir = entry.startsWith('[DIR] ');
      final childName = childIsDir
          ? entry.replaceFirst('[DIR] ', '')
          : entry.split('|').first;
      await _copyEntryRecursive(
        '$srcPath/$childName',
        '$destPath/$childName',
        childIsDir,
        tmpDir,
      );
    }
  }

  Future<void> _pasteClipboard() async {
    setState(() => _isLoading = true);
    final tmpDir = await getTemporaryDirectory();
    try {
      for (final src in _clipboardSourceItems) {
        final srcPath = src['path'] as String;
        final isDir = src['isDir'] as bool;
        final fileName = srcPath.split('/').last;
        final destPath = _currentDirPath.isEmpty
            ? fileName
            : '$_currentDirPath/$fileName';
        if (srcPath == destPath) continue;
        if (_isCutOperation) {
          await vaultExplorerApi.renameFile(
              widget.container, srcPath, destPath);
        } else {
          await _copyEntryRecursive(srcPath, destPath, isDir, tmpDir);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Operation failed: $e'),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      setState(() {
        _isClipboardMode = false;
        _clipboardSourceItems.clear();
        _isLoading = false;
      });
      _loadDirectoryContents(_currentDirPath);
    }
  }

  // ── Import / Export ────────────────────────────────────────────────────────

  Future<void> _exportSelectedToStorage() async {
    final items = selectedItems.map((item) {
      final isDir = item.startsWith('[DIR] ');
      final name =
          isDir ? item.replaceFirst('[DIR] ', '') : item.split('|').first;
      final path =
          _currentDirPath.isEmpty ? name : '$_currentDirPath/$name';
      return <String, dynamic>{'path': path, 'isDir': isDir};
    }).toList();
    if (items.isEmpty) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(
        content: Text('Preparing export for ${items.length} item(s)…')));
    setState(() => _isLoading = true);
    try {
      final count = await vaultExplorerApi.exportSelectedToFolder(
          widget.container, items);
      messenger.showSnackBar(SnackBar(
        content: Text(count > 0
            ? 'Exported $count file(s)'
            : 'Export cancelled or failed'),
        backgroundColor: count > 0 ? const Color(0xFF1A3A2A) : null,
      ));
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
    exitSelectionMode();
  }

  Future<void> _importFilesFromDevice() async {
    setState(() => _isLoading = true);
    try {
      final count = await vaultExplorerApi.importFiles(
          widget.container, _currentDirPath);
      if (count > 0) _loadDirectoryContents(_currentDirPath);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(count > 0
              ? 'Imported $count file${count != 1 ? 's' : ''}'
              : 'No files imported'),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Import failed: $e'),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _importFolderFromDevice() async {
    setState(() => _isLoading = true);
    try {
      final count = await vaultExplorerApi.importFolder(
          widget.container, _currentDirPath);
      if (count > 0) _loadDirectoryContents(_currentDirPath);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(count > 0
              ? 'Imported $count file${count != 1 ? 's' : ''}'
              : 'No files imported'),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Folder import failed: $e'),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Batch delete ───────────────────────────────────────────────────────────

  void _batchDelete() {
    BrowserDialogs.showBatchDelete(
      context,
      toDelete: List<String>.from(selectedItems),
      onConfirmed: (items) async {
        setState(() => _isLoading = true);
        int failCount = 0;
        try {
          for (final item in items) {
            final isDir = item.startsWith('[DIR] ');
            final name = isDir
                ? item.replaceFirst('[DIR] ', '')
                : item.split('|').first;
            final full =
                _currentDirPath.isEmpty ? name : '$_currentDirPath/$name';
            if (!await vaultExplorerApi.deleteFile(widget.container, full)) {
              failCount++;
            }
          }
        } finally {
          exitSelectionMode();
          _loadDirectoryContents(_currentDirPath);
          if (mounted) {
            final successCount = items.length - failCount;
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(failCount == 0
                  ? 'Deleted $successCount item(s)'
                  : 'Deleted $successCount of ${items.length} — $failCount failed'),
              backgroundColor:
                  failCount == 0 ? const Color(0xFF1A3A2A) : Colors.red,
            ));
          }
        }
      },
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final dirs = _currentItems.where((f) => f.startsWith('[DIR]')).toList()
      ..sort(compareItems);
    final files = _currentItems
        .where((f) => !f.startsWith('[DIR]') && !f.startsWith('System:'))
        .toList()
      ..sort(compareItems);

    return Scaffold(
      appBar: _buildAppBar(context),
      body: Column(
        children: [
          if (_pathStack.length > 1)
            BreadcrumbBar(stack: _pathStack, onTap: _jumpTo),
          _StatsBar(
            dirCount: dirs.length,
            fileCount: files.length,
            freeSpaceBytes: _freeSpace,
          ),
          const Divider(),
          Expanded(child: _buildBody(dirs, files)),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (isSelectionMode) {
      final single = selectedItems.length == 1;
      final singleFile = single && !selectedItems.first.startsWith('[DIR] ');
      return SelectionAppBar(
        selectedCount: selectedItems.length,
        singleSelected: single,
        singleFileSelected: singleFile,
        onClose: exitSelectionMode,
        onSelectAll: () => setState(() => selectedItems.addAll(_currentItems)),
        onRename: () {
          final raw = selectedItems.first;
          final isDir = raw.startsWith('[DIR] ');
          final name =
              isDir ? raw.replaceFirst('[DIR] ', '') : raw.split('|').first;
          BrowserDialogs.showRename(
            context,
            container: widget.container,
            oldName: name,
            currentDirPath: _currentDirPath,
            onSuccess: () => _loadDirectoryContents(_currentDirPath),
          );
          exitSelectionMode();
        },
        onCopy: () => _initClipboard(cut: false),
        onCut: () => _initClipboard(cut: true),
        onExport: _exportSelectedToStorage,
        onDelete: _batchDelete,
        onOpenWithApp: () {
          final raw = selectedItems.first;
          final name = raw.split('|').first;
          final path =
              _currentDirPath.isEmpty ? name : '$_currentDirPath/$name';
          vaultExplorerApi.openWithApp(widget.container, path);
          exitSelectionMode();
        },
      );
    }

    if (_isClipboardMode) {
      return ClipboardAppBar(
        isCutOperation: _isCutOperation,
        itemCount: _clipboardSourceItems.length,
        onCancel: _cancelClipboard,
        onPaste: _pasteClipboard,
      );
    }

    // Default navigation bar
    return AppBar(
      leading: _atRoot
          ? null
          : IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: _navigateUp,
            ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.container.displayName,
              style: const TextStyle(fontSize: 14)),
          if (!_atRoot)
            Text(
              _pathStack.skip(1).map((s) => s.label).join(' / '),
              style: TextStyle(
                fontSize: 11,
                color: cs.primary,
                height: 1.3,
              ),
            ),
        ],
      ),
      actions: [
        PopupMenuButton<SortBy>(
          icon: const Icon(Icons.sort),
          tooltip: 'Sort by',
          onSelected: setSort,
          itemBuilder: (_) => [
            buildSortMenuItem(SortBy.name, 'Name'),
            buildSortMenuItem(SortBy.size, 'Size'),
            buildSortMenuItem(SortBy.extension, 'Type'),
          ],
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.add),
          onSelected: (v) {
            switch (v) {
              case 'folder':
                BrowserDialogs.showCreateFolder(
                  context,
                  container: widget.container,
                  currentDirPath: _currentDirPath,
                  onSuccess: () => _loadDirectoryContents(_currentDirPath),
                );
                break;
              case 'file':
                BrowserDialogs.showCreateFile(
                  context,
                  container: widget.container,
                  currentDirPath: _currentDirPath,
                  onSuccess: () => _loadDirectoryContents(_currentDirPath),
                );
                break;
              case 'import':
                _importFilesFromDevice();
                break;
              case 'import_folder':
                _importFolderFromDevice();
                break;
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: 'folder',
              child: ListTile(
                leading: Icon(Icons.create_new_folder),
                title: Text('New Folder'),
              ),
            ),
            PopupMenuItem(
              value: 'file',
              child: ListTile(
                leading: Icon(Icons.insert_drive_file),
                title: Text('New File'),
              ),
            ),
            PopupMenuItem(
              value: 'import',
              child: ListTile(
                leading: Icon(Icons.drive_folder_upload),
                title: Text('Import Files from Device'),
              ),
            ),
            PopupMenuItem(
              value: 'import_folder',
              child: ListTile(
                leading: Icon(Icons.create_new_folder_outlined),
                title: Text('Import Folder from Device'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBody(List<String> dirs, List<String> files) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_currentItems.isEmpty) {
      return _EmptyPlaceholder(onBack: _navigateUp, atRoot: _atRoot);
    }
    return FileListView(
      dirs: dirs,
      files: files,
      isSelectionMode: isSelectionMode,
      selectedItems: selectedItems,
      onDirTap: _handleDirTap,
      onFileTap: _handleFileTap,
      onItemLongPress: _handleItemLongPress,
    );
  }
}

// ── Stats bar ──────────────────────────────────────────────────────────────────

class _StatsBar extends StatelessWidget {
  final int dirCount;
  final int fileCount;
  final int freeSpaceBytes;

  const _StatsBar({
    Key? key,
    required this.dirCount,
    required this.fileCount,
    required this.freeSpaceBytes,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: cs.surface,
      child: Row(
        children: [
          _Chip(
            icon: Icons.folder_outlined,
            label: '$dirCount folder${dirCount != 1 ? 's' : ''}',
          ),
          const SizedBox(width: 14),
          _Chip(
            icon: Icons.insert_drive_file_outlined,
            label: '$fileCount file${fileCount != 1 ? 's' : ''}',
          ),
          const Spacer(),
          _Chip(
            icon: Icons.storage_outlined,
            label: '${formatBytes(freeSpaceBytes)} free',
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Chip({Key? key, required this.icon, required this.label})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 13, color: cs.outline),
      const SizedBox(width: 4),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ]);
  }
}

// ── Empty placeholder ──────────────────────────────────────────────────────────

class _EmptyPlaceholder extends StatelessWidget {
  final VoidCallback onBack;
  final bool atRoot;
  const _EmptyPlaceholder(
      {Key? key, required this.onBack, required this.atRoot})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.folder_open, size: 40, color: cs.outline),
        const SizedBox(height: 12),
        Text('Empty Folder', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        const Text('Tap + to create files or folders.',
            style: TextStyle(color: Colors.grey, fontSize: 11)),
        if (!atRoot) ...[
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back, size: 16),
            label: const Text('Go back'),
          ),
        ],
      ]),
    );
  }
}