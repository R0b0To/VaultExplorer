import 'package:flutter/material.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/tools/models/tool_models.dart';
import 'package:vaultexplorer/features/tools/widgets/vault_browser_sheet.dart';

/// Lets the user browse one or more mounted vaults and pick a single
/// folder as the Single File Crypto destination. Pops with a
/// [CryptoDestination], or nothing if the user backs out.
class VaultFolderPickerSheet extends StatefulWidget {
  final List<MountedContainer> mountedContainers;

  const VaultFolderPickerSheet({super.key, required this.mountedContainers});

  @override
  State<VaultFolderPickerSheet> createState() => _VaultFolderPickerSheetState();
}

class _VaultFolderPickerSheetState extends VaultBrowserSheetState<VaultFolderPickerSheet> {
  @override
  List<MountedContainer> get mountedContainers => widget.mountedContainers;

  @override
  String appBarTitle(BuildContext context) =>
      context.l10n.vaultFolderPickerTitle(selectedContainer.displayName);

  @override
  String emptyMessage(BuildContext context) => context.l10n.vaultFolderPickerEmptyMessage;

  @override
  List<RawEntry> processEntries(List<RawEntry> raw) {
    final folders = raw.where((e) => e.isDir).toList();
    folders.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return folders;
  }

  void _confirmSelection() {
    final folderName =
        currentPath.isEmpty ? context.l10n.vaultFolderPickerRootLabel : currentPath.split('/').last;
    final displayName = '${selectedContainer.displayName} / $folderName';
    Navigator.pop(
      context,
      CryptoDestination.vault(
        displayName: displayName,
        container: selectedContainer,
        relativePath: currentPath,
      ),
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
            : context.l10n.vaultFolderPickerConfirmNamedButton(currentPath.split('/').last),
      ),
    );
  }
}
