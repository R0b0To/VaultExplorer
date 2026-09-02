import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';

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
  Widget _buildFilterMenuItem(
    String? value,
    String label,
    IconData icon,
    ColorScheme cs,
  ) {
    final isActive = widget.currentFilter == value;
    return MenuItemButton(
      leadingIcon: Icon(
        icon,
        size: 18,
        color: isActive ? cs.primary : cs.onSurfaceVariant,
      ),
      trailingIcon: isActive
          ? Icon(Icons.check_rounded, size: 16, color: cs.primary)
          : null,
      onPressed: () => widget.onFilterChanged(value),
      child: Text(
        label,
        style: TextStyle(
          fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          color: isActive ? cs.primary : null,
        ),
      ),
    );
  }

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
menuChildren: [
        _buildFilterMenuItem(
            null, context.l10n.filterAllFilesOption, Icons.all_inclusive_rounded, cs),
        _buildFilterMenuItem(
            'image', context.l10n.filterImagesOption, Icons.image_outlined, cs),
        _buildFilterMenuItem(
            'video', context.l10n.filterVideosOption, Icons.videocam_outlined, cs),
        _buildFilterMenuItem(
            'audio', context.l10n.filterAudioOption, Icons.audiotrack_rounded, cs),
        _buildFilterMenuItem(
            'document', context.l10n.filterDocumentsOption, Icons.description_outlined, cs),
        if (!widget.hideVaultOnlyActions)
          _buildFilterMenuItem(
              'secure', context.l10n.secureItem, Icons.lock_outline_rounded, cs),
      ],
    );
  }
}