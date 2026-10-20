import 'package:flutter/material.dart' hide ReorderableListView;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' show ReorderableListView;
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/data/models/container_sort_mode.dart';
import 'package:vaultexplorer/data/models/vault_list_item.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/features/dashboard/vault_dashboard_controller.dart';
import 'package:vaultexplorer/features/dashboard/widgets/dashboard_empty_state.dart';
import 'package:vaultexplorer/features/dashboard/widgets/vault_card_row.dart';

/// Dashboard viewport content. The shell or standalone route owns all chrome.
class VaultDashboardContentView extends ConsumerWidget {
  final List<VaultListItem> items;
  final VaultDashboardViewState state;
  final AppSettings settings;
  final VoidCallback onAdd;
  final ValueChanged<VaultListItem> onOpen;
  final ValueChanged<VaultListItem> onEdit;
  final ValueChanged<VaultListItem> onDelete;

  const VaultDashboardContentView({
    super.key,
    required this.items,
    required this.state,
    required this.settings,
    required this.onAdd,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (items.isEmpty && !state.isLoading) {
      return EmptyState(onAdd: onAdd);
    }

    final vaultList = ReorderableListView.builder(
      buildDefaultDragHandles: false,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
      itemCount: items.length,
      onReorderItem: (oldIndex, newIndex) => ref
          .read(vaultDashboardControllerProvider.notifier)
          .handleReorder(oldIndex, newIndex),
      proxyDecorator: (child, index, animation) => AnimatedBuilder(
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
      ),
      itemBuilder: (context, index) {
        final item = items[index];
        return VaultCardRow(
          key: ValueKey(item.uri),
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
          dragEnabled: settings.containerSortMode == ContainerSortMode.manual,
        );
      },
    );

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: vaultList,
      ),
    );
  }
}
