import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/tools/models/tool_models.dart';
import 'package:vaultexplorer/features/tools/widgets/vault_browser_sheet.dart';
import 'package:vaultexplorer/features/tools/widgets/vault_browser_sheet_controller.dart';

/// Lets the user browse one or more mounted vaults and pick a single
/// folder as the Single File Crypto destination. Pops with a
/// [CryptoDestination], or nothing if the user backs out.
class VaultFolderPickerSheet extends ConsumerWidget {
  final List<MountedContainer> mountedContainers;
  final MountedContainer? initialContainer;
  final String initialPath;

  const VaultFolderPickerSheet({
    super.key,
    required this.mountedContainers,
    this.initialContainer,
    this.initialPath = '',
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final params = VaultBrowserParams(
      mountedContainers: mountedContainers,
      initialContainer: initialContainer ?? mountedContainers.first,
      initialPath: initialPath,
    );
    final state = ref.watch(vaultBrowserControllerProvider(params));
    final notifier = ref.read(vaultBrowserControllerProvider(params).notifier);
    final cs = Theme.of(context).colorScheme;

    return VaultBrowserScaffold(
      params: params,
      appBarTitle: (ctx, container) =>
          ctx.l10n.vaultFolderPickerTitle(container.displayName),
      emptyMessage: (ctx) => ctx.l10n.vaultFolderPickerEmptyMessage,
      processEntries: (raw) {
        final folders = raw.where((e) => e.isDir).toList();
        folders.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
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
            final folderName = state.currentPath.isEmpty
                ? ctx.l10n.vaultFolderPickerRootLabel
                : state.currentPath.split('/').last;
            final displayName = '${state.selectedContainer.displayName} / $folderName';
            Navigator.pop(
              ctx,
              CryptoDestination.vault(
                displayName: displayName,
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