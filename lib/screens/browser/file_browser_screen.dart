import 'dart:io';
import 'package:flutter/material.dart';
import '../../models/mounted_container.dart';
import '../../services/cryptbridge_api.dart';
import 'widgets/breadcrumb_bar.dart';
import 'media_viewer_screen.dart';

class PathSegment {
  final String label;
  final String fatPath;
  const PathSegment(this.label, this.fatPath);
}

class FileBrowserScreen extends StatefulWidget {
  final MountedContainer container;
  const FileBrowserScreen({Key? key, required this.container}) : super(key: key);

  @override
  State<FileBrowserScreen> createState() => _FileBrowserScreenState();
}

class _FileBrowserScreenState extends State<FileBrowserScreen> {
  final List<PathSegment> _pathStack = [
    const PathSegment('Root', ''),
  ];

  late List<String> _currentItems = [];
  bool _isLoading = false;
  late int _freeSpace = 0; // Live available space tracks

  // Modern Multi-Selection State
  bool _isSelectionMode = false;
  final Set<String> _selectedItems = {}; // Holds raw file names (e.g., "[DIR] Documents" or "pic.png|12345")

  // Clipboard State (for Cut/Copy/Paste operations)
  bool _isClipboardMode = false;
  bool _isCutOperation = false; // true = Move/Cut, false = Copy
  List<String> _clipboardSourceFiles = []; // Holds absolute paths inside container

  @override
  void initState() {
    super.initState();
    _freeSpace = widget.container.freeSpace;
    _loadDirectoryContents('');
  }

  bool get _atRoot => _pathStack.length == 1;

  // ---------------------------------------------------------------------------
  // Async Directory Loader
  // ---------------------------------------------------------------------------

