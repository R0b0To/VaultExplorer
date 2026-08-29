import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/utils/file_type_utils.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/tools/models/tool_models.dart';
import 'package:vaultexplorer/features/tools/widgets/vault_browser_sheet.dart';

/// Lets the user browse one or more mounted vaults and multi-select files
/// to add as Single File Crypto sources. Pops with the selected
/// [CryptoSourceItem]s, or nothing if the user backs out.
class VaultFilePickerSheet extends StatefulWidget {
  final List<MountedContainer> mountedContainers;

  const VaultFilePickerSheet({super.key, required this.mountedContainers});

  @override
  State<VaultFilePickerSheet> createState() => _VaultFilePickerSheetState();
}

class _VaultFilePickerSheetState extends VaultBrowserSheetState<VaultFilePickerSheet> {
  final Map<String, CryptoSourceItem> _selectedItems = {};

  @override
  List<MountedContainer> get mountedContainers => widget.mountedContainers;

  @override
  String appBarTitle(BuildContext context) =>
      context.l10n.vaultFilePickerTitle(selectedContainer.displayName);

  @override
  String emptyMessage(BuildContext context) => context.l10n.vaultFilePickerEmptyMessage;

  @override
  List<RawEntry> processEntries(List<RawEntry> raw) {
    final sorted = List<RawEntry>.from(raw);
    sorted.sort((a, b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return sorted;
  }

  void _toggleFileSelection(RawEntry entry) {
    final relPath = currentPath.isEmpty ? entry.name : '$currentPath/${entry.name}';
    final key = '${selectedContainer.volId}:$relPath';
    setState(() {
      if (_selectedItems.containsKey(key)) {
        _selectedItems.remove(key);
      } else {
        _selectedItems[key] = CryptoSourceItem.vault(
          displayName: entry.name,
          container: selectedContainer,
          relativePath: relPath,
        );
      }
    });
  }

  void _confirmSelection() {
    Navigator.pop(context, _selectedItems.values.toList());
  }

  @override
  Widget buildEntryTile(BuildContext context, RawEntry entry) {
    final cs = Theme.of(context).colorScheme;

    if (entry.isDir) {
      return ListTile(
        leading: Icon(Icons.folder_rounded, color: cs.secondary),
        title: Text(entry.name),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => navigateToFolder(entry.name),
      );
    }

    final relPath = currentPath.isEmpty ? entry.name : '$currentPath/${entry.name}';
    final key = '${selectedContainer.volId}:$relPath';
    final isSelected = _selectedItems.containsKey(key);

    return ListTile(
      leading: Icon(iconForFile(entry.name), color: colorForFile(entry.name)),
      title: Text(entry.name),
      subtitle: Text(formatBytes(entry.sizeBytes)),
      trailing: Checkbox(
        value: isSelected,
        onChanged: (_) => _toggleFileSelection(entry),
      ),
      onTap: () => _toggleFileSelection(entry),
    );
  }

  @override
  Widget buildBottomBar(BuildContext context) {
    return FilledButton(
      onPressed: _selectedItems.isNotEmpty ? _confirmSelection : null,
      child: Text(context.l10n.vaultFilePickerConfirmButton(_selectedItems.length)),
    );
  }
}
