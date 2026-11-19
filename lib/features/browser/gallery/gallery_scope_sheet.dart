import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/theme/file_manager_skin_scope.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/services/category_scan.dart';
import 'package:vaultexplorer/features/browser/widgets/tile_selection_style.dart';
import 'package:vaultexplorer/features/library/controllers/library_controller.dart';
import 'package:vaultexplorer/features/library/index/library_index.dart';
import 'package:vaultexplorer/features/library/widgets/music_scope_sheet.dart'
    show ScopeSheetResult;

export 'package:vaultexplorer/features/library/widgets/music_scope_sheet.dart'
    show ScopeSheetResult;

/// Asks which folders gallery mode should cover.
///
/// Returns the chosen folders and whether "Don't ask again" was checked (empty
/// folders means the whole location), or null when cancelled. [turningOn]
/// switches the confirm button between "Start" and "Save". Phone and external
/// storage open on "Only some folders": their root is everything on the device,
/// and indexing all of it is rarely what is wanted.
Future<ScopeSheetResult?> showGalleryScopeSheet(
  BuildContext context, {
  required MountedContainer container,
  required LibraryFileAccess access,
  required List<String> initialFolders,
  required bool turningOn,
  required bool preferChoosing,
  bool initialDontAskAgain = false,
  bool showHidden = false,
  bool Function(String dirPath)? skipDirectory,
}) {
  return showModalBottomSheet<ScopeSheetResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _GalleryScopeSheet(
      access: access,
      initialFolders: initialFolders,
      turningOn: turningOn,
      preferChoosing: preferChoosing,
      initialDontAskAgain: initialDontAskAgain,
      showHidden: showHidden,
      skipDirectory: skipDirectory,
    ),
  );
}

class _GalleryScopeSheet extends StatefulWidget {
  final LibraryFileAccess access;
  final List<String> initialFolders;
  final bool turningOn;
  final bool preferChoosing;
  final bool initialDontAskAgain;
  final bool showHidden;
  final bool Function(String dirPath)? skipDirectory;

  const _GalleryScopeSheet({
    required this.access,
    required this.initialFolders,
    required this.turningOn,
    required this.preferChoosing,
    this.initialDontAskAgain = false,
    this.showHidden = false,
    this.skipDirectory,
  });

  @override
  State<_GalleryScopeSheet> createState() => _GalleryScopeSheetState();
}

class _GalleryScopeSheetState extends State<_GalleryScopeSheet> {
  late bool _choosing =
      widget.initialFolders.isNotEmpty || widget.preferChoosing;
  late List<String> _folders = List.of(widget.initialFolders);
  late bool _dontAskAgain = widget.initialDontAskAgain;

  bool get _canConfirm => !_choosing || _folders.isNotEmpty;

