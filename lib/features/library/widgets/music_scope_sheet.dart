import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/library/controllers/library_controller.dart';
import 'package:vaultexplorer/features/library/index/library_index.dart';
import 'package:vaultexplorer/features/library/models/music_config.dart';

/// Asks which folders music mode should cover.
///
/// Returns the chosen folders (empty means the whole location), or null when
/// cancelled. [turningOn] switches the confirm button between "Start" and
/// "Save". Phone and external storage open on "Only some folders": their root is
/// everything on the device, and indexing all of it is rarely what is wanted.
Future<List<String>?> showMusicScopeSheet(
  BuildContext context, {
  required MountedContainer container,
  required LibraryFileAccess access,
  required List<String> initialFolders,
  required bool turningOn,
  required bool preferChoosing,
}) {
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _MusicScopeSheet(
      access: access,
      initialFolders: initialFolders,
      turningOn: turningOn,
      preferChoosing: preferChoosing,
    ),
  );
}

class _MusicScopeSheet extends StatefulWidget {
  final LibraryFileAccess access;
  final List<String> initialFolders;
  final bool turningOn;
  final bool preferChoosing;

  const _MusicScopeSheet({
    required this.access,
    required this.initialFolders,
    required this.turningOn,
    required this.preferChoosing,
  });

  @override
  State<_MusicScopeSheet> createState() => _MusicScopeSheetState();
}

class _MusicScopeSheetState extends State<_MusicScopeSheet> {
  late bool _choosing = widget.initialFolders.isNotEmpty || widget.preferChoosing;
  late List<String> _folders = List.of(widget.initialFolders);

  bool get _canConfirm => !_choosing || _folders.isNotEmpty;

  Future<void> _addFolder() async {
    final picked = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => _MusicFolderPicker(access: widget.access)),
    );
    if (picked == null || !mounted) return;
    setState(() => _folders = List.of(MusicConfig.normalizeFolders([..._folders, picked])));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = context.typography;
    final cs = context.colors;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.musicScopeTitle, style: text.titleLarge),
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.musicScopeMessage,
            style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<bool>(
              segments: [
                ButtonSegment<bool>(value: false, label: Text(l10n.musicScopeAll)),
                ButtonSegment<bool>(value: true, label: Text(l10n.musicScopeChoose)),
              ],
              selected: {_choosing},
              onSelectionChanged: (s) => setState(() => _choosing = s.first),
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
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Text(
                  l10n.musicScopeNoFolders,
                  style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            for (final f in _folders)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.folder_outlined),
                title: Text(f, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  tooltip: l10n.musicScopeRemoveFolder,
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => setState(() => _folders = [
                        for (final x in _folders)
                          if (x != f) x,
                      ]),
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
                    ? () => Navigator.of(context).pop(_choosing ? _folders : <String>[])
                    : null,
                child: Text(widget.turningOn ? l10n.musicScopeStart : l10n.save),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Browses a container's folders one level at a time and returns the one the
/// person adds. Works the same for vaults, phone storage and external storage:
/// it only uses the listing the scanner uses.
class _MusicFolderPicker extends StatefulWidget {
  final LibraryFileAccess access;

  const _MusicFolderPicker({required this.access});

  @override
  State<_MusicFolderPicker> createState() => _MusicFolderPickerState();
}

class _MusicFolderPickerState extends State<_MusicFolderPicker> {
  String _path = '';
  List<String> _dirs = const [];
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
      _loading = true;
      _failed = false;
    });
    List<String>? dirs;
    try {
      final entries = await widget.access.list(path);
      if (entries != null) {
        dirs = [
          for (final e in entries)
            if (e.isDir && !e.name.startsWith('.')) e.name,
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
    final title = _path.isEmpty ? l10n.musicScopePickerRoot : _path.substring(_path.lastIndexOf('/') + 1);
    return PopScope(
      canPop: _path.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _up();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          leading: BackButton(
            onPressed: () => _path.isEmpty ? Navigator.of(context).pop() : _up(),
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _dirs.isEmpty
                ? Center(
                    child: Text(
                      _failed ? l10n.libraryIncompleteNote : l10n.musicScopePickerEmpty,
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.builder(
                    itemCount: _dirs.length,
                    itemBuilder: (context, i) => ListTile(
                      leading: const Icon(Icons.folder_outlined),
                      title: Text(_dirs[i], maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _load(_join(_dirs[i])),
                    ),
                  ),
        bottomNavigationBar: _path.isEmpty
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(_path),
                    icon: const Icon(Icons.add_rounded),
                    label: Text(l10n.musicScopePickerAdd),
                  ),
                ),
              ),
      ),
    );
  }
}
