import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';

/// Shows a vault image picker rooted at the Markdown file's directory.
///
/// The returned path is relative to the vault root. Call
/// [relativeMarkdownImagePath] to turn it into a Markdown-relative link.
Future<String?> showMarkdownImagePicker({
  required BuildContext context,
  required MountedContainer container,
  required String markdownFilePath,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _MarkdownImagePickerDialog(
      container: container,
      initialDirectory: _parentDirectory(markdownFilePath),
    ),
  );
}

/// Returns an image path relative to the directory containing [markdownPath].
String relativeMarkdownImagePath(String markdownPath, String imagePath) {
  final markdownDirectory = p.posix.dirname(p.posix.normalize(markdownPath));
  return p.posix.relative(
    p.posix.normalize(imagePath),
    from: markdownDirectory,
  );
}

String _parentDirectory(String filePath) {
  final directory = p.posix.dirname(p.posix.normalize(filePath));
  return directory == '.' ? '' : directory;
}

class _MarkdownImagePickerDialog extends ConsumerStatefulWidget {
  final MountedContainer container;
  final String initialDirectory;

  const _MarkdownImagePickerDialog({
    required this.container,
    required this.initialDirectory,
  });

  @override
  ConsumerState<_MarkdownImagePickerDialog> createState() =>
      _MarkdownImagePickerDialogState();
}

class _MarkdownImagePickerDialogState
    extends ConsumerState<_MarkdownImagePickerDialog> {
  static const _imageExtensions = {
    'png',
    'jpg',
    'jpeg',
    'gif',
    'webp',
    'bmp',
    'svg',
  };

  late String _currentDirectory;
  List<RawEntry> _entries = const [];
  bool _loading = true;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _currentDirectory = widget.initialDirectory;
    _loadDirectory();
  }

  Future<void> _loadDirectory() async {
    final generation = ++_loadGeneration;
    if (!_loading) setState(() => _loading = true);
    List<String>? raw;
    try {
      raw = await _readDirectory();
    } catch (_) {
      raw = null;
    }
    if (!mounted || generation != _loadGeneration) return;

    final entries = raw == null ? <RawEntry>[] : RawEntry.parseAll(raw);
    entries.sort((a, b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  Future<List<String>?> _readDirectory() {
    return ref
        .read(vaultFileIoApiProvider)
        .listDirectory(widget.container, _currentDirectory);
  }

  String? get _parentPath {
    if (_currentDirectory.isEmpty) return null;
    final parent = p.posix.dirname(_currentDirectory);
    return parent == '.' ? '' : parent;
  }

  bool _isImage(RawEntry entry) =>
      !entry.isDir && _imageExtensions.contains(entry.extension);

  void _openDirectory(String path) {
    setState(() => _currentDirectory = path);
    _loadDirectory();
  }

  void _selectImage(RawEntry entry) {
    final path = _currentDirectory.isEmpty
        ? entry.name
        : p.posix.join(_currentDirectory, entry.name);
    Navigator.of(context).pop(path);
  }

  @override
  Widget build(BuildContext context) {
    final parentPath = _parentPath;
    final visibleEntries = _entries
        .where((entry) => entry.isDir || _isImage(entry))
        .toList();

    return AlertDialog(
      title: Text(context.l10n.selectImageTitle),
      content: SizedBox(
        width: double.maxFinite,
        height: 360,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _currentDirectory.isEmpty ? '/' : _currentDirectory,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const Divider(height: 16),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        if (parentPath != null)
                          ListTile(
                            leading: const Icon(Icons.arrow_upward_rounded),
                            title: const Text('..'),
                            onTap: () => _openDirectory(parentPath),
                          ),
                        for (final entry in visibleEntries)
                          ListTile(
                            leading: Icon(
                              entry.isDir
                                  ? Icons.folder_outlined
                                  : Icons.image_outlined,
                            ),
                            title: Text(
                              entry.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: entry.isDir
                                ? () => _openDirectory(
                                    _currentDirectory.isEmpty
                                        ? entry.name
                                        : p.posix.join(
                                            _currentDirectory,
                                            entry.name,
                                          ),
                                  )
                                : () => _selectImage(entry),
                          ),
                        if (visibleEntries.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(context.l10n.noImagesFoundMessage),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.cancel),
        ),
      ],
    );
  }
}
