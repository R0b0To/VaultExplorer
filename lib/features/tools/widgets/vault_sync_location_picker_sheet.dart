import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/core/providers/external_storage_locations_provider.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/utils/natural_sort.dart';
import 'package:vaultexplorer/core/widgets/feedback/app_empty_state.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/browser_dialogs.dart';
import 'package:vaultexplorer/features/decoy/local/decoy_local_repository.dart';
import 'package:vaultexplorer/features/tools/models/vault_sync_models.dart';
import 'package:vaultexplorer/features/tools/widgets/vault_browser_sheet.dart';
import 'package:vaultexplorer/features/tools/widgets/vault_browser_sheet_controller.dart';
import 'package:vaultexplorer/features/tools/widgets/vault_sync_target_style.dart';

/// Lets the user pick a storage target + folder to use as the Left or Right
/// side of the Vault Sync tool.
///
/// The selectable storages are the mounted vaults, the device's Local Storage
/// (when all-files access is granted) and any saved external / document-
/// provider locations.
///
/// Pops with a [VaultSyncSide] on confirm, or nothing if the user backs out.
/// Reuses [VaultBrowserScaffold] -- same browsing / switch-storage behavior
/// as [VaultFolderPickerSheet], just returning a sync side instead of a
/// [CryptoDestination].
class VaultSyncLocationPickerSheet extends ConsumerStatefulWidget {
  /// The currently mounted vaults. Device and document-provider storages are
  /// discovered by the sheet itself.
  final List<MountedContainer> mountedContainers;
  final String sideLabel;
  final VaultSyncSide? initialSide;
  final bool isLeft;

  const VaultSyncLocationPickerSheet({
    super.key,
    required this.mountedContainers,
    required this.sideLabel,
    this.initialSide,
    this.isLeft = true,
  });

  @override
  ConsumerState<VaultSyncLocationPickerSheet> createState() =>
      _VaultSyncLocationPickerSheetState();
}

class _VaultSyncLocationPickerSheetState
    extends ConsumerState<VaultSyncLocationPickerSheet>
    with WidgetsBindingObserver {
  /// Pseudo-containers built for device / provider storages, keyed by what
  /// identifies them. [VaultBrowserParams] compares containers by identity,
  /// so handing it a fresh instance on every rebuild would reset the browser
  /// each time -- reuse the same instance for an unchanged storage.
  final Map<String, MountedContainer> _containerCache = {};

  bool _accessChecked = false;

  /// Root of the primary Local Storage, or null while all-files access
  /// hasn't been granted.
  String? _localRoot;

  List<MountedContainer> _targets = const [];
  MountedContainer? _initialContainer;
  String _initialPath = '';
  VaultBrowserParams? _params;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refreshLocalAccess());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from the system settings screen after granting access.
    if (state == AppLifecycleState.resumed) unawaited(_refreshLocalAccess());
  }

  Future<void> _refreshLocalAccess() async {
    String? root;
    try {
      final hasAccess = await ref
          .read(vaultLifecycleApiProvider)
          .hasAllFilesAccess();
      if (hasAccess) {
        root = (await const DecoyLocalRepository().primaryRoot()).path;
      }
    } catch (_) {
      root = null;
    }
    if (!mounted) return;
    _localRoot = root;
    _accessChecked = true;
    _rebuildTargets();
  }

  /// Recomputes the storage list. Only touches state when the list actually
  /// changed (or a specific storage is being [selectVolId]-ed), so it's safe
  /// to call from listeners.
  void _rebuildTargets({int? selectVolId}) {
    if (!_accessChecked) return;

    final l10n = context.l10n;
    final targets = <MountedContainer>[...widget.mountedContainers];

    final root = _localRoot;
    if (root != null) {
      final name = l10n.localStorageCardTitle;
      targets.add(
        _containerCache.putIfAbsent(
          'local|$root|$name',
          () => buildLocalStorageContainer(rootPath: root, displayName: name),
        ),
      );
    }

    final externals = ref.read(externalStorageLocationsProvider.notifier);
    for (final location in ref.read(externalStorageLocationsProvider)) {
      final resolved = externals.resolveContainer(location.volId);
      if (resolved == null) continue;
      targets.add(
        _containerCache.putIfAbsent(
          'ext|${resolved.volId}|${resolved.uri}|${resolved.displayName}',
          () => resolved,
        ),
      );
    }

    if (listEquals(targets, _targets) && selectVolId == null) return;

    _targets = targets;
    if (targets.isEmpty) {
      setState(() => _params = null);
      return;
    }

    final initial = _pickInitial(selectVolId);
    setState(() {
      _initialContainer = initial;
      _params = VaultBrowserParams(
        mountedContainers: _targets,
        initialContainer: initial,
        initialPath: _initialPath,
      );
    });
  }

  MountedContainer _pickInitial(int? selectVolId) {
    MountedContainer? byId(int volId) {
      for (final c in _targets) {
        if (c.volId == volId) return c;
      }
      return null;
    }

    // A storage the user just added: open it at its root.
    if (selectVolId != null) {
      final added = byId(selectVolId);
      if (added != null) {
        _initialPath = '';
        return added;
      }
    }
    // Later rebuilds keep whatever the sheet opened on.
    final current = _initialContainer;
    if (current != null) {
      final same = byId(current.volId);
      if (same != null) return same;
    }
    final side = widget.initialSide;
    if (side != null) {
      final previous = byId(side.container.volId);
      if (previous != null) {
        _initialPath = side.relativePath;
        return previous;
      }
    }
    _initialPath = '';
    // Default to the second storage when picking the Right side.
    if (!widget.isLeft && _targets.length > 1) return _targets[1];
    return _targets.first;
  }

  Future<void> _requestLocalAccess() async {
    // The result arrives via the resumed lifecycle callback.
    await ref
        .read(vaultLifecycleApiProvider)
        .requestAllFilesAccess(openSettings: true);
  }

  @override
  Widget build(BuildContext context) {
    // The saved-locations provider loads asynchronously and changes when a
    // location is added; keep the storage list in step with it.
    ref.listen(externalStorageLocationsProvider, (_, _) => _rebuildTargets());

    final params = _params;
    if (params == null) return _buildPlaceholder(context);
    return _buildPicker(context, params);
  }

  /// Shown while storages are being discovered, or when there are none yet.
  Widget _buildPlaceholder(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.l10n.vaultSyncPickLocationTitle(widget.sideLabel),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          if (_accessChecked && _localRoot == null)
            IconButton(
              icon: const Icon(Icons.smartphone_rounded),
              tooltip: context.l10n.vaultSyncEnableLocalStorageTooltip,
              onPressed: _requestLocalAccess,
            ),
        ],
      ),
      body: !_accessChecked
          ? const Center(child: CircularProgressIndicator())
          : AppEmptyState(
              icon: Icons.sd_storage_rounded,
              title: context.l10n.vaultSyncNoStoragesTitle,
              message: context.l10n.vaultSyncNoStoragesMessage,
            ),
    );
  }

  Widget _buildPicker(BuildContext context, VaultBrowserParams params) {
    final state = ref.watch(vaultBrowserControllerProvider(params));
    final notifier = ref.read(vaultBrowserControllerProvider(params).notifier);
    final cs = Theme.of(context).colorScheme;

    return VaultBrowserScaffold(
      params: params,
      appBarTitle: (ctx, _) =>
          ctx.l10n.vaultSyncPickLocationTitle(widget.sideLabel),
      emptyMessage: (ctx) => ctx.l10n.vaultFolderPickerEmptyMessage,
      selectorLabel: (ctx) => ctx.l10n.vaultSyncStorageSelectorLabel,
      containerSubtitle: (ctx, container) =>
          syncTargetKindOf(container).label(ctx.l10n),
      actions: (ctx) => [
        if (_accessChecked && _localRoot == null)
          IconButton(
            icon: const Icon(Icons.smartphone_rounded),
            tooltip: ctx.l10n.vaultSyncEnableLocalStorageTooltip,
            onPressed: _requestLocalAccess,
          ),
        IconButton(
          icon: const Icon(Icons.create_new_folder_outlined),
          tooltip: ctx.l10n.newFolderTitle,
          onPressed: () {
            BrowserDialogs.showCreateFolder(
              ctx,
              container: state.selectedContainer,
              currentDirPath: state.currentPath,
              existingEntries: state.rawEntries,
              onSuccess: () =>
                  notifier.loadDirectory(state.currentPath, refresh: true),
              readOnly: state.selectedContainer.readOnly,
            );
          },
        ),
      ],
      processEntries: (raw) {
        final folders = raw.where((e) => e.isDir).toList()
          ..sort((a, b) => naturalCompare(a.name.toLowerCase(), b.name.toLowerCase()));
        return folders;
      },
      buildEntryTile: (ctx, entry) => ListTile(
        leading: Icon(Icons.folder_rounded, color: cs.secondary),
        title: Text(entry.name),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => notifier.navigateToFolder(entry.name),
      ),
      buildBottomBar: (ctx) {
        return FilledButton.icon(
          onPressed: () {
            Navigator.pop(
              ctx,
              VaultSyncSide(
                container: state.selectedContainer,
                relativePath: state.currentPath,
              ),
            );
          },
          icon: const Icon(Icons.check_rounded),
          label: Text(
            state.currentPath.isEmpty
                ? ctx.l10n.vaultFolderPickerConfirmRootButton
                : ctx.l10n.vaultFolderPickerConfirmNamedButton(
                    state.currentPath.split('/').last,
                  ),
          ),
        );
      },
    );
  }
}
