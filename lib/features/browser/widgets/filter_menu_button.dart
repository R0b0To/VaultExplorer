import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';

Widget _filterMenuItem(
  BuildContext context,
  ColorScheme cs,
  String? value,
  String? currentFilter,
  ValueChanged<String?> onFilterChanged,
  String label,
  IconData icon,
) {
  final isActive = currentFilter == value;
  return MenuItemButton(
    leadingIcon: Icon(
      icon,
      size: 18,
      color: isActive ? cs.primary : cs.onSurfaceVariant,
    ),
    trailingIcon: isActive
        ? Icon(Icons.check_rounded, size: 16, color: cs.primary)
        : null,
    onPressed: () => onFilterChanged(value),
    child: Text(
      label,
      style: TextStyle(
        fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
        color: isActive ? cs.primary : null,
      ),
    ),
  );
}

/// The filter options, shared between [FilterMenuButton]'s own MenuAnchor
/// and any other cascade (e.g. the FAB toolbar's "More" menu) that wants to
/// embed the same choices as a [SubmenuButton]'s `menuChildren`.
List<Widget> buildFilterMenuItems({
  required BuildContext context,
  required ColorScheme cs,
  required String? currentFilter,
  required ValueChanged<String?> onFilterChanged,
  required bool hideVaultOnlyActions,
}) {
  final l10n = context.l10n;
  return [
    _filterMenuItem(context, cs, null, currentFilter, onFilterChanged,
        l10n.filterAllFilesOption, Icons.all_inclusive_rounded),
    _filterMenuItem(context, cs, 'image', currentFilter, onFilterChanged,
        l10n.filterImagesOption, Icons.image_outlined),
    _filterMenuItem(context, cs, 'video', currentFilter, onFilterChanged,
        l10n.filterVideosOption, Icons.videocam_outlined),
    _filterMenuItem(context, cs, 'audio', currentFilter, onFilterChanged,
        l10n.filterAudioOption, Icons.audiotrack_rounded),
    _filterMenuItem(context, cs, 'document', currentFilter, onFilterChanged,
        l10n.filterDocumentsOption, Icons.description_outlined),
    if (!hideVaultOnlyActions)
      _filterMenuItem(context, cs, 'secure', currentFilter, onFilterChanged,
          l10n.secureItem, Icons.lock_outline_rounded),
  ];
}

/// Toolbar popup button for filtering files by type (images/videos/audio/documents).
class FilterMenuButton extends StatefulWidget {
  final String? currentFilter;
  final ValueChanged<String?> onFilterChanged;

  /// Hides the "Secure Item" filter option. Mirrors
  /// `AddItemMenuButton.hideVaultOnlyActions`: a plain local-storage
  /// container (decoy mode's file manager) has no vault-item records for
  /// this filter to match, and surfacing the option there would itself
  /// hint that a "secure item" concept exists.
  final bool hideVaultOnlyActions;

  const FilterMenuButton({
    super.key,
    required this.currentFilter,
    required this.onFilterChanged,
    required this.hideVaultOnlyActions,
  });

  @override
  State<FilterMenuButton> createState() => _FilterMenuButtonState();
}

class _FilterMenuButtonState extends State<FilterMenuButton> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isFilterActive = widget.currentFilter != null;

    return MenuAnchor(
      builder: (context, controller, child) => IconButton(
        icon: Icon(
          isFilterActive ? Icons.filter_alt_rounded : Icons.filter_alt_outlined,
          color: isFilterActive ? cs.primary : null,
        ),
        tooltip: context.l10n.filtersMenuItem,
        onPressed: () {
          if (controller.isOpen) {
            controller.close();
          } else {
            controller.open();
          }
        },
      ),
      menuChildren: buildFilterMenuItems(
        context: context,
        cs: cs,
        currentFilter: widget.currentFilter,
        onFilterChanged: widget.onFilterChanged,
        hideVaultOnlyActions: widget.hideVaultOnlyActions,
      ),
    );
  }
}