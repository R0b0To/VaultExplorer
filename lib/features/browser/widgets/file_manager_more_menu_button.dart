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
///
/// When [actions] holds exactly one entry, a "More" button that only ever
/// reveals that one item is pure overhead -- one tap to open it, a second to
/// actually use it. In that case the button collapses onto the action
/// itself: the icon reflects the action directly (its current state, for
/// search/filter/view mode), and tapping it does what the single menu entry
/// would have done -- toggles it directly for search/play media, or opens
/// its options in one tap for view mode/sort/filter, instead of surfacing a
/// one-item "More" menu first.
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

    // Exactly one action enabled: the FAB *is* that action -- see class doc.
    if (actions.length == 1) {
      return _buildSingleActionFab(context, cs, l10n, actions.single);
    }

    return MenuAnchor(
      builder: (context, controller, child) => _fabShell(
        cs: cs,
        icon: Icon(Icons.more_horiz_rounded, color: cs.onSurface),
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
      ),
      menuChildren: entries,
    );
  }

  /// The circular 48dp Material/InkWell shell shared by the "More" button
  /// and every single-action collapse below, so they're visually identical
  /// regardless of which one is showing.
  Widget _fabShell({
    required ColorScheme cs,
    required Widget icon,
    required VoidCallback? onTap,
    String? tooltip,
  }) {
    final button = Material(
      color: cs.surfaceContainerHighest,
      shape: const CircleBorder(),
      elevation: 4,
      shadowColor: Colors.black45,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(width: 48, height: 48, child: icon),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip, child: button);
  }

  /// Builds the FAB for the single-enabled-action case: same shell, but the
  /// icon and tap behavior belong to [action] directly instead of an outer
  /// "More" menu. Search and Play media are direct toggles, so tapping does
  /// the thing. View mode/Sort/Filter are themselves option pickers, so
  /// tapping opens that one menu immediately -- the same `menuChildren`
  /// used inside "More" above, just reached in one tap instead of two.
  Widget _buildSingleActionFab(
    BuildContext context,
    ColorScheme cs,
    AppLocalizations l10n,
    FileManagerAction action,
  ) {
    Widget menuFab({
      required Widget icon,
      required List<Widget> menuChildren,
      required String tooltip,
    }) {
      return MenuAnchor(
        builder: (context, controller, child) => _fabShell(
          cs: cs,
          icon: icon,
          tooltip: tooltip,
          onTap: () => controller.isOpen ? controller.close() : controller.open(),
        ),
        menuChildren: menuChildren,
      );
    }

    switch (action) {
      case FileManagerAction.add:
        // Never reached: `add` is always split off into its own FAB before
        // `actions` reaches this widget (see _buildFabToolbar).
        return const SizedBox.shrink();

      case FileManagerAction.search:
        return _fabShell(
          cs: cs,
          icon: Icon(
            searchActive ? Icons.search_off_rounded : Icons.search_rounded,
            color: searchActive ? cs.primary : cs.onSurface,
          ),
          tooltip: searchActive ? l10n.closeSearchTooltip : l10n.searchInThisFolderTooltip,
          onTap: onToggleSearch,
        );

      case FileManagerAction.playMedia:
        return _fabShell(
          cs: cs,
          icon: Icon(
            Icons.play_circle_outline_rounded,
            color: canPlayMedia ? cs.onSurface : cs.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          tooltip: l10n.playMediaAction,
          onTap: canPlayMedia ? onPlayMedia : null,
        );

      case FileManagerAction.viewToggle:
        final currentIcon = switch (layoutMode) {
          BrowserLayoutMode.list => Icons.view_list_rounded,
          BrowserLayoutMode.detailed => Icons.view_agenda_rounded,
          BrowserLayoutMode.compact => Icons.list_rounded,
          BrowserLayoutMode.grid => Icons.grid_view_rounded,
          BrowserLayoutMode.masonry => Icons.dashboard_rounded,
        };
        return menuFab(
          icon: Icon(currentIcon, color: cs.onSurface),
          tooltip: l10n.layoutOptionsTooltip,
          menuChildren: buildLayoutModeMenuItems(
            context: context,
            cs: cs,
            layoutMode: layoutMode,
            onLayoutModeChanged: onLayoutModeChanged,
            gridAspectRatio: gridAspectRatio,
            onGridAspectRatioChanged: onGridAspectRatioChanged,
          ),
        );

      case FileManagerAction.sort:
        return menuFab(
          icon: Icon(Icons.sort_by_alpha_rounded, color: cs.onSurface),
          tooltip: l10n.sortOptionsTooltip,
          menuChildren: buildSortMenuItems(
            context: context,
            cs: cs,
            sortBy: sortBy,
            sortAscending: sortAscending,
            onSortChanged: onSortChanged,
          ),
        );

      case FileManagerAction.filter:
        final isFilterActive = currentFilter != null;
        return menuFab(
          icon: Icon(
            isFilterActive ? Icons.filter_alt_rounded : Icons.filter_alt_outlined,
            color: isFilterActive ? cs.primary : cs.onSurface,
          ),
          tooltip: l10n.filtersMenuItem,
          menuChildren: buildFilterMenuItems(
            context: context,
            cs: cs,
            currentFilter: currentFilter,
            onFilterChanged: onFilterChanged,
            hideVaultOnlyActions: hideVaultOnlyActions,
          ),
        );
    }
  }
}