  Future<void> _loadDirectoryContents(String path) async {
    setState(() {
      _isLoading = true;
    });
    try {
      final items = await CryptBridgeApi.listDirectory(widget.container, path);
      final space = await CryptBridgeApi.getSpaceInfo(widget.container);
      
      if (mounted) {
        setState(() {
          _currentItems = items ?? [];
          if (space != null && space.length > 1) {
            _freeSpace = space[1];
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed loading folder: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

// ---------------------------------------------------------------------------
  // Selection Logic
  // ---------------------------------------------------------------------------

  void _toggleSelectItem(String item) {
    setState(() {
      if (_selectedItems.contains(item)) {
        _selectedItems.remove(item);
        if (_selectedItems.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedItems.add(item);
      }
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedItems.clear();
    });
  }

  // ---------------------------------------------------------------------------
  // Clipboard Logic (Multi Copy / Cut / Paste)
  // ---------------------------------------------------------------------------

  void _initClipboard({required bool cut}) {
    final currentDir = _pathStack.last.fatPath;
    final List<String> sources = [];

    for (final item in _selectedItems) {
      final isDir = item.startsWith('[DIR] ');
      final cleanName = isDir ? item.replaceFirst('[DIR] ', '') : item.split('|').first;
      final fullPath = currentDir.isEmpty ? cleanName : '$currentDir/$cleanName';
      sources.add(fullPath);
    }

    setState(() {
      _isClipboardMode = true;
      _isCutOperation = cut;
      _clipboardSourceFiles = sources;
      _isSelectionMode = false;
      _selectedItems.clear();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(cut 
            ? 'Cut ${sources.length} items. Navigate to target folder & click Paste.' 
            : 'Copied ${sources.length} items. Navigate to target folder & click Paste.'),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _cancelClipboard() {
    setState(() {
      _isClipboardMode = false;
      _clipboardSourceFiles.clear();
    });
  }

  Future<void> _pasteClipboard() async {
    final targetDir = _pathStack.last.fatPath;
    setState(() {
      _isLoading = true;
    });

    try {
      for (final srcPath in _clipboardSourceFiles) {
        final fileName = srcPath.split('/').last;
        final destPath = targetDir.isEmpty ? fileName : '$targetDir/$fileName';

        if (srcPath == destPath) continue; // Skip redundant actions

        if (_isCutOperation) {
          // Direct native move by rewriting FAT headers
          await CryptBridgeApi.renameFile(widget.container, srcPath, destPath);
        } else {
          // Copy operation: extract securely to system RAM cache, then write back
          final tempFile = File('${Directory.systemTemp.path}/cb_copy_temp');
          final success = await CryptBridgeApi.decryptFile(widget.container, srcPath, tempFile.path);
          if (success) {
            await CryptBridgeApi.writeBackFile(widget.container, destPath, tempFile.path);
            if (await tempFile.exists()) {
              await tempFile.delete();
            }
          }
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Operation failed: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() {
        _isClipboardMode = false;
        _clipboardSourceFiles.clear();
        _isLoading = false;
      });
      _loadDirectoryContents(_pathStack.last.fatPath);
    }
  }
  // ---------------------------------------------------------------------------
  // Folder Navigation Handlers
  // ---------------------------------------------------------------------------

  void _enterDirectory(String rawDirEntry) {
    final cleanName = rawDirEntry.replaceFirst('[DIR] ', '');
    final newPath = _pathStack.last.fatPath.isEmpty
        ? cleanName
        : '${_pathStack.last.fatPath}/$cleanName';

    setState(() {
      _pathStack.add(PathSegment(cleanName, newPath));
    });
    _loadDirectoryContents(newPath);
  }

  void _navigateUp() {
    if (_atRoot) return;
    setState(() {
      _pathStack.removeLast();
    });
    _loadDirectoryContents(_pathStack.last.fatPath);
  }

  void _jumpTo(int index) {
    if (index == _pathStack.length - 1) return;
    setState(() {
      _pathStack.removeRange(index + 1, _pathStack.length);
    });
    _loadDirectoryContents(_pathStack.last.fatPath);
  }

  bool _isSupportedMedia(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    return ['jpg', 'jpeg', 'png', 'gif', 'webp', 'mp4', 'm4v', 'webm', 'mov', 'avi', 'mkv'].contains(ext);
  }

  // ---------------------------------------------------------------------------
  // Folder Operations & Decrypt Export / Imports
  // ---------------------------------------------------------------------------

  void _showCreateFolderDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Folder', style: TextStyle(fontSize: 16)),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Folder name'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(context);
                final fullDirPath = _pathStack.last.fatPath.isEmpty ? name : '${_pathStack.last.fatPath}/$name';
                final success = await CryptBridgeApi.createDirectory(widget.container, fullDirPath);
                if (success) {
                  _loadDirectoryContents(_pathStack.last.fatPath);
                }
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showCreateFileDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Text File', style: TextStyle(fontSize: 16)),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'filename.txt'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(context);
                final fullFilePath = _pathStack.last.fatPath.isEmpty ? name : '${_pathStack.last.fatPath}/$name';
                final success = await CryptBridgeApi.createEmptyFile(widget.container, fullFilePath);
                if (success) {
                  _loadDirectoryContents(_pathStack.last.fatPath);
                }
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showRenameDialog(String oldName) {
    final controller = TextEditingController(text: oldName);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename File / Folder', style: TextStyle(fontSize: 16)),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isNotEmpty && newName != oldName) {
                Navigator.pop(context);
                final oldFullPath = _pathStack.last.fatPath.isEmpty ? oldName : '${_pathStack.last.fatPath}/$oldName';
                final newFullPath = _pathStack.last.fatPath.isEmpty ? newName : '${_pathStack.last.fatPath}/$newName';
                final success = await CryptBridgeApi.renameFile(widget.container, oldFullPath, newFullPath);
                if (success) {
                  _loadDirectoryContents(_pathStack.last.fatPath);
                }
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  Future<void> _importFileFromDevice() async {
    final currentDir = _pathStack.last.fatPath;
    setState(() {
      _isLoading = true;
    });

    try {
      final success = await CryptBridgeApi.importFile(widget.container, currentDir);
      if (success) {
        _loadDirectoryContents(currentDir);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import failed: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _exportFileToStorage(String cleanName, String fullPath) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(content: Text('Preparing export for $cleanName…')),
    );

    try {
      final success = await CryptBridgeApi.exportFileToStorage(
        widget.container,
        fullPath,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(success ? 'Successfully exported $cleanName' : 'Export cancelled/failed'),
          backgroundColor: success ? const Color(0xFF1A3A2A) : null,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _batchDelete() async {
    final currentDir = _pathStack.last.fatPath;
    final List<String> toDelete = List.from(_selectedItems);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${toDelete.length} items?', style: const TextStyle(fontSize: 16)),
        content: const Text('These items will be permanently erased from your encrypted volume.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              setState(() {
                _isLoading = true;
              });

              try {
                for (final item in toDelete) {
                  final isDir = item.startsWith('[DIR] ');
                  final cleanName = isDir ? item.replaceFirst('[DIR] ', '') : item.split('|').first;
                  final fullPath = currentDir.isEmpty ? cleanName : '$currentDir/$cleanName';
                  await CryptBridgeApi.deleteFile(widget.container, fullPath);
                }
              } finally {
                _exitSelectionMode();
                _loadDirectoryContents(currentDir);
              }
            },
            child: const Text('Delete All', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Style, Size, and Icon Helpers
  // ---------------------------------------------------------------------------

  String _formatBytes(int bytes) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    double size = bytes.toDouble();
    int suffixIndex = 0;
    while (size >= 1024 && suffixIndex < suffixes.length - 1) {
      size /= 1024;
      suffixIndex++;
    }
    return "${size.toStringAsFixed(size < 10 ? 1 : 0)} ${suffixes[suffixIndex]}";
  }

  IconData _iconFor(String name) {
    final ext = name.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf': return Icons.picture_as_pdf_outlined;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp': return Icons.image_outlined;
      case 'mp4':
      case 'mov':
      case 'avi':
      case 'mkv': return Icons.ondemand_video_outlined;
      case 'mp3':
      case 'flac':
      case 'wav':
      case 'm4a': return Icons.audio_file_outlined;
      case 'txt':
      case 'md':
      case 'csv': return Icons.article_outlined;
      case 'zip':
      case 'gz':
      case 'tar':
      case '7z': return Icons.archive_outlined;
      default: return Icons.insert_drive_file_outlined;
    }
  }

  Color _colorFor(String name) {
    final ext = name.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf': return const Color(0xFFEF5350);
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp': return const Color(0xFF26C6DA);
      case 'mp4':
      case 'mov':
      case 'avi':
      case 'mkv': return const Color(0xFF7E57C2);
      case 'mp3':
      case 'flac':
      case 'wav':
      case 'm4a': return const Color(0xFF66BB6A);
      case 'txt':
      case 'md':
      case 'csv': return const Color(0xFF78909C);
      default: return const Color(0xFF546E7A);
    }
  }

  // ---------------------------------------------------------------------------
  // Contextual Selection AppBar (MiXplorer Style) [5]
  // ---------------------------------------------------------------------------

  AppBar _buildSelectionAppBar(ColorScheme cs) {
    final singleSelected = _selectedItems.length == 1;
    final isSingleFolder = singleSelected && _selectedItems.first.startsWith('[DIR] ');
    final isSingleFile = singleSelected && !isSingleFolder;

    return AppBar(
      backgroundColor: cs.surfaceVariant,
      elevation: 2,
      leading: IconButton(
        icon: const Icon(Icons.close, color: Colors.white),
        onPressed: _exitSelectionMode,
      ),
      title: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          dropdownColor: cs.surface,
          value: 'header',
          icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
          selectedItemBuilder: (BuildContext context) {
            return ['header', 'all', 'none'].map<Widget>((_) {
              return Center(
                child: Text(
                  '${_selectedItems.length} selected',
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                ),
              );
            }).toList();
          },
          items: const [
            DropdownMenuItem(
              value: 'header',
              child: Text('Selection List', style: TextStyle(fontSize: 11, color: Colors.grey)),
            ),
            DropdownMenuItem(
              value: 'all',
              child: Text('Select All', style: TextStyle(fontSize: 13)),
            ),
            DropdownMenuItem(
              value: 'none',
              child: Text('Clear Selection', style: TextStyle(fontSize: 13)),
            ),
          ],
          onChanged: (val) {
            if (val == 'all') {
              setState(() {
                _selectedItems.addAll(_currentItems);
              });
            } else if (val == 'none') {
              _exitSelectionMode();
            }
          },
        ),
      ),
      actions: [
        if (singleSelected)
          IconButton(
            icon: const Icon(Icons.edit_outlined, color: Colors.white),
            tooltip: 'Rename',
            onPressed: () {
              final rawName = _selectedItems.first;
              final isDir = rawName.startsWith('[DIR] ');
              final cleanName = isDir ? rawName.replaceFirst('[DIR] ', '') : rawName.split('|').first;
              _showRenameDialog(cleanName);
              _exitSelectionMode();
            },
          ),
        IconButton(
          icon: const Icon(Icons.copy_outlined, color: Colors.white),
          tooltip: 'Copy',
          onPressed: () => _initClipboard(cut: false),
        ),
        IconButton(
          icon: const Icon(Icons.cut_outlined, color: Colors.white),
          tooltip: 'Cut (Move)',
          onPressed: () => _initClipboard(cut: true),
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline, color: Color(0xFFEF5350)),
          tooltip: 'Delete',
          onPressed: _batchDelete,
        ),
        
        // Context-aware Three-Dot Popup Menu for Single Files [5]
        if (isSingleFile)
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (val) {
              final rawName = _selectedItems.first;
              final cleanName = rawName.split('|').first;
              final path = _pathStack.last.fatPath.isEmpty 
                  ? cleanName 
                  : '${_pathStack.last.fatPath}/$cleanName';

              if (val == 'open_with') {
                CryptBridgeApi.openWithApp(widget.container, path); // Safe streaming launch [5]
                _exitSelectionMode();
              } else if (val == 'export') {
                _exportFileToStorage(cleanName, path); // Export File dialog [5]
                _exitSelectionMode();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'open_with',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.open_in_new, size: 18),
                  title: Text('Open with App', style: TextStyle(fontSize: 13)),
                ),
              ),
              const PopupMenuItem(
                value: 'export',
                // Updated title to standard folder exports [5]
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.drive_folder_upload_outlined, size: 18),
                  title: Text('Export File...', style: TextStyle(fontSize: 13)),
                ),
              ),
            ],
          ),
        const SizedBox(width: 8),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Contextual Clipboard Paste AppBar [5]
  // ---------------------------------------------------------------------------

  AppBar _buildClipboardAppBar(ColorScheme cs) {
    return AppBar(
      backgroundColor: cs.primaryContainer,
      elevation: 2,
      leading: IconButton(
        icon: const Icon(Icons.close, color: Colors.white),
        tooltip: 'Cancel operation',
        onPressed: _cancelClipboard,
      ),
      title: Text(
        _isCutOperation
            ? 'Moving ${_clipboardSourceFiles.length} item(s)'
            : 'Copying ${_clipboardSourceFiles.length} item(s)',
        style: TextStyle(
          color: cs.onPrimaryContainer,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      actions: [
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: cs.primary,
            foregroundColor: cs.onPrimary,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            padding: const EdgeInsets.symmetric(horizontal: 12),
          ),
          onPressed: _pasteClipboard,
          icon: const Icon(Icons.paste, size: 14),
          label: const Text(
            'Paste Here',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(width: 12),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Build Method
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dirs = _currentItems.where((f) => f.startsWith('[DIR]')).toList();
    final files = _currentItems.where((f) => !f.startsWith('[DIR]') && !f.startsWith('System:')).toList();

    // Dynamically swaps the AppBar state [5]
    final PreferredSizeWidget activeAppBar = _isSelectionMode
        ? _buildSelectionAppBar(cs)
        : _isClipboardMode
            ? _buildClipboardAppBar(cs)
            : AppBar(
                leading: _atRoot
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.arrow_back),
                        onPressed: _navigateUp,
                      ),
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.container.displayName, style: const TextStyle(fontSize: 14)),
                    if (!_atRoot)
                      Text(
                        _pathStack.skip(1).map((s) => s.label).join(' / '),
                        style: TextStyle(fontSize: 11, color: cs.primary, height: 1.3),
                      ),
                  ],
                ),
                actions: [
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.add),
                    onSelected: (value) {
                      if (value == 'folder') {
                        _showCreateFolderDialog();
                      } else if (value == 'file') {
                        _showCreateFileDialog();
                      } else if (value == 'import') {
                        _importFileFromDevice(); // Trigger device memory import picker [5]
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'folder', child: ListTile(leading: Icon(Icons.create_new_folder), title: Text('New Folder'))),
                      const PopupMenuItem(value: 'file', child: ListTile(leading: Icon(Icons.insert_drive_file), title: Text('New File'))),
                      const PopupMenuItem(value: 'import', child: ListTile(leading: Icon(Icons.drive_folder_upload), title: Text('Import File from Device'))),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(4)),
                      child: Text(
                        'VOL ${widget.container.volId}',
                        style: TextStyle(color: cs.primary, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5),
                      ),
                    ),
                  ),
                ],
              );

    return Scaffold(
      appBar: activeAppBar,
      body: Column(
        children: [
          if (_pathStack.length > 1) BreadcrumbBar(stack: _pathStack, onTap: _jumpTo),
          _StatsBar(dirCount: dirs.length, fileCount: files.length, freeSpaceBytes: _freeSpace), // Live space tracker
          const Divider(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : _currentItems.isEmpty
                    ? _EmptyPlaceholder(onBack: _navigateUp, atRoot: _atRoot)
                    : ListView.builder(
                        itemCount: dirs.length + files.length,
                        itemBuilder: (_, index) {
                          final isDir = index < dirs.length;
                          final rawItem = isDir ? dirs[index] : files[index - dirs.length];
                          
                          String cleanName;
                          int fileSize = 0;
                          if (isDir) {
                            cleanName = rawItem.replaceFirst('[DIR] ', '');
                          } else {
                            final parts = rawItem.split('|');
                            cleanName = parts.first;
                            fileSize = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
                          }
                          
                          final isSelected = _selectedItems.contains(rawItem);

                          return Container(
                            color: isSelected ? cs.primaryContainer.withOpacity(0.35) : Colors.transparent,
                            child: ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                              leading: Icon(
                                isDir ? Icons.folder : _iconFor(cleanName),
                                size: 20,
                                color: isDir ? const Color(0xFFFFA726) : _colorFor(cleanName),
                              ),
                              title: Text(cleanName, style: Theme.of(context).textTheme.bodyMedium),
                              subtitle: isDir ? null : Text(_formatBytes(fileSize), style: const TextStyle(fontSize: 11, color: Colors.grey)),
                              trailing: _isSelectionMode
                                  ? (isSelected 
                                      ? Icon(Icons.check_circle, size: 18, color: cs.primary) 
                                      : Icon(Icons.radio_button_unchecked, size: 18, color: cs.outline))
                                  : null, 
                              onTap: () {
                                if (_isSelectionMode) {
                                  _toggleSelectItem(rawItem);
                                } else {
                                  if (isDir) {
                                    _enterDirectory(rawItem);
                                  } else {
                                    if (_isSupportedMedia(cleanName)) {
                                      final mediaList = files.map((f) => f.split('|').first).where((f) => _isSupportedMedia(f)).toList();
                                      final targetIndex = mediaList.indexOf(cleanName);

                                      final resolvedMediaList = mediaList.map((f) {
                                        return _pathStack.last.fatPath.isEmpty ? f : '${_pathStack.last.fatPath}/$f';
                                      }).toList();

                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => MediaViewerScreen(
                                            container: widget.container,
                                            mediaFiles: resolvedMediaList,
                                            initialIndex: targetIndex,
                                          ),
                                        ),
                                      );
                                    } else {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('Long-press "$cleanName" to select and trigger Open-with options.'),
                                          duration: const Duration(seconds: 2),
                                        ),
                                      );
                                    }
                                  }
                                }
                              },
                              onLongPress: () {
                                if (!_isSelectionMode) {
                                  setState(() {
                                    _isSelectionMode = true;
                                    _selectedItems.add(rawItem);
                                  });
                                } else {
                                  _toggleSelectItem(rawItem);
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
  final int freeSpaceBytes; // Added

  const _StatsBar({
    Key? key,
    required this.dirCount,
    required this.fileCount,
    required this.freeSpaceBytes, // Added
  }) : super(key: key);

  String _formatBytes(int bytes) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    double size = bytes.toDouble();
    int suffixIndex = 0;
    while (size >= 1024 && suffixIndex < suffixes.length - 1) {
      size /= 1024;
      suffixIndex++;
    }
    return "${size.toStringAsFixed(size < 10 ? 1 : 0)} ${suffixes[suffixIndex]}";
  }

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
          // Live, dynamic available storage space label inside the file manager stats bar [5]
          _Chip(icon: Icons.storage_outlined, label: '${_formatBytes(freeSpaceBytes)} free'),
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: cs.outline),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.folder_open, size: 40, color: cs.outline),
          const SizedBox(height: 12),
          Text('Empty Folder', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          const Text('Tap the + icon in the top right to create files or folders.', style: TextStyle(color: Colors.grey, fontSize: 11)),
          if (!atRoot) ...[
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back, size: 16),
              label: const Text('Go back'),
            ),
          ],
        ],
      ),
    );
  }
}