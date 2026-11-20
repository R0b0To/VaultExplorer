import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/features/browser/file_browser_predicates.dart';
import 'package:vaultexplorer/features/browser/services/category_scan.dart';

/// Lets the person choose which folders of a storage the gallery scans.
///
/// Folders are read one level at a time, only when opened, so a storage with
/// thousands of folders costs nothing until someone looks inside. Ticking a
/// folder takes everything under it (its subfolders show as included); ticking
/// nothing means the whole storage.
///
/// Returns the chosen folders (paths from the storage root, already reduced by
/// [normalizeScanRoots]), an empty list for "scan everything", or null when
/// the sheet was dismissed without applying.
Future<List<String>?> showGalleryFolderPicker(
  BuildContext context, {
  required CategoryDirectoryLister listDirectory,
  required List<String> initial,
  required bool showHidden,
  bool Function(String dirPath)? skipDirectory,
}) {
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scroll) => GalleryFolderPickerSheet(
        listDirectory: listDirectory,
        initial: initial,
        showHidden: showHidden,
        skipDirectory: skipDirectory,
        scrollController: scroll,
      ),
    ),
  );
}

class GalleryFolderPickerSheet extends StatefulWidget {
  const GalleryFolderPickerSheet({
    super.key,
    required this.listDirectory,
    required this.initial,
    required this.showHidden,
    required this.scrollController,
    this.skipDirectory,
  });

  final CategoryDirectoryLister listDirectory;
  final List<String> initial;
  final bool showHidden;
  final bool Function(String dirPath)? skipDirectory;
  final ScrollController scrollController;

  @override
  State<GalleryFolderPickerSheet> createState() =>
      _GalleryFolderPickerSheetState();
}

class _Row {
  const _Row(this.path, this.name, this.depth);
  final String path;
  final String name;
  final int depth;
}

class _GalleryFolderPickerSheetState extends State<GalleryFolderPickerSheet> {
  /// The ticked folders; none of them lies inside another one.
  late Set<String> _selected;

  /// Sub-folder names of every folder read so far ('' is the storage root).
  final Map<String, List<String>> _children = {};
  final Set<String> _expanded = {};
  final Set<String> _loading = {};
  final Set<String> _failed = {};

  @override
  void initState() {
    super.initState();
    _selected = normalizeScanRoots(widget.initial).toSet();
    // Open the path to every folder already chosen, so the sheet shows what
    // is ticked instead of a collapsed root.
    final toOpen = <String>{''};
    for (final path in _selected) {
      var dir = parentOf(path);
      while (dir.isNotEmpty) {
        _expanded.add(dir);
        toOpen.add(dir);
        dir = parentOf(dir);
      }
    }
    // Reading starts after the first frame: it reports back through setState.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final dir in toOpen) {
        _load(dir);
      }
    });
  }

  static String parentOf(String path) {
    final slash = path.lastIndexOf('/');
    return slash < 0 ? '' : path.substring(0, slash);
  }

  Future<void> _load(String dir) async {
    if (_children.containsKey(dir) || _loading.contains(dir)) return;
    setState(() {
      _loading.add(dir);
      _failed.remove(dir);
    });
    List<String>? raw;
    try {
      raw = await widget.listDirectory(dir);
    } catch (_) {
      raw = null;
    }
    if (!mounted) return;
    final names = <String>[];
    if (raw != null) {
      for (final entry in RawEntry.parseAll(raw)) {
        if (!entry.isDir) continue;
        if (!widget.showHidden && isHiddenEntryName(entry.name)) continue;
        final path = dir.isEmpty ? entry.name : '$dir/${entry.name}';
        if (widget.skipDirectory?.call(path) ?? false) continue;
        names.add(entry.name);
      }
      names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    }
    setState(() {
      _loading.remove(dir);
      if (raw == null) {
        _failed.add(dir);
      } else {
        _children[dir] = names;
      }
    });
  }

  bool _coveredByAncestor(String path) {
    var dir = parentOf(path);
    while (true) {
      if (_selected.contains(dir)) return true;
      if (dir.isEmpty) return false;
      dir = parentOf(dir);
    }
  }

  bool _hasSelectedDescendant(String path) {
    final prefix = '$path/';
    return _selected.any((s) => s.startsWith(prefix));
  }

  void _toggle(String path) {
    setState(() {
      if (_selected.contains(path)) {
        _selected.remove(path);
      } else {
        // Everything beneath is included from now on, so choices made inside
        // it are redundant.
        _selected.removeWhere((s) => s.startsWith('$path/'));
        _selected.add(path);
      }
    });
  }

  void _toggleExpanded(String path) {
    setState(() {
      if (!_expanded.add(path)) _expanded.remove(path);
    });
    if (_expanded.contains(path)) _load(path);
  }

  void _rows(String dir, int depth, List<_Row> out) {
    final names = _children[dir];
    if (names == null) return;
    for (final name in names) {
      final path = dir.isEmpty ? name : '$dir/$name';
      out.add(_Row(path, name, depth));
      if (_expanded.contains(path)) _rows(path, depth + 1, out);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final rows = <_Row>[];
    _rows('', 0, rows);
    // Also true before the first read has started.
    final rootLoading =
        !_children.containsKey('') && !_failed.contains('');

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(l.galleryFoldersMenu, style: theme.textTheme.titleLarge),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              l.galleryFoldersHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.hintColor,
              ),
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: rootLoading
              ? const Center(child: CircularProgressIndicator())
              : rows.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      l.emptyFolder,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              : ListView.builder(
                  controller: widget.scrollController,
                  itemCount: rows.length,
                  itemBuilder: (context, index) => _buildRow(rows[index]),
                ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
          child: Row(
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context, const <String>[]),
                child: Text(l.galleryFoldersUseAll),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l.cancel),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () =>
                    Navigator.pop(context, normalizeScanRoots(_selected)),
                child: Text(l.galleryFoldersApply),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRow(_Row row) {
    final scheme = Theme.of(context).colorScheme;
    final covered = _coveredByAncestor(row.path);
    final ticked = _selected.contains(row.path);
    final partial = !ticked && !covered && _hasSelectedDescendant(row.path);
    final expanded = _expanded.contains(row.path);
    final loading = _loading.contains(row.path);
    final known = _children[row.path];
    // A folder read and found without sub-folders has nothing to open.
    final leaf = known != null && known.isEmpty;

    return InkWell(
      onTap: leaf ? () => _toggle(row.path) : () => _toggleExpanded(row.path),
      child: Padding(
        padding: EdgeInsets.only(left: 8.0 + row.depth * 20.0, right: 8),
        child: Row(
          children: [
            Checkbox(
              tristate: true,
              // A folder inside a ticked one is included whatever it says, so
              // it shows ticked and cannot be changed on its own.
              value: ticked || covered ? true : (partial ? null : false),
              onChanged: covered ? null : (_) => _toggle(row.path),
            ),
            Icon(
              expanded ? Icons.folder_open_rounded : Icons.folder_rounded,
              size: 22,
              color: ticked || covered ? scheme.primary : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                row.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: ticked ? FontWeight.w600 : null,
                  color: covered && !ticked ? scheme.onSurfaceVariant : null,
                ),
              ),
            ),
            if (loading)
              const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (!leaf)
              Icon(
                expanded
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
                color: scheme.onSurfaceVariant,
              ),
          ],
        ),
      ),
    );
  }
}
