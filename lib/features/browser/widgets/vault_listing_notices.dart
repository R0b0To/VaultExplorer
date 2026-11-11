import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/filesystem/filesystem_type.dart';
import 'package:vaultexplorer/core/filesystem/mounted_container_filesystem.dart';
import 'package:vaultexplorer/core/filesystem/name_validation.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/utils/vault_symlink.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/models/file_operation.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';

/// What a Cryptomator folder contains that a normal listing cannot show:
///
///  * **Symbolic links.** A link is neither a file nor a folder here. It is never followed (its target could
///    point anywhere), so the sheet only *shows* where it points.
///  * **Hidden entries.** Things that exist on disk inside the vault but are not listed -- most often
///    sync-conflict copies such as "name (1)" made by a cloud sync app, or a node whose upload has not
///    finished. Without this notice they are simply invisible.
///
/// Renders nothing at all unless there is something to report, and nothing for anything that is not a
/// Cryptomator vault, so it is safe to place above every folder listing.
class VaultListingNotices extends ConsumerStatefulWidget {
  const VaultListingNotices({
    super.key,
    required this.container,
    required this.dirPath,
    required this.listingToken,
  });

  final MountedContainer container;
  final String dirPath;

  /// Anything whose identity changes when the folder listing is reloaded (the browser passes its item list),
  /// so the notice is refreshed together with the listing.
  final Object listingToken;

  @override
  ConsumerState<VaultListingNotices> createState() =>
      _VaultListingNoticesState();
}

class _VaultListingNoticesState extends ConsumerState<VaultListingNotices> {
  List<VaultSymlink> _links = const [];
  int _hidden = 0;
  int _generation = 0;
  late final FileOperationService _opSvc;

  @override
  void initState() {
    super.initState();
    _opSvc = ref.read(fileOperationServiceProvider);
    // Creating, renaming or deleting a link changes neither the folder, the container nor the listing, so
    // nothing else would tell this notice to reload.
    _opSvc.addVolumeContentChangedListener(_onVolumeContentChanged);
    _load();
  }

  @override
  void dispose() {
    _opSvc.removeVolumeContentChangedListener(_onVolumeContentChanged);
    super.dispose();
  }

  void _onVolumeContentChanged(VolumeContentChange change) {
    // Only Cryptomator vaults have links or hidden entries; every other container stays untouched.
    if (!widget.container.format.isCryptomator) return;
    if (change.volId != widget.container.volId) return;
    unawaited(_load());
  }

  @override
  void didUpdateWidget(VaultListingNotices oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dirPath != widget.dirPath ||
        oldWidget.container.volId != widget.container.volId ||
        !identical(oldWidget.listingToken, widget.listingToken)) {
      _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final api = ref.read(vaultFileIoApiProvider);
    final links = await api.listVaultSymlinks(widget.container, widget.dirPath);
    final hidden = await api.hiddenEntryCount(widget.container, widget.dirPath);
    if (!mounted || generation != _generation) return;
    final shownHidden = hidden < 0 ? 0 : hidden;
    if (shownHidden == _hidden && listEquals(links, _links)) return;
    setState(() {
      _links = links;
      _hidden = shownHidden;
    });
  }

  String _pathOf(VaultSymlink link) =>
      widget.dirPath.isEmpty ? link.name : '${widget.dirPath}/${link.name}';

  void _openDetails() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => _DetailsSheet(
        container: widget.container,
        dirPath: widget.dirPath,
        links: _links,
        hidden: _hidden,
        pathOf: _pathOf,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_links.isEmpty && _hidden == 0) return const SizedBox.shrink();
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final parts = <String>[
      if (_links.isNotEmpty) l10n.vaultListingSymbolicLinkCount(_links.length),
      if (_hidden > 0) l10n.vaultListingHiddenEntryCount(_hidden),
    ];
    final warn = _hidden > 0;
    return Material(
      color: warn ? scheme.tertiaryContainer : scheme.surfaceContainerHighest,
      child: InkWell(
        onTap: _openDetails,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(
                warn ? Icons.visibility_off_outlined : Icons.link,
                size: 18,
                color: warn
                    ? scheme.onTertiaryContainer
                    : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  parts.join(' \u00B7 '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: warn
                        ? scheme.onTertiaryContainer
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ),
              Text(
                l10n.vaultListingDetails,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: warn ? scheme.onTertiaryContainer : scheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailsSheet extends ConsumerStatefulWidget {
  const _DetailsSheet({
    required this.container,
    required this.dirPath,
    required this.links,
    required this.hidden,
    required this.pathOf,
  });

  final MountedContainer container;
  final String dirPath;
  final List<VaultSymlink> links;
  final int hidden;
  final String Function(VaultSymlink) pathOf;

  @override
  ConsumerState<_DetailsSheet> createState() => _DetailsSheetState();
}

class _DetailsSheetState extends ConsumerState<_DetailsSheet> {
  // link name -> target text (null while loading, '' if unreadable is represented by a marker)
  final Map<String, String?> _targets = {};
  final Set<String> _done = {};

  /// The links shown. Starts as the snapshot the banner passed in and is re-read after a delete or rename.
  late List<VaultSymlink> _links;
  int _loadGeneration = 0;

  bool get _canEdit => !widget.container.readOnly;

  @override
  void initState() {
    super.initState();
    _links = widget.links;
    unawaited(_loadTargets());
  }

  Future<void> _loadTargets() async {
    final generation = ++_loadGeneration;
    final api = ref.read(vaultFileIoApiProvider);
    for (final link in _links) {
      final target = await api.readVaultSymlink(
        widget.container,
        widget.pathOf(link),
      );
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _targets[link.name] = target;
        _done.add(link.name);
      });
    }
  }

  /// Re-reads the links after a change, and closes the sheet once there is nothing left to show.
  Future<void> _refreshAfterChange() async {
    ref
        .read(fileOperationServiceProvider)
        .notifyVolumeContentChanged(widget.container.volId);
    final links = await ref
        .read(vaultFileIoApiProvider)
        .listVaultSymlinks(widget.container, widget.dirPath);
    if (!mounted) return;
    setState(() {
      _links = links;
      _targets.clear();
      _done.clear();
    });
    if (_links.isEmpty && widget.hidden == 0) {
      Navigator.pop(context);
      return;
    }
    unawaited(_loadTargets());
  }

  /// Removes the link itself. Its target is never touched or followed: the engine deletes the link node only.
  Future<void> _delete(VaultSymlink link) async {
    final l10n = context.l10n;
    final confirmed = await showAppConfirmDialog(
      context,
      title: l10n.deleteSymbolicLinkTitle,
      message: l10n.deleteSymbolicLinkMessage(link.name),
      confirmLabel: l10n.delete,
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;
    var ok = false;
    try {
      ok = await ref
          .read(vaultFileIoApiProvider)
          .deleteFile(widget.container, widget.pathOf(link));
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    if (ok) {
      await _refreshAfterChange();
    } else {
      showAppSnackBar(
        context,
        message: l10n.filesDeleteFailed,
        tone: AppBannerTone.error,
      );
    }
  }

  Future<void> _rename(VaultSymlink link) async {
    final l10n = context.l10n;
    final newName = await showDialog<String>(
      context: context,
      builder: (_) => _RenameSymlinkDialog(
        container: widget.container,
        link: link,
        otherNames: _links.map((l) => l.name).toSet()..remove(link.name),
      ),
    );
    if (newName == null || newName == link.name || !mounted) return;
    final newPath = widget.dirPath.isEmpty
        ? newName
        : '${widget.dirPath}/$newName';
    var ok = false;
    try {
      ok = await ref
          .read(vaultFileIoApiProvider)
          .renameFile(widget.container, widget.pathOf(link), newPath);
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    if (ok) {
      await _refreshAfterChange();
    } else {
      showAppSnackBar(
        context,
        message: l10n.couldntRenameSingle(link.name),
        tone: AppBannerTone.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            if (widget.hidden > 0) ...[
              Text(
                l10n.vaultListingHiddenEntriesTitle,
                style: textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                l10n.vaultListingHiddenEntriesBody,
                style: textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
            ],
            if (_links.isNotEmpty) ...[
              Text(
                l10n.vaultListingSymbolicLinksTitle,
                style: textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                l10n.vaultListingSymbolicLinksNote,
                style: textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              for (final link in _links)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.link),
                  trailing: !_canEdit
                      ? null
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: l10n.rename,
                              icon: const Icon(Icons.drive_file_rename_outline),
                              onPressed: () => _rename(link),
                            ),
                            IconButton(
                              tooltip: l10n.delete,
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _delete(link),
                            ),
                          ],
                        ),
                  title: Text(
                    link.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: !_done.contains(link.name)
                      ? null
                      : Text(
                          _targets[link.name] ??
                              l10n.vaultListingTargetUnreadable,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                  onTap: _targets[link.name] == null
                      ? null
                      : () {
                          Clipboard.setData(
                            ClipboardData(text: _targets[link.name]!),
                          );
                          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                            SnackBar(
                              content: Text(l10n.vaultListingLinkTargetCopied),
                            ),
                          );
                        },
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Asks for a new name for one link. Validated like the "New symbolic link" dialog (file-name rules for the
/// container, and not the name of another link in the folder); pops with the new name, or null on cancel.
class _RenameSymlinkDialog extends StatefulWidget {
  const _RenameSymlinkDialog({
    required this.container,
    required this.link,
    required this.otherNames,
  });

  final MountedContainer container;
  final VaultSymlink link;
  final Set<String> otherNames;

  @override
  State<_RenameSymlinkDialog> createState() => _RenameSymlinkDialogState();
}

class _RenameSymlinkDialogState extends State<_RenameSymlinkDialog> {
  late final TextEditingController _ctrl;
  late final FilesystemType _fsType;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.link.name);
    _ctrl.selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.link.name.length,
    );
    _fsType = resolveFilesystemType(widget.container);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool _takenByOtherLink(String name) {
    if (FilesystemRules.of(_fsType).caseSensitive) {
      return widget.otherNames.contains(name);
    }
    final lower = name.toLowerCase();
    return widget.otherNames.any((n) => n.toLowerCase() == lower);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final name = _ctrl.text;
    final issues = name.isEmpty
        ? const <NameValidationIssue>[]
        : validateEntryName(
            name,
            _fsType,
            entryType: EntryType.file,
            l10n: l10n,
          ).issues;
    final taken = name.isNotEmpty && _takenByOtherLink(name);
    final canRename =
        name.isNotEmpty && name != widget.link.name && issues.isEmpty && !taken;
    final errors = [
      ...issues.map((i) => i.message),
      if (taken) l10n.symbolicLinkNameTaken,
    ];
    return AlertDialog(
      title: Text(l10n.symbolicLinkRenameTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _ctrl,
            autofocus: true,
            decoration: InputDecoration(hintText: l10n.symbolicLinkNameHint),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) {
              if (canRename) Navigator.pop(context, _ctrl.text);
            },
          ),
          for (final message in errors)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                message,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: canRename ? () => Navigator.pop(context, _ctrl.text) : null,
          child: Text(l10n.rename),
        ),
      ],
    );
  }
}
