import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/models/file_item_action.dart';
import 'package:vaultexplorer/features/settings/file_manager_toolbar_settings_controller.dart';

/// Lets the user choose which item actions are shown, and in what order, in
/// the item actions sheet and the selection bar's overflow menu.
///
/// The quick actions (the sheet's horizontal row) and the menu list are
/// ordered separately, mirroring how the sheet lays them out, and an action can
/// be moved from one to the other. Both orders come from the single
/// `itemActionsOrder` list; which section an action is in is
/// `quickItemActions`.
class FileManagerItemActionsScreen extends ConsumerWidget {
  final String? containerUri;
  const FileManagerItemActionsScreen({super.key, this.containerUri});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = fileManagerToolbarSettingsProvider(containerUri);
    final state = ref.watch(provider);
    final notifier = ref.read(provider.notifier);
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final order = state.config.itemActionsOrder;
    final quickSet = state.config.quickItemActions;
    final quickActions = order.where(quickSet.contains).toList();
    final menuActions = order.where((a) => !quickSet.contains(a)).toList();
    final quickRowFull = quickActions.length >= FileItemAction.maxQuickActions;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.l10n.itemActionsMenuTitle,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.restart_alt_rounded),
            tooltip: context.l10n.resetToDefaultsTooltip,
            onPressed: notifier.resetItemActions,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                  child: Text(
                    context.l10n.itemActionsMenuDesc,
                    style: textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
                SectionHeader(
                  '${context.l10n.itemActionsQuickRowHeader} '
                  '(${quickActions.length}/${FileItemAction.maxQuickActions})',
                ),
                _ItemActionSection(
                  actions: quickActions,
                  hidden: state.config.hiddenItemActions,
                  onReorder: (oldIndex, newIndex) =>
                      notifier.reorderItemActions(true, oldIndex, newIndex),
                  onToggle: notifier.toggleItemActionVisible,
                  moveIcon: Icons.arrow_downward_rounded,
                  moveTooltip: context.l10n.itemActionsMoveToMenuList,
                  canMove: true,
                  onMove: (action) =>
                      notifier.setItemActionInQuickRow(action, false),
                ),
                SectionHeader(context.l10n.itemActionsMenuListHeader),
                _ItemActionSection(
                  actions: menuActions,
                  hidden: state.config.hiddenItemActions,
                  onReorder: (oldIndex, newIndex) =>
                      notifier.reorderItemActions(false, oldIndex, newIndex),
                  onToggle: notifier.toggleItemActionVisible,
                  moveIcon: Icons.arrow_upward_rounded,
                  moveTooltip: context.l10n.itemActionsMoveToQuickRow,
                  canMove: !quickRowFull,
                  onMove: (action) =>
                      notifier.setItemActionInQuickRow(action, true),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One reorderable card-list of item actions (a switch and a drag handle per
/// row), styled like the toolbar and detail-column lists.
class _ItemActionSection extends StatelessWidget {
  final List<FileItemAction> actions;
  final Set<FileItemAction> hidden;
  final void Function(int oldIndex, int newIndex) onReorder;
  final Future<void> Function(FileItemAction action, bool visible) onToggle;

  /// Moves an action to the other section. [canMove] is false when that
  /// section cannot take another one (the quick row is full).
  final IconData moveIcon;
  final String moveTooltip;
  final bool canMove;
  final Future<void> Function(FileItemAction action) onMove;

  const _ItemActionSection({
    required this.actions,
    required this.hidden,
    required this.onReorder,
    required this.onToggle,
    required this.moveIcon,
    required this.moveTooltip,
    required this.canMove,
    required this.onMove,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: actions.length,
      onReorderItem: onReorder,
      itemBuilder: (context, i) {
        final action = actions[i];
        final visible = !hidden.contains(action);
        // Delete keeps its danger accent, matching the menus.
        final accent = action == FileItemAction.delete ? cs.error : cs.primary;
        return Padding(
          key: ValueKey(action),
          padding: const EdgeInsets.only(bottom: 2),
          child: Material(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(i == 0 ? 20 : 4),
              bottom: Radius.circular(i == actions.length - 1 ? 20 : 4),
            ),
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 2,
              ),
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: visible
                      ? accent.withValues(alpha: 0.12)
                      : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  action.icon,
                  size: 20,
                  color: visible
                      ? accent
                      : cs.onSurfaceVariant.withValues(alpha: 0.5),
                ),
              ),
              title: Text(
                action.getLocalizedLabel(context.l10n),
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: visible
                      ? cs.onSurface
                      : cs.onSurfaceVariant.withValues(alpha: 0.6),
                ),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(moveIcon, size: 20),
                    tooltip: moveTooltip,
                    visualDensity: VisualDensity.compact,
                    onPressed: canMove ? () => onMove(action) : null,
                  ),
                  Switch(
                    value: visible,
                    onChanged: (v) => onToggle(action, v),
                  ),
                  const SizedBox(width: 4),
                  ReorderableDragStartListener(
                    index: i,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest.withValues(
                          alpha: 0.5,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.drag_handle_rounded,
                        color: cs.onSurfaceVariant,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
