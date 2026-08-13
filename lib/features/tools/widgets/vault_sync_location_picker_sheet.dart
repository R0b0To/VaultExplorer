import 'package:flutter/material.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/tools/models/vault_sync_models.dart';
import 'package:vaultexplorer/features/tools/widgets/vault_browser_sheet.dart';

/// Lets the user browse the currently mounted vaults and pick a container +
/// folder to use as the Left or Right side of the Vault Sync tool.
///
/// Pops with a [VaultSyncSide] on confirm, or nothing if the user backs
/// out. Reuses [VaultBrowserSheetState] -- same browsing/switch-vault
/// behavior as [VaultFolderPickerSheet], just returning a sync side instead
/// of a [CryptoDestination].
class VaultSyncLocationPickerSheet extends StatefulWidget {
  final List<MountedContainer> mountedContainers;

  /// "Left" or "Right" -- shown in the app bar title so it's clear which
  /// side of the comparison is being picked.
  final String sideLabel;

  /// The side's current selection, if any -- when reopening the picker to
  /// change an already-made choice, the sheet resumes browsing there
  /// instead of jumping back to the first mounted vault.
  final VaultSyncSide? initialSide;

  const VaultSyncLocationPickerSheet({
    super.key,
    required this.mountedContainers,
    required this.sideLabel,
    this.initialSide,
  });

  @override
  State<VaultSyncLocationPickerSheet> createState() =>
      _VaultSyncLocationPickerSheetState();
}

class _VaultSyncLocationPickerSheetState
    extends VaultBrowserSheetState<VaultSyncLocationPickerSheet> {
  @override
  List<MountedContainer> get mountedContainers => widget.mountedContainers;

  @override
  MountedContainer get initialContainer {
    final side = widget.initialSide;
    if (side == null) return mountedContainers.first;
    // Match by volId rather than trusting object identity -- the mounted
    // list may have been rebuilt since the side was first picked.
    return mountedContainers.firstWhere(
      (c) => c.volId == side.container.volId,
      orElse: () => mountedContainers.first,
    );
  }

  @override
  String get initialPath => widget.initialSide?.relativePath ?? '';

  @override
  String appBarTitle(BuildContext context) =>
      context.l10n.vaultSyncPickLocationTitle(widget.sideLabel);

  @override
  String emptyMessage(BuildContext context) =>
      context.l10n.vaultFolderPickerEmptyMessage;

  @override
  List<RawEntry> processEntries(List<RawEntry> raw) {
    final folders = raw.where((e) => e.isDir).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return folders;
  }

  void _confirmSelection() {
    Navigator.pop(
      context,
      VaultSyncSide(container: selectedContainer, relativePath: currentPath),
    );
  }

  @override
  Widget buildEntryTile(BuildContext context, RawEntry entry) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(Icons.folder_rounded, color: cs.secondary),
      title: Text(entry.name),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => navigateToFolder(entry.name),
    );
  }

  @override
  Widget buildBottomBar(BuildContext context) {
    return FilledButton.icon(
      onPressed: _confirmSelection,
      icon: const Icon(Icons.check_rounded),
      label: Text(
        currentPath.isEmpty
            ? context.l10n.vaultFolderPickerConfirmRootButton
            : context.l10n.vaultFolderPickerConfirmNamedButton(
                currentPath.split('/').last,
              ),
      ),
    );
  }
}