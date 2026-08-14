import 'package:flutter/material.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/features/browser/file_browser_screen.dart' show PathSegment;
import 'package:vaultexplorer/features/browser/widgets/breadcrumb_bar.dart';

abstract class VaultBrowserSheetState<W extends StatefulWidget> extends State<W> {
  late MountedContainer selectedContainer;
  final List<String> pathStack = [''];
  List<RawEntry> currentEntries = [];
  bool loading = false;

  String get currentPath => pathStack.last;

  /// Vault to start browsing in when the sheet first opens. Defaults to the
  /// first mounted vault. Subclasses that reopen the sheet to change an
  /// already-made selection (e.g. Vault Sync's Left/Right pickers) should
  /// override this.
  MountedContainer get initialContainer => mountedContainers.first;

  String get initialPath => '';

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
    selectedContainer = initialContainer;
    pathStack
      ..clear()
      ..add(initialPath);
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

  void _jumpTo(int index) {
    if (index == pathStack.length - 1) return; // Already at this folder
    setState(() {
      pathStack.removeRange(index + 1, pathStack.length);
    });
    loadDirectory(currentPath);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Convert string paths into PathSegments for the BreadcrumbBar
    final segments = pathStack.asMap().entries.map((e) {
      final label = e.key == 0 ? context.l10n.vaultBrowserRootFolderLabel : e.value.split('/').last;
      return PathSegment(label, e.value);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: cs.surfaceContainerHigh,
        title: Text(
          appBarTitle(context),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        leading: pathStack.length > 1
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: navigateUp,
              )
            : IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.pop(context),
              ),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.only(top: 8, bottom: 8),
            color: cs.surfaceContainerLow,
            child: _buildVaultSelector(context),
          ),
          BreadcrumbBar(
            stack: segments,
            onTap: _jumpTo,
          ),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : currentEntries.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.folder_open_rounded,
                              size: 48,
                              color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              emptyMessage(context),
                              style: textTheme.bodyMedium?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        itemCount: currentEntries.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (ctx, i) => Material(
                          color: Colors.transparent,
                          child: buildEntryTile(ctx, currentEntries[i]),
                        ),
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

  Widget _buildVaultSelector(BuildContext context) {
    final canSwitch = mountedContainers.length > 1;

    return Material(
      color: Colors.transparent,
      child: OptionPickerTile<int>(
        label: context.l10n.hashVerifierVaultPickerLabel, // Usually "Vault" or "Volume"
        value: selectedContainer.volId,
        subtitle: selectedContainer.displayName,
        prefixIcon: Icons.folder_special_rounded,
        enabled: canSwitch,
        options: mountedContainers
            .map((c) => SelectOption(value: c.volId, label: c.displayName))
            .toList(),
        onChanged: (volId) {
          final container = mountedContainers.firstWhere(
            (c) => c.volId == volId,
            orElse: () => mountedContainers.first,
          );
          switchVault(container);
        },
      ),
    );
  }
}