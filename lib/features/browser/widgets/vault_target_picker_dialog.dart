import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';

/// Lets the user choose any file or folder in the current Cryptomator vault.
/// Returns a vault-root-relative path; the caller converts it to a target
/// relative to the directory containing the new symbolic link.
Future<String?> showVaultTargetPicker({
  required BuildContext context,
  required MountedContainer container,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _VaultTargetPickerDialog(container: container),
  );
}

class _VaultTargetPickerDialog extends ConsumerStatefulWidget {
  const _VaultTargetPickerDialog({required this.container});

  final MountedContainer container;

  @override
  ConsumerState<_VaultTargetPickerDialog> createState() =>
      _VaultTargetPickerDialogState();
}

class _VaultTargetPickerDialogState
    extends ConsumerState<_VaultTargetPickerDialog> {
  String _directory = '';
  List<RawEntry> _entries = const [];
  bool _loading = true;
  bool _loadFailed = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _loadDirectory();
  }

  Future<void> _loadDirectory() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _loadFailed = false;
    });

    try {
      final api = ref.read(vaultFileIoApiProvider);
      // Use the browser-only listing: it merges shortcut entries, while the
      // generic listing remains link-free for sync, export and scanners.
      final raw = await api.listDirectoryForBrowser(
        widget.container,
        _directory,
      );
      if (raw == null) throw StateError('Unable to list vault directory');
      final entries = RawEntry.parseAll(raw);
      entries.sort((a, b) {
        if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

      if (!mounted || generation != _generation) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _entries = const [];
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  String? get _parentDirectory {
    if (_directory.isEmpty) return null;
    final parent = p.posix.dirname(_directory);
    return parent == '.' ? '' : parent;
  }

  String _entryPath(RawEntry entry) => _directory.isEmpty
      ? entry.name
      : p.posix.join(_directory, entry.name);

  void _openDirectory(String path) {
    setState(() => _directory = path);
    _loadDirectory();
  }

  void _select(String path) => Navigator.of(context).pop(path);

  @override
  Widget build(BuildContext context) {
    final parent = _parentDirectory;
    return AlertDialog(
      title: Text(context.l10n.symbolicLinkSelectTargetTitle),
      content: SizedBox(
        width: double.maxFinite,
        height: 380,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _directory.isEmpty ? '/' : '/$_directory',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const Divider(height: 16),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _loadFailed
                      ? Center(
                          child: Text(context.l10n.symbolicLinkPickerLoadError),
                        )
                      : ListView(
                          children: [
                            if (parent != null)
                              ListTile(
                                leading: const Icon(Icons.arrow_upward_rounded),
                                title: const Text('..'),
                                onTap: () => _openDirectory(parent),
                              ),
                            for (final entry in _entries)
                              ListTile(
                                leading: Icon(
                                  entry.isDir
                                      ? (entry.isSymlink
                                          ? Icons.folder_special_outlined
                                          : Icons.folder_outlined)
                                      : (entry.isSymlink
                                          ? Icons.insert_link_rounded
                                          : Icons.insert_drive_file_outlined),
                                ),
                                title: Text(
                                  entry.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: entry.isSymlink
                                    ? Text(context.l10n.shortcutBadge)
                                    : null,
                                trailing: entry.isDir
                                    ? const Icon(Icons.chevron_right_rounded)
                                    : null,
                                onTap: entry.isDir
                                    ? () => _openDirectory(_entryPath(entry))
                                    : () => _select(_entryPath(entry)),
                              ),
                            if (_entries.isEmpty)
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(context.l10n.emptyFolder),
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
        TextButton(
          onPressed: _loading || _loadFailed ? null : () => _select(_directory),
          child: Text(context.l10n.symbolicLinkSelectThisFolder),
        ),
      ],
    );
  }
}
