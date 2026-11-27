import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/responsive.dart';
import 'package:vaultexplorer/data/models/container_sort_mode.dart';
import 'package:vaultexplorer/data/models/dashboard_layout_mode.dart';
import 'package:vaultexplorer/data/models/vault_list_item.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/features/dashboard/vault_dashboard_controller.dart';
import 'package:vaultexplorer/features/dashboard/widgets/dashboard_empty_state.dart';
import 'package:vaultexplorer/features/dashboard/widgets/vault_card_row.dart';
import 'package:vaultexplorer/features/dashboard/widgets/vault_layout_views.dart';

/// Dashboard viewport content. The shell or standalone route owns all chrome.
class VaultDashboardContentView extends ConsumerWidget {
  final List<VaultListItem> items;
  final VaultDashboardViewState state;
  final AppSettings settings;
  final VoidCallback onAdd;

  /// False while the list is filtered: the shown indices no longer match the
  /// stored order, so dragging would reorder the wrong cards.
  final bool reorderEnabled;

  /// True when [items] is empty only because of the search filter.
  final bool filteredEmpty;
  final ValueChanged<VaultListItem> onOpen;
  final ValueChanged<VaultListItem> onEdit;
  final ValueChanged<VaultListItem> onDelete;

  const VaultDashboardContentView({
    super.key,
    required this.items,
    required this.state,
    required this.settings,
    required this.onAdd,
    this.reorderEnabled = true,
    this.filteredEmpty = false,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (items.isEmpty && !state.isLoading) {
      if (filteredEmpty) {
        return Center(
          child: Text(
            context.l10n.noResultsTitle,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        );
      }
      return EmptyState(onAdd: onAdd);
    }

    final layout = defaultTargetPlatform == TargetPlatform.android
        ? DashboardLayoutMode.cards
        : settings.dashboardLayoutMode;
    return LayoutBuilder(
      builder: (context, constraints) {
        final usable = constraints.maxWidth;
        final available = usable - _kGridSidePadding * 2;
        switch (layout) {
          case DashboardLayoutMode.cards:
            // Tablets and desktop windows lay the vaults out as a grid of
            // cards; a phone-sized viewport keeps the single reorderable
            // column.
            final columns = ScreenInfo.cardColumnsFor(
              available,
              maxColumns: null,
            );
            if (columns < 2) return _buildSingleColumn(context, ref, layout);
            return _buildGrid(context, ref, usable, columns, layout);
          case DashboardLayoutMode.grid:
            // Always at least two tiles per row, even on a phone.
            final fit = ScreenInfo.cardColumnsFor(
              available,
              minTileWidth: _kGridTileMinWidth,
              maxColumns: null,
            );
            return _buildGrid(context, ref, usable, fit < 2 ? 2 : fit, layout);
          case DashboardLayoutMode.list:
            // Rows flow into columns once a window is wide enough for two.
            final columns = ScreenInfo.cardColumnsFor(
              available,
              minTileWidth: _kListTileMinWidth,
              maxColumns: null,
            );
            if (columns < 2) return _buildSingleColumn(context, ref, layout);
            return _buildGrid(context, ref, usable, columns, layout);
          case DashboardLayoutMode.details:
            return _buildDetails(context, ref, usable);
        }
      },
    );
  }

  static const double _kGridSidePadding = 16;
  static const double _kGridGap = 14;
  static const double _kGridTileMinWidth = 150;
  static const double _kListTileMinWidth = 300;

  VaultCardRow _buildCardRow(
    WidgetRef ref,
    int index, {
    required bool dragEnabled,
    DashboardLayoutMode layout = DashboardLayoutMode.cards,
    double rowWidth = 0,
    Key? key,
  }) {
    final item = items[index];
    return VaultCardRow(
      key: key ?? ValueKey(item.uri),
      index: index,
      item: item,
      record: state.records[item.uri],
      appSettings: settings,
      onOpen: () => onOpen(item),
      onEdit: () => onEdit(item),
      onDelete: () => onDelete(item),
      onLocked: (volId) => ref
          .read(vaultDashboardControllerProvider.notifier)
          .onContainerLocked(volId),
      isRemoving: state.animatingOutUris.contains(item.uri),
      isInserting: state.animatingInUris.contains(item.uri),
      dragEnabled: dragEnabled,
      layout: layout,
      rowWidth: rowWidth,
    );
  }

  /// The multi-column layout: cards wrap into equally wide cells. Manual
  /// ordering works the same way as in the single column -- press and hold a
  /// card, then drop it on the card whose place it should take.
  Widget _buildGrid(
    BuildContext context,
    WidgetRef ref,
    double width,
    int columns,
    DashboardLayoutMode layout,
  ) {
    final cellWidth =
        (width - _kGridSidePadding * 2 - _kGridGap * (columns - 1)) / columns;
    final reorderable =
        reorderEnabled && settings.containerSortMode == ContainerSortMode.manual;

    Widget cell(int index) {
      final item = items[index];
      // The row does not use the list's own drag handle here: that one only
      // works inside a ReorderableListView.
      final card = _buildCardRow(ref, index, dragEnabled: false, layout: layout);
      Widget child = card;
      if (reorderable) {
        // Build the drag wrapper around `card`, never around `child`: the
        // builder below runs later, when `child` already is the DragTarget.
        child = DragTarget<int>(
          onWillAcceptWithDetails: (details) => details.data != index,
          onAcceptWithDetails: (details) => ref
              .read(vaultDashboardControllerProvider.notifier)
              .handleReorder(details.data, index),
          builder: (context, candidates, _) => LongPressDraggable<int>(
            data: index,
            feedback: Material(
              color: Colors.transparent,
              elevation: 8,
              borderRadius: BorderRadius.circular(AppRadius.xl),
              child: SizedBox(
                width: cellWidth,
                child: _buildCardRow(
                  ref,
                  index,
                  dragEnabled: false,
                  layout: layout,
                  key: ValueKey('drag_${item.uri}'),
                ),
              ),
            ),
            childWhenDragging: Opacity(
              opacity: 0.35,
              child: _buildCardRow(
                ref,
                index,
                dragEnabled: false,
                layout: layout,
                key: ValueKey('ghost_${item.uri}'),
              ),
            ),
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.xl),
                border: candidates.isEmpty
                    ? null
                    : Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: 2,
                      ),
              ),
              child: card,
            ),
          ),
        );
      }
      return SizedBox(
        key: ValueKey('cell_${item.uri}'),
        width: cellWidth,
        child: child,
      );
    }

    return Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: width,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            _kGridSidePadding,
            12,
            _kGridSidePadding,
            120,
          ),
          child: Wrap(
            spacing: _kGridGap,
            children: [for (var i = 0; i < items.length; i++) cell(i)],
          ),
        ),
      ),
    );
  }

  /// Shared drag look of the reorderable lists.
  Widget _dragProxy(Widget child, int index, Animation<double> animation) =>
      AnimatedBuilder(
        animation: animation,
        builder: (context, child) {
          final animValue = Curves.easeInOut.transform(animation.value);
          final elevation = Tween<double>(
            begin: 0,
            end: 8,
          ).transform(animValue);
          return Material(
            elevation: elevation,
            color: Colors.transparent,
            shadowColor: Theme.of(
              context,
            ).colorScheme.shadow.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(AppRadius.xl),
            child: child,
          );
        },
        child: child,
      );

  bool get _dragAllowed =>
      reorderEnabled && settings.containerSortMode == ContainerSortMode.manual;

  Widget _buildSingleColumn(
    BuildContext context,
    WidgetRef ref,
    DashboardLayoutMode layout,
  ) {
    final vaultList = ReorderableListView.builder(
      buildDefaultDragHandles: false,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
      itemCount: items.length,
      onReorderItem: (oldIndex, newIndex) => ref
          .read(vaultDashboardControllerProvider.notifier)
          .handleReorder(oldIndex, newIndex),
      proxyDecorator: _dragProxy,
      itemBuilder: (context, index) => _buildCardRow(
        ref,
        index,
        dragEnabled: _dragAllowed,
        layout: layout,
      ),
    );

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: vaultList,
      ),
    );
  }

  /// The table layout: a header row over full-width rows. Columns that do not
  /// fit drop out; on a phone the rows become two-line list rows.
  Widget _buildDetails(BuildContext context, WidgetRef ref, double usable) {
    final rowWidth = usable - _kGridSidePadding * 2;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            _kGridSidePadding,
            12,
            _kGridSidePadding,
            0,
          ),
          child: VaultDetailsHeader(width: rowWidth),
        ),
        Expanded(
          child: ReorderableListView.builder(
            buildDefaultDragHandles: false,
            padding: const EdgeInsets.fromLTRB(
              _kGridSidePadding,
              0,
              _kGridSidePadding,
              120,
            ),
            itemCount: items.length,
            onReorderItem: (oldIndex, newIndex) => ref
                .read(vaultDashboardControllerProvider.notifier)
                .handleReorder(oldIndex, newIndex),
            proxyDecorator: _dragProxy,
            itemBuilder: (context, index) => _buildCardRow(
              ref,
              index,
              dragEnabled: _dragAllowed,
              layout: DashboardLayoutMode.details,
              rowWidth: rowWidth,
            ),
          ),
        ),
      ],
    );
  }
}
