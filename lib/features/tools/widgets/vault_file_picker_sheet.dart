import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/utils/file_type_utils.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/tools/models/tool_models.dart';
import 'package:vaultexplorer/features/tools/widgets/vault_browser_sheet.dart';
import 'package:vaultexplorer/features/tools/widgets/vault_browser_sheet_controller.dart';

/// Lets the user browse one or more mounted vaults and multi-select files
/// to add as Single File Crypto sources. Pops with the selected
/// [CryptoSourceItem]s, or nothing if the user backs out.
class VaultFilePickerSheet extends ConsumerStatefulWidget {
  final List<MountedContainer> mountedContainers;
  final MountedContainer? initialContainer;
  final String initialPath;

  const VaultFilePickerSheet({
    super.key,
    required this.mountedContainers,
    this.initialContainer,
    this.initialPath = '',
  });

  @override
  ConsumerState<VaultFilePickerSheet> createState() => _VaultFilePickerSheetState();
}

class _VaultFilePickerSheetState extends ConsumerState<VaultFilePickerSheet> {
  final Map<String, CryptoSourceItem> _selectedItems = {};

  void _toggleFileSelection(MountedContainer container, String currentPath, RawEntry entry) {
    final relPath = currentPath.isEmpty ? entry.name : '$currentPath/${entry.name}';
    final key = '${container.volId}:$relPath';
    setState(() {
      if (_selectedItems.containsKey(key)) {
        _selectedItems.remove(key);
      } else {
        _selectedItems[key] = CryptoSourceItem.vault(
          displayName: entry.name,
          container: container,
          relativePath: relPath,
        );
      }
    });
  }

  void _confirmSelection() {
    Navigator.pop(context, _selectedItems.values.toList());
  }

  @override
  Widget build(BuildContext context) {
    final params = VaultBrowserParams(
      mountedContainers: widget.mountedContainers,
      initialContainer: widget.initialContainer ?? widget.mountedContainers.first,
      initialPath: widget.initialPath,
    );
    final state = ref.watch(vaultBrowserControllerProvider(params));
    final notifier = ref.read(vaultBrowserControllerProvider(params).notifier);
    final cs = Theme.of(context).colorScheme;

    return VaultBrowserScaffold(
      params: params,
      appBarTitle: (ctx, container) =>
          ctx.l10n.vaultFilePickerTitle(container.displayName),
      emptyMessage: (ctx) => ctx.l10n.vaultFilePickerEmptyMessage,
      processEntries: (raw) {
        final sorted = List<RawEntry>.from(raw);
        sorted.sort((a, b) {
          if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
        return sorted;
      },
      buildEntryTile: (ctx, entry) {
        if (entry.isDir) {
          return ListTile(
            leading: Icon(Icons.folder_rounded, color: cs.secondary),
            title: Text(entry.name),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => notifier.navigateToFolder(entry.name),
          );
        }

        final relPath = state.currentPath.isEmpty ? entry.name : '${state.currentPath}/${entry.name}';
        final key = '${state.selectedContainer.volId}:$relPath';
        final isSelected = _selectedItems.containsKey(key);

        return ListTile(
          leading: Icon(iconForFile(entry.name), color: colorForFile(entry.name)),
          title: Text(entry.name),
          subtitle: Text(formatBytes(entry.sizeBytes)),
          trailing: Checkbox(
            value: isSelected,
            onChanged: (_) => _toggleFileSelection(state.selectedContainer, state.currentPath, entry),
          ),
          onTap: () => _toggleFileSelection(state.selectedContainer, state.currentPath, entry),
        );
      },
      buildBottomBar: (ctx) {
        return FilledButton(
          onPressed: _selectedItems.isNotEmpty ? _confirmSelection : null,
          child: Text(ctx.l10n.vaultFilePickerConfirmButton(_selectedItems.length)),
        );
      },
    );
  }
}