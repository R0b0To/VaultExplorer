import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/data/models/browser_layout_mode.dart';
import 'package:vaultexplorer/data/models/file_manager_action.dart';
import 'package:vaultexplorer/data/models/grid_aspect_ratio.dart';
import 'package:vaultexplorer/features/browser/mixins/sort_mixin.dart';
import 'package:vaultexplorer/features/browser/widgets/filter_menu_button.dart';
import 'package:vaultexplorer/features/browser/widgets/layout_mode_menu_button.dart';
import 'package:vaultexplorer/features/browser/widgets/sort_menu_button.dart';

/// Floating-toolbar "More" button: a single cascading [MenuAnchor] holding
/// every toolbar action other than Add (which is promoted to its own FAB).
/// Sort/Filter/View mode nest as [SubmenuButton]s using the exact same
/// option-building functions as their app-bar equivalents, so there's one
/// source of truth for each menu's contents.
///
/// This replaces the old `FileManagerSpeedDialFab`, which expanded a
/// full-screen scrim into a row of mini-buttons that each opened *another*,
/// separate cascade for Add/Sort/Filter/View -- two flyouts stacked on top
/// of each other, and one that never told the first to close on selection.
/// A single MenuAnchor here gets correct outside-tap and close-on-select
/// behavior for free, the same way it already does for these widgets in the
/// non-FAB toolbar.
class FileManagerMoreMenuButton extends StatelessWidget {
  /// Which actions to show, in order. `add` is ignored if present -- it's
  /// always the separate FAB, never a "More" entry.
  final List<FileManagerAction> actions;

  final bool searchActive;
  final VoidCallback onToggleSearch;

  final SortBy sortBy;
  final bool sortAscending;
  final ValueChanged<SortBy> onSortChanged;

  final String? currentFilter;
  final ValueChanged<String?> onFilterChanged;
  final bool hideVaultOnlyActions;

  final BrowserLayoutMode layoutMode;
  final ValueChanged<BrowserLayoutMode> onLayoutModeChanged;
  final GridAspectRatio gridAspectRatio;
  final ValueChanged<GridAspectRatio>? onGridAspectRatioChanged;

  final bool canPlayMedia;
  final VoidCallback onPlayMedia;

  const FileManagerMoreMenuButton({
    super.key,
    required this.actions,
    required this.searchActive,
    required this.onToggleSearch,
    required this.sortBy,
    required this.sortAscending,
    required this.onSortChanged,
    required this.currentFilter,
    required this.onFilterChanged,
    required this.hideVaultOnlyActions,
    required this.layoutMode,
    required this.onLayoutModeChanged,
    required this.gridAspectRatio,
    this.onGridAspectRatioChanged,
    required this.canPlayMedia,
    required this.onPlayMedia,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;

    Widget? entryFor(FileManagerAction action) {
      switch (action) {
        case FileManagerAction.add:
          return null; // Promoted to its own FAB; never shown here.
        case FileManagerAction.search:
          return MenuItemButton(
            leadingIcon: Icon(
              searchActive ? Icons.search_off_rounded : Icons.search_rounded,
              color: cs.primary,
            ),
            onPressed: onToggleSearch,
            child: Text(
              searchActive ? l10n.closeSearchTooltip : l10n.searchInThisFolderTooltip,
            ),
          );
        case FileManagerAction.viewToggle:
          return SubmenuButton(
            leadingIcon: Icon(Icons.grid_view_rounded, color: cs.primary),
            menuChildren: buildLayoutModeMenuItems(
              context: context,
              cs: cs,
              layoutMode: layoutMode,
              onLayoutModeChanged: onLayoutModeChanged,
              gridAspectRatio: gridAspectRatio,
              onGridAspectRatioChanged: onGridAspectRatioChanged,
            ),
            child: Text(l10n.viewModeAction),
          );
        case FileManagerAction.sort:
          return SubmenuButton(
            leadingIcon: Icon(Icons.sort_by_alpha_rounded, color: cs.primary),
            menuChildren: buildSortMenuItems(
              context: context,
              cs: cs,
              sortBy: sortBy,
              sortAscending: sortAscending,
              onSortChanged: onSortChanged,
            ),
            child: Text(l10n.sortAction),
          );
        case FileManagerAction.filter:
          final isFilterActive = currentFilter != null;
          return SubmenuButton(
            leadingIcon: Icon(
              isFilterActive ? Icons.filter_alt_rounded : Icons.filter_alt_outlined,
              color: cs.primary,
            ),
            menuChildren: buildFilterMenuItems(
              context: context,
              cs: cs,
              currentFilter: currentFilter,
              onFilterChanged: onFilterChanged,
              hideVaultOnlyActions: hideVaultOnlyActions,
            ),
            child: Text(l10n.filterAction),
          );
        case FileManagerAction.playMedia:
          return MenuItemButton(
            leadingIcon: Icon(
              Icons.play_circle_outline_rounded,
              color: canPlayMedia ? cs.primary : cs.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            onPressed: canPlayMedia ? onPlayMedia : null,
            child: Text(l10n.playMediaAction),
          );
      }
    }

    final entries = actions.map(entryFor).whereType<Widget>().toList(growable: false);
    if (entries.isEmpty) return const SizedBox.shrink();

    return MenuAnchor(
      builder: (context, controller, child) => Material(
        color: cs.surfaceContainerHighest,
        shape: const CircleBorder(),
        elevation: 4,
        shadowColor: Colors.black45,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => controller.isOpen ? controller.close() : controller.open(),
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(Icons.more_horiz_rounded, color: cs.onSurface),
          ),
        ),
      ),
      menuChildren: entries,
    );
  }
}