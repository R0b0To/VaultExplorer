import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../../models/mounted_container.dart';
import '../../services/vaultexplorer_api.dart';
import '../../utils/format_utils.dart';
import 'widgets/breadcrumb_bar.dart';
import 'media_viewer_screen.dart';

class PathSegment {
  final String label;
  final String fatPath;
  const PathSegment(this.label, this.fatPath);
}

enum _SortBy { name, size, extension }

class ClipboardItem {
  final String path;
  final bool isDir;
  ClipboardItem(this.path, this.isDir);
}

class BrowserItem {
  final String raw;
  final String name;
  final bool isDir;
  final int size;
  final String extension;

  BrowserItem({
    required this.raw,
    required this.name,
    required this.isDir,
    required this.size,
    required this.extension,
  });

  factory BrowserItem.parse(String raw) {
    if (raw.startsWith('[DIR] ')) {
      final name = raw.replaceFirst('[DIR] ', '');
      return BrowserItem(
        raw: raw,
        name: name,
        isDir: true,
        size: 0,
        extension: '',
      );
    } else {
      final parts = raw.split('|');
      final name = parts.first;
      final size = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
      final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
      return BrowserItem(
        raw: raw,
        name: name,
        isDir: false,
        size: size,
        extension: ext,
      );
    }
  }
}

class FileBrowserScreen extends StatefulWidget {
  final MountedContainer container;
  const FileBrowserScreen({Key? key, required this.container}) : super(key: key);

  @override
  State<FileBrowserScreen> createState() => _FileBrowserScreenState();
}

class _FileBrowserScreenState extends State<FileBrowserScreen> {
  final List<PathSegment> _pathStack = [const PathSegment('Root', '')];

  List<BrowserItem> _cachedDirs = [];
  List<BrowserItem> _cachedFiles = [];
  List<BrowserItem> _sortedDirs = [];
  List<BrowserItem> _sortedFiles = [];

  bool _isLoading = false;
  int _freeSpace = 0;

  bool _isSelectionMode = false;
  final Set<String> _selectedItems = {};

  bool _isClipboardMode = false;
  bool _isCutOperation = false;
  List<ClipboardItem> _clipboardItems = [];

  _SortBy _sortBy = _SortBy.name;
  bool _sortAscending = true;

  @override
  void initState() {
    super.initState();
    _freeSpace = widget.container.freeSpace;
    _loadDirectoryContents('');
  }

  bool get _atRoot => _pathStack.length == 1;

  Future<void> _loadDirectoryContents(String path) async {
    setState(() => _isLoading = true);
    try {
      final items = await vaultExplorerApi.listDirectory(widget.container, path);
      final space = await vaultExplorerApi.getSpaceInfo(widget.container);
      
      final parsedDirs = <BrowserItem>[];
      final parsedFiles = <BrowserItem>[];

      if (items != null) {
        for (final raw in items) {
          if (raw.startsWith('System:')) continue;
          final parsed = BrowserItem.parse(raw);
          if (parsed.isDir) {
            parsedDirs.add(parsed);
          } else {
            parsedFiles.add(parsed);
          }
        }
      }

      if (mounted) {
        setState(() {
          _cachedDirs = parsedDirs;
          _cachedFiles = parsedFiles;
          if (space != null && space.length > 1) _freeSpace = space[1];
          _isLoading = false;
        });
        _sortCachedItems();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed loading folder: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _sortCachedItems() {
    int compare(BrowserItem a, BrowserItem b) {
      int res;
      switch (_sortBy) {
        case _SortBy.name:
          res = a.name.toLowerCase().compareTo(b.name.toLowerCase());
          break;
        case _SortBy.size:
          res = a.size.compareTo(b.size);
          break;
        case _SortBy.extension:
          res = a.extension.compareTo(b.extension);
          if (res == 0) res = a.name.toLowerCase().compareTo(b.name.toLowerCase());
          break;
      }
      return _sortAscending ? res : -res;
    }

    setState(() {
      _sortedDirs = List.from(_cachedDirs)..sort(compare);
      _sortedFiles = List.from(_cachedFiles)..sort(compare);
    });
  }

  void _setSort(_SortBy by) {
    if (_sortBy == by) {
      _sortAscending = !_sortAscending;
    } else {
      _sortBy = by;
      _sortAscending = true;
    }
    _sortCachedItems();
  }

  void _toggleSelectItem(String item) => setState(() {
        if (_selectedItems.contains(item)) {
          _selectedItems.remove(item);
          if (_selectedItems.isEmpty) _isSelectionMode = false;
        } else {
          _selectedItems.add(item);
        }
      });

  void _exitSelectionMode() => setState(() {
        _isSelectionMode = false;
        _selectedItems.clear();
      });

  void _initClipboard({required bool cut}) {
    final currentDir = _pathStack.last.fatPath;
    final items = <ClipboardItem>[];
    for (final item in _selectedItems) {
      final isDir = item.startsWith('[DIR] ');
      final name = isDir ? item.replaceFirst('[DIR] ', '') : item.split('|').first;
      final fullPath = currentDir.isEmpty ? name : '$currentDir/$name';
      items.add(ClipboardItem(fullPath, isDir));
    }
    setState(() {
      _isClipboardMode = true;
      _isCutOperation = cut;
      _clipboardItems = items;
      _isSelectionMode = false;
      _selectedItems.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(cut
          ? 'Cut ${items.length} item(s) — navigate and tap Paste'
          : 'Copied ${items.length} item(s) — navigate and tap Paste'),
    ));
  }

  void _cancelClipboard() => setState(() {
        _isClipboardMode = false;
        _clipboardItems.clear();
      });

  Future<void> _pasteClipboard() async {
    final targetDir = _pathStack.last.fatPath;
    setState(() => _isLoading = true);
    final tmpDir = await getTemporaryDirectory();

    try {
      for (final item in _clipboardItems) {
        final fileName = item.path.split('/').last;
        final destPath = targetDir.isEmpty ? fileName : '$targetDir/$fileName';
        if (item.path == destPath) continue;

        if (_isCutOperation) {
          await vaultExplorerApi.renameFile(widget.container, item.path, destPath);
        } else {
          await _copyRecursive(item.path, destPath, item.isDir, tmpDir);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Clipboard error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() {
        _isClipboardMode = false;
        _clipboardItems.clear();
        _isLoading = false;
      });
      _loadDirectoryContents(_pathStack.last.fatPath);
    }
  }

  Future<void> _copyRecursive(String src, String dest, bool isDir, Directory tmp) async {
    if (isDir) {
      await vaultExplorerApi.createDirectory(widget.container, dest);
      final list = await vaultExplorerApi.listDirectory(widget.container, src);
      if (list != null) {
        for (final child in list) {
          if (child.startsWith('System:')) continue;
          final childIsDir = child.startsWith('[DIR] ');
          final childName = childIsDir ? child.replaceFirst('[DIR] ', '') : child.split('|').first;
          await _copyRecursive('$src/$childName', '$dest/$childName', childIsDir, tmp);
        }
      }
    } else {
      final tempFile = File('${tmp.path}/cb_copy_${DateTime.now().microsecondsSinceEpoch}_${src.hashCode}');
      try {
        final ok = await vaultExplorerApi.decryptFile(widget.container, src, tempFile.path);
        if (ok) {
          await vaultExplorerApi.writeBackFile(widget.container, dest, tempFile.path);
        }
      } finally {
        if (await tempFile.exists()) await tempFile.delete();
      }
    }
  }

  void _enterDirectory(String rawDirEntry) {
    final name = rawDirEntry.replaceFirst('[DIR] ', '');
    final newPath = _pathStack.last.fatPath.isEmpty ? name : '${_pathStack.last.fatPath}/$name';
    setState(() => _pathStack.add(PathSegment(name, newPath)));
    _loadDirectoryContents(newPath);
  }

  void _navigateUp() {
    if (_atRoot) return;
    setState(() => _pathStack.removeLast());
    _loadDirectoryContents(_pathStack.last.fatPath);
  }

  void _jumpTo(int index) {
    if (index == _pathStack.length - 1) return;
    setState(() => _pathStack.removeRange(index + 1, _pathStack.length));
    _loadDirectoryContents(_pathStack.last.fatPath);
  }

  bool _isSupportedMedia(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    return ['jpg','jpeg','png','gif','webp','mp4','m4v','webm','mov','avi','mkv'].contains(ext);
  }

  Future<void> _openFileWithApp(String cleanName, String fullPath) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ok = await vaultExplorerApi.openWithApp(widget.container, fullPath);
      if (!ok && mounted) {
        messenger.showSnackBar(const SnackBar(content: Text('No app found to open this file')));
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(
          content: Text('Could not open file: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  void _showCreateFolderDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('New Folder'),
        content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'Folder name'), autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              final name = ctrl.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(context);
              final full = _pathStack.last.fatPath.isEmpty ? name : '${_pathStack.last.fatPath}/$name';
              if (await vaultExplorerApi.createDirectory(widget.container, full)) {
                _loadDirectoryContents(_pathStack.last.fatPath);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showCreateFileDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('New Text File'),
        content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'filename.txt'), autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              final name = ctrl.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(context);
              final full = _pathStack.last.fatPath.isEmpty ? name : '${_pathStack.last.fatPath}/$name';
              if (await vaultExplorerApi.createEmptyFile(widget.container, full)) {
                _loadDirectoryContents(_pathStack.last.fatPath);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showRenameDialog(String oldName) {
    final ctrl = TextEditingController(text: oldName);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              final newName = ctrl.text.trim();
              if (newName.isEmpty || newName == oldName) return;
              Navigator.pop(context);
              final dir = _pathStack.last.fatPath;
              final oldFull = dir.isEmpty ? oldName : '$dir/$oldName';
              final newFull = dir.isEmpty ? newName : '$dir/$newName';
              if (await vaultExplorerApi.renameFile(widget.container, oldFull, newFull)) {
                _loadDirectoryContents(dir);
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportSelectedToStorage() async {
    final currentDir = _pathStack.last.fatPath;
    final items = _selectedItems.map((item) {
      final isDir = item.startsWith('[DIR] ');
      final name = isDir ? item.replaceFirst('[DIR] ', '') : item.split('|').first;
      final path = currentDir.isEmpty ? name : '$currentDir/$name';
      return {'path': path, 'isDir': isDir};
    }).toList();

    if (items.isEmpty) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(content: Text('Preparing export for ${items.length} item(s)…')));
    setState(() => _isLoading = true);
    try {
      final count = await vaultExplorerApi.exportSelectedToFolder(widget.container, items);
      messenger.showSnackBar(SnackBar(
        content: Text(count > 0 ? 'Exported $count file(s)' : 'Export cancelled or failed'),
        backgroundColor: count > 0 ? const Color(0xFF1A3A2A) : null,
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
    _exitSelectionMode();
  }

  Future<void> _importFilesFromDevice() async {
    final currentDir = _pathStack.last.fatPath;
    setState(() => _isLoading = true);
    try {
      final count = await vaultExplorerApi.importFiles(widget.container, currentDir);
      if (count > 0) _loadDirectoryContents(currentDir);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(count > 0 ? 'Imported $count files' : 'No files imported')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Import failed: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _importFolderFromDevice() async {
    final currentDir = _pathStack.last.fatPath;
    setState(() => _isLoading = true);
    try {
      final count = await vaultExplorerApi.importFolder(widget.container, currentDir);
      if (count > 0) _loadDirectoryContents(currentDir);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(count > 0 ? 'Imported folder content' : 'Import failed')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Folder import failed: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _batchDelete() async {
    final currentDir = _pathStack.last.fatPath;
    final toDelete = List<String>.from(_selectedItems);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Delete ${toDelete.length} item(s)?'),
        content: const Text('These items will be permanently erased.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              setState(() => _isLoading = true);
              try {
                int failed = 0;
                for (final item in toDelete) {
                  final isDir = item.startsWith('[DIR] ');
                  final name = isDir ? item.replaceFirst('[DIR] ', '') : item.split('|').first;
                  final full = currentDir.isEmpty ? name : '$currentDir/$name';
                  final ok = await vaultExplorerApi.deleteFile(widget.container, full);
                  if (!ok) failed++;
                }
                if (failed > 0 && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed deleting $failed items'), backgroundColor: Colors.red));
                }
              } finally {
                _exitSelectionMode();
                _loadDirectoryContents(currentDir);
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  PopupMenuItem<_SortBy> _sortMenuItem(_SortBy value, String label) {
    final cs = Theme.of(context).colorScheme;
    final isActive = _sortBy == value;
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(isActive ? (_sortAscending ? Icons.arrow_upward : Icons.arrow_downward) : Icons.sort, size: 16, color: isActive ? cs.primary : null),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(fontWeight: isActive ? FontWeight.w700 : FontWeight.normal)),
        ],
      ),
    );
  }

  AppBar _buildSelectionAppBar(ColorScheme cs) {
    final single     = _selectedItems.length == 1;
    final singleDir  = single && _selectedItems.first.startsWith('[DIR] ');
    final singleFile = single && !singleDir;

    return AppBar(
      backgroundColor: cs.surface,
      leading: IconButton(icon: const Icon(Icons.close), onPressed: _exitSelectionMode),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(20)),
            child: Text('${_selectedItems.length}', style: TextStyle(color: cs.primary, fontSize: 13, fontWeight: FontWeight.w700)),
          ),
          const Spacer(),
          TextButton(
            onPressed: () => setState(() {
              _selectedItems.addAll(_sortedDirs.map((d) => d.raw));
              _selectedItems.addAll(_sortedFiles.map((f) => f.raw));
            }),
            child: const Text('All'),
          ),
        ],
      ),
      actions: [
        if (single)
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () {
              final raw = _selectedItems.first;
              final isDir = raw.startsWith('[DIR] ');
              final name = isDir ? raw.replaceFirst('[DIR] ', '') : raw.split('|').first;
              _showRenameDialog(name);
              _exitSelectionMode();
            },
          ),
        IconButton(icon: const Icon(Icons.copy_outlined), onPressed: () => _initClipboard(cut: false)),
        IconButton(icon: const Icon(Icons.cut_outlined), onPressed: () => _initClipboard(cut: true)),
        IconButton(icon: const Icon(Icons.drive_folder_upload_outlined), onPressed: _exportSelectedToStorage),
        IconButton(icon: Icon(Icons.delete_outline, color: cs.error), onPressed: _batchDelete),
        if (singleFile)
          IconButton(
            icon: const Icon(Icons.open_in_new),
            onPressed: () {
              final raw  = _selectedItems.first;
              final name = raw.split('|').first;
              final path = _pathStack.last.fatPath.isEmpty ? name : '${_pathStack.last.fatPath}/$name';
              _openFileWithApp(name, path);
              _exitSelectionMode();
            },
          ),
      ],
    );
  }

  AppBar _buildClipboardAppBar(ColorScheme cs) => AppBar(
        backgroundColor: cs.surface,
        leading: IconButton(icon: const Icon(Icons.close), onPressed: _cancelClipboard),
        title: Row(
          children: [
            Icon(_isCutOperation ? Icons.cut : Icons.copy, size: 16, color: cs.primary),
            const SizedBox(width: 8),
            Text(_isCutOperation ? 'Moving ${_clipboardItems.length} items' : 'Copying ${_clipboardItems.length} items', style: const TextStyle(fontSize: 13)),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: _pasteClipboard,
            icon: const Icon(Icons.paste, size: 16),
            label: const Text('Paste Here'),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final PreferredSizeWidget activeAppBar = _isSelectionMode
        ? _buildSelectionAppBar(cs)
        : _isClipboardMode
            ? _buildClipboardAppBar(cs)
            : AppBar(
                leading: _atRoot ? null : IconButton(icon: const Icon(Icons.arrow_back), onPressed: _navigateUp),
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.container.displayName, style: const TextStyle(fontSize: 14)),
                    if (!_atRoot)
                      Text(_pathStack.skip(1).map((s) => s.label).join(' / '), style: TextStyle(fontSize: 11, color: cs.primary)),
                  ],
                ),
                actions: [
                  PopupMenuButton<_SortBy>(
                    icon: const Icon(Icons.sort),
                    onSelected: _setSort,
                    itemBuilder: (_) => [
                      _sortMenuItem(_SortBy.name, 'Name'),
                      _sortMenuItem(_SortBy.size, 'Size'),
                      _sortMenuItem(_SortBy.extension, 'Type'),
                    ],
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.add),
                    onSelected: (v) {
                      if (v == 'folder') _showCreateFolderDialog();
                      else if (v == 'file') _showCreateFileDialog();
                      else if (v == 'import') _importFilesFromDevice();
                      else if (v == 'import_folder') _importFolderFromDevice();
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'folder', child: ListTile(leading: Icon(Icons.create_new_folder), title: Text('New Folder'))),
                      PopupMenuItem(value: 'file', child: ListTile(leading: Icon(Icons.insert_drive_file), title: Text('New File'))),
                      PopupMenuItem(value: 'import', child: ListTile(leading: Icon(Icons.drive_folder_upload), title: Text('Import Files'))),
                      PopupMenuItem(value: 'import_folder', child: ListTile(leading: Icon(Icons.create_new_folder_outlined), title: Text('Import Folder'))),
                    ],
                  ),
                ],
              );

    final totalCount = _sortedDirs.length + _sortedFiles.length;

    return Scaffold(
      appBar: activeAppBar,
      body: Column(
        children: [
          if (_pathStack.length > 1) BreadcrumbBar(stack: _pathStack, onTap: _jumpTo),
          _StatsBar(dirCount: _sortedDirs.length, fileCount: _sortedFiles.length, freeSpaceBytes: _freeSpace),
          const Divider(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : totalCount == 0
                    ? _EmptyPlaceholder(onBack: _navigateUp, atRoot: _atRoot)
                    : ListView.builder(
                        itemCount: totalCount,
                        itemBuilder: (_, index) {
                          final isDir  = index < _sortedDirs.length;
                          final item = isDir ? _sortedDirs[index] : _sortedFiles[index - _sortedDirs.length];
                          final isSelected = _selectedItems.contains(item.raw);

                          return Container(
                            color: isSelected ? cs.primaryContainer.withOpacity(0.35) : Colors.transparent,
                            child: ListTile(
                              dense: true,
                              leading: Icon(
                                isDir ? Icons.folder : FormatUtils.iconForFile(item.name),
                                size: 20,
                                color: isDir ? const Color(0xFFFFA726) : FormatUtils.colorForFile(item.name),
                              ),
                              title: Text(item.name, style: Theme.of(context).textTheme.bodyMedium),
                              subtitle: isDir ? null : Text(FormatUtils.formatBytes(item.size), style: const TextStyle(fontSize: 11, color: Colors.grey)),
                              trailing: _isSelectionMode
                                  ? (isSelected ? Icon(Icons.check_circle, size: 18, color: cs.primary) : Icon(Icons.radio_button_unchecked, size: 18, color: cs.outline))
                                  : null,
                              onTap: () {
                                if (_isSelectionMode) {
                                  _toggleSelectItem(item.raw);
                                  return;
                                }
                                if (isDir) {
                                  _enterDirectory(item.raw);
                                  return;
                                }

                                final dir = _pathStack.last.fatPath;
                                final fullPath = dir.isEmpty ? item.name : '$dir/${item.name}';

                                if (_isSupportedMedia(item.name)) {
                                  final mediaList = _sortedFiles.map((f) => f.name).where(_isSupportedMedia).toList();
                                  final resolved = mediaList.map((f) => dir.isEmpty ? f : '$dir/$f').toList();
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => MediaViewerScreen(
                                        container: widget.container,
                                        mediaFiles: resolved,
                                        initialIndex: mediaList.indexOf(item.name),
                                      ),
                                    ),
                                  );
                                } else {
                                  _openFileWithApp(item.name, fullPath);
                                }
                              },
                              onLongPress: () {
                                if (!_isSelectionMode) {
                                  setState(() {
                                    _isSelectionMode = true;
                                    _selectedItems.add(item.raw);
                                  });
                                } else {
                                  _toggleSelectItem(item.raw);
                                }
                              },
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

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
          _Chip(icon: Icons.folder_outlined, label: '$dirCount folder${dirCount != 1 ? 's' : ''}'),
          const SizedBox(width: 14),
          _Chip(icon: Icons.insert_drive_file_outlined, label: '$fileCount file${fileCount != 1 ? 's' : ''}'),
          const Spacer(),
          _Chip(icon: Icons.storage_outlined, label: '${FormatUtils.formatBytes(freeSpaceBytes)} free'),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Chip({Key? key, required this.icon, required this.label}) : super(key: key);
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

class _EmptyPlaceholder extends StatelessWidget {
  final VoidCallback onBack;
  final bool atRoot;
  const _EmptyPlaceholder({Key? key, required this.onBack, required this.atRoot}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.folder_open, size: 40, color: cs.outline),
        const SizedBox(height: 12),
        Text('Empty Folder', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        const Text('Tap + to create files or folders.', style: TextStyle(color: Colors.grey, fontSize: 11)),
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