import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/tools/models/vault_sync_models.dart';
import 'package:vaultexplorer/features/tools/widgets/vault_browser_sheet.dart';
import 'package:vaultexplorer/features/tools/widgets/vault_browser_sheet_controller.dart';

/// Lets the user browse the currently mounted vaults and pick a container +
/// folder to use as the Left or Right side of the Vault Sync tool.
///
/// Pops with a [VaultSyncSide] on confirm, or nothing if the user backs
/// out. Reuses [VaultBrowserScaffold] -- same browsing/switch-vault
/// behavior as [VaultFolderPickerSheet], just returning a sync side instead
/// of a [CryptoDestination].
class VaultSyncLocationPickerSheet extends ConsumerWidget {
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

  MountedContainer _computeInitialContainer() {
    final side = initialSide;
    if (side != null) {
      return mountedContainers.firstWhere(
        (c) => c.volId == side.container.volId,
        orElse: () => mountedContainers.first,
      );
    }
    // Default to the second mounted vault if picking the Right side
    if (!isLeft && mountedContainers.length > 1) {
      return mountedContainers[1];
    }
    return mountedContainers.first;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final initialContainer = _computeInitialContainer();
    final initialPath = initialSide?.relativePath ?? '';
    final params = VaultBrowserParams(
      mountedContainers: mountedContainers,
      initialContainer: initialContainer,
      initialPath: initialPath,
    );
    final state = ref.watch(vaultBrowserControllerProvider(params));
    final notifier = ref.read(vaultBrowserControllerProvider(params).notifier);
    final cs = Theme.of(context).colorScheme;

    return VaultBrowserScaffold(
      params: params,
      appBarTitle: (ctx, _) => ctx.l10n.vaultSyncPickLocationTitle(sideLabel),
      emptyMessage: (ctx) => ctx.l10n.vaultFolderPickerEmptyMessage,
      processEntries: (raw) {
        final folders = raw.where((e) => e.isDir).toList()
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
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