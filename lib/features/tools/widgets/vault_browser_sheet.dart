import 'package:flutter/material.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';

/// Shared directory-browsing behavior for the vault file picker and vault
/// folder picker sheets used by the Single File Crypto tool.
///
/// Both pickers need to: track which mounted vault + path is being
/// browsed, load and list entries for the current path, navigate into and
/// out of folders, let the user switch between mounted vaults, and show a
/// breadcrumb + confirm button. This base class owns all of that; the two
/// concrete sheets only differ in which entries they show (files+folders
/// vs. folders-only), how a row is rendered, and what the confirm button
/// does.
abstract class VaultBrowserSheetState<W extends StatefulWidget> extends State<W> {
  late MountedContainer selectedContainer;
  final List<String> pathStack = [''];
  List<RawEntry> currentEntries = [];
  bool loading = false;

  String get currentPath => pathStack.last;

  /// The full set of vaults the user can switch between.
  List<MountedContainer> get mountedContainers;

  /// Title shown in the app bar, given the vault currently being browsed.
  String appBarTitle(BuildContext context);

  /// Message shown when [currentEntries] is empty for the current path.
  String emptyMessage(BuildContext context);

  /// Takes the raw directory listing and returns what should actually be
  /// displayed -- e.g. all entries sorted folders-first, or folders only.
  List<RawEntry> processEntries(List<RawEntry> raw);

  /// Builds a single row for [entry]. Implementations decide whether
  /// tapping a non-folder entry does anything (the folder picker has no
  /// use for leaf files, so [processEntries] simply excludes them).
  Widget buildEntryTile(BuildContext context, RawEntry entry);

  /// The bottom action bar (usually a single confirm button).
  Widget buildBottomBar(BuildContext context);

  @override
  void initState() {
    super.initState();
    selectedContainer = mountedContainers.first;
    loadDirectory(currentPath);
  }

  Future<void> loadDirectory(String path) async {
    setState(() => loading = true);
    try {
      final rawList = await vaultExplorerApi.listDirectory(selectedContainer, path);
      final entries = processEntries(RawEntry.parseAll(rawList ?? []));
      if (mounted) {
        setState(() {
          currentEntries = entries;
          loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
  }

  void switchVault(MountedContainer container) {
    if (container == selectedContainer) return;
    setState(() {
      selectedContainer = container;
      pathStack
        ..clear()
        ..add('');
    });
    loadDirectory('');
  }

  void navigateToFolder(String folderName) {
    final newPath = currentPath.isEmpty ? folderName : '$currentPath/$folderName';
    pathStack.add(newPath);
    loadDirectory(newPath);
  }

  void navigateUp() {
    if (pathStack.length > 1) {
      pathStack.removeLast();
      loadDirectory(currentPath);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(appBarTitle(context)),
        leading: pathStack.length > 1
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: navigateUp,
              )
            : IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.pop(context),
              ),
        actions: [
          if (mountedContainers.length > 1)
            PopupMenuButton<MountedContainer>(
              icon: const Icon(Icons.swap_horiz_rounded),
              tooltip: context.l10n.vaultBrowserSwitchVaultTooltip,
              onSelected: switchVault,
              itemBuilder: (ctx) => mountedContainers
                  .map((c) => PopupMenuItem(value: c, child: Text(c.displayName)))
                  .toList(),
            ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: cs.surfaceContainerLow,
            child: Row(
              children: [
                Icon(Icons.folder_open_rounded, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    currentPath.isEmpty ? context.l10n.vaultBrowserRootFolderLabel : currentPath,
                    style: textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : currentEntries.isEmpty
                    ? Center(
                        child: Text(
                          emptyMessage(context),
                          style: textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      )
                    : ListView.separated(
                        itemCount: currentEntries.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (ctx, i) => buildEntryTile(ctx, currentEntries[i]),
                      ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          border: Border(top: BorderSide(color: cs.outlineVariant)),
        ),
        child: SafeArea(child: buildBottomBar(context)),
      ),
    );
  }
}