  Future<void> _addFolder() async {
    final picked = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (_) => _GalleryFolderPicker(
          access: widget.access,
          showHidden: widget.showHidden,
          skipDirectory: widget.skipDirectory,
        ),
      ),
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    setState(
      () => _folders = List.of(normalizeScanRoots([..._folders, ...picked])),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = context.typography;
    final cs = context.colors;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.galleryFoldersMenu, style: text.titleLarge),
              const SizedBox(height: AppSpacing.xs),
              Text(
                l10n.galleryFoldersHint,
                style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.md),
              RadioGroup<bool>(
                groupValue: _choosing,
                onChanged: (value) {
                  if (value != null) setState(() => _choosing = value);
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RadioListTile<bool>(
                      value: false,
                      contentPadding: EdgeInsets.zero,
                      title: Text(l10n.musicScopeAll),
                    ),
                    RadioListTile<bool>(
                      value: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(l10n.musicScopeChoose),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              if (!_choosing)
                Text(
                  l10n.musicScopeAllHint,
                  style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                )
              else ...[
                if (_folders.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.sm,
                    ),
                    child: Text(
                      l10n.musicScopeNoFolders,
                      style: text.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                for (final f in _folders)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(
                      f,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: IconButton(
                      tooltip: l10n.musicScopeRemoveFolder,
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => setState(
                        () => _folders = [
                          for (final x in _folders)
                            if (x != f) x,
                        ],
                      ),
                    ),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _addFolder,
                    icon: const Icon(Icons.add_rounded),
                    label: Text(l10n.musicScopeAddFolder),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              InkWell(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                onTap: () => setState(() => _dontAskAgain = !_dontAskAgain),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: Checkbox(
                          value: _dontAskAgain,
                          onChanged: (val) =>
                              setState(() => _dontAskAgain = val ?? false),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(l10n.dontAskAgain, style: text.bodyMedium),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.cancel),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  FilledButton(
                    onPressed: _canConfirm
                        ? () => Navigator.of(context).pop(
                            ScopeSheetResult(
                              folders: _choosing
                                  ? normalizeScanRoots(_folders)
                                  : <String>[],
                              dontAskAgain: _dontAskAgain,
                            ),
                          )
                        : null,
                    child: Text(
                      widget.turningOn ? l10n.musicScopeStart : l10n.save,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Browses a container's folders one level at a time and returns the ones the
/// person adds. Works the same for vaults, phone storage and external storage.
class _GalleryFolderPicker extends StatefulWidget {
  final LibraryFileAccess access;
  final bool showHidden;
  final bool Function(String dirPath)? skipDirectory;

  const _GalleryFolderPicker({
    required this.access,
    required this.showHidden,
    this.skipDirectory,
  });

  @override
  State<_GalleryFolderPicker> createState() => _GalleryFolderPickerState();
}

class _GalleryFolderPickerState extends State<_GalleryFolderPicker> {
  String _path = '';
  List<String> _dirs = const [];
  final Set<String> _selected = <String>{};
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load('');
  }

  Future<void> _load(String path) async {
    setState(() {
      _path = path;
      _selected.clear();
      _loading = true;
      _failed = false;
    });
    List<String>? dirs;
    try {
      final entries = await widget.access.list(path);
      if (entries != null) {
        dirs = [
          for (final e in entries)
            if (e.isDir)
              if (widget.showHidden || !e.name.startsWith('.'))
                if (!(widget.skipDirectory?.call(
                      path.isEmpty ? e.name : '$path/${e.name}',
                    ) ??
                    false))
                  e.name,
        ]..sort(LibraryText.compare);
      }
    } catch (_) {
      dirs = null;
    }
    if (!mounted || _path != path) return;
    setState(() {
      _dirs = dirs ?? const [];
      _failed = dirs == null;
      _loading = false;
    });
  }

  void _up() {
    final slash = _path.lastIndexOf('/');
    _load(slash < 0 ? '' : _path.substring(0, slash));
  }

  String _join(String name) => _path.isEmpty ? name : '$_path/$name';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final title = _path.isEmpty
        ? l10n.musicScopePickerRoot
        : _path.substring(_path.lastIndexOf('/') + 1);
    final inSelectionMode = _selected.isNotEmpty;
    return PopScope(
      canPop: !inSelectionMode && _path.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (inSelectionMode) {
          setState(() => _selected.clear());
          return;
        }
        _up();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: inSelectionMode
              ? IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => setState(() => _selected.clear()),
                )
              : BackButton(
                  onPressed: () =>
                      _path.isEmpty ? Navigator.of(context).pop() : _up(),
                ),
          title: Text(
            inSelectionMode ? '${_selected.length}' : title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            if (inSelectionMode)
              IconButton(
                tooltip: _selected.length == _dirs.length
                    ? l10n.deselectAll
                    : l10n.selectAll,
                icon: Icon(
                  _selected.length == _dirs.length
                      ? Icons.deselect_rounded
                      : Icons.select_all_rounded,
                ),
                onPressed: () {
                  setState(() {
                    if (_selected.length == _dirs.length) {
                      _selected.clear();
                    } else {
                      _selected.addAll(_dirs);
                    }
                  });
                },
              ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _dirs.isEmpty
            ? Center(
                child: Text(
                  _failed
                      ? l10n.libraryIncompleteNote
                      : l10n.musicScopePickerEmpty,
                  textAlign: TextAlign.center,
                ),
              )
            : ListView.builder(
                itemCount: _dirs.length,
                itemBuilder: (context, i) {
                  final dir = _dirs[i];
                  final isSelected = _selected.contains(dir);
                  final cs = Theme.of(context).colorScheme;
                  final skin = FileManagerSkinScope.of(context);
                  final folderIcon = skin.folderIcon;
                  final iconColor = skin.folderIconColor(cs);
                  final iconBackground = cs.secondaryContainer.withValues(
                    alpha: 0.4,
                  );

                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: 1,
                    ),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      selected: isSelected,
                      selectedTileColor: TileSelectionStyle.selectedBackground(
                        cs,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: 2,
                      ),
                      leading: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          setState(() {
                            if (isSelected) {
                              _selected.remove(dir);
                            } else {
                              _selected.add(dir);
                            }
                          });
                        },
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? cs.primaryContainer
                                : iconBackground,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            folderIcon,
                            size: 22,
                            color: isSelected ? cs.primary : iconColor,
                          ),
                        ),
                      ),
                      title: Text(
                        dir,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: TileSelectionStyle.titleWeight,
                        ),
                      ),
                      trailing: SizedBox(
                        width: 24,
                        height: 24,
                        child: Center(
                          child: inSelectionMode
                              ? TileSelectionIndicator(selected: isSelected)
                              : Icon(
                                  Icons.chevron_right_rounded,
                                  color: cs.onSurfaceVariant,
                                  size: 20,
                                ),
                        ),
                      ),
                      onTap: () {
                        if (inSelectionMode) {
                          setState(() {
                            if (isSelected) {
                              _selected.remove(dir);
                            } else {
                              _selected.add(dir);
                            }
                          });
                        } else {
                          _load(_join(dir));
                        }
                      },
                      onLongPress: () {
                        setState(() {
                          if (isSelected) {
                            _selected.remove(dir);
                          } else {
                            _selected.add(dir);
                          }
                        });
                      },
                    ),
                  );
                },
              ),
        bottomNavigationBar: inSelectionMode
            ? SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(
                      context,
                    ).pop<List<String>>(_selected.map(_join).toList()),
                    icon: const Icon(Icons.add_rounded),
                    label: Text('${l10n.add} (${_selected.length})'),
                  ),
                ),
              )
            : _path.isEmpty
            ? null
            : SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: FilledButton.icon(
                    onPressed: () =>
                        Navigator.of(context).pop<List<String>>([_path]),
                    icon: const Icon(Icons.add_rounded),
                    label: Text(l10n.musicScopePickerAdd),
                  ),
                ),
              ),
      ),
    );
  }
}
