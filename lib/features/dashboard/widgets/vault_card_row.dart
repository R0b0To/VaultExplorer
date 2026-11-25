import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/data/models/dashboard_layout_mode.dart';
import 'package:vaultexplorer/data/models/vault_list_item.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/features/dashboard/widgets/container_card.dart';
import 'package:vaultexplorer/features/dashboard/widgets/vault_layout_views.dart';

class VaultCardRow extends StatefulWidget {
  final int index;
  final VaultListItem item;
  final ContainerRecord? record;
  final AppSettings appSettings;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<int> onLocked;
  final bool isRemoving;
  final bool isInserting;
  final bool dragEnabled;

  /// How this vault is drawn. [DashboardLayoutMode.cards] is the original card.
  final DashboardLayoutMode layout;

  /// Width of the row, needed only by [DashboardLayoutMode.details] to decide
  /// which columns fit.
  final double rowWidth;

  const VaultCardRow({
    super.key,
    required this.index,
    required this.item,
    required this.record,
    required this.appSettings,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
    required this.onLocked,
    this.isRemoving = false,
    this.isInserting = false,
    this.dragEnabled = true,
    this.layout = DashboardLayoutMode.cards,
    this.rowWidth = 0,
  });

  @override
  State<VaultCardRow> createState() => _VaultCardRowState();
}

class _VaultCardRowState extends State<VaultCardRow> {
  bool _isCurrentlyInserting = false;

  @override
  void initState() {
    super.initState();
    if (widget.isInserting) {
      _isCurrentlyInserting = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _isCurrentlyInserting = false);
        }
      });
    }
  }

  Widget _maybeDragWrap({required Widget child}) {
    if (!widget.dragEnabled) return child;
    return ReorderableDelayedDragStartListener(index: widget.index, child: child);
  }

  @override
  Widget build(BuildContext context) {
    final isHidden = widget.isRemoving || _isCurrentlyInserting;

    final Widget card = switch (widget.layout) {
      DashboardLayoutMode.cards => _cardView(),
      DashboardLayoutMode.grid => VaultGridTile(
        key: ValueKey('grid_${widget.item.uri}'),
        item: widget.item,
        record: widget.record,
        appSettings: widget.appSettings,
        onOpen: widget.onOpen,
        onEdit: widget.onEdit,
        onDelete: widget.onDelete,
        onLocked: widget.onLocked,
      ),
      DashboardLayoutMode.list => VaultListTile(
        key: ValueKey('list_${widget.item.uri}'),
        item: widget.item,
        record: widget.record,
        appSettings: widget.appSettings,
        onOpen: widget.onOpen,
        onEdit: widget.onEdit,
        onDelete: widget.onDelete,
        onLocked: widget.onLocked,
      ),
      DashboardLayoutMode.details => VaultDetailsRow(
        key: ValueKey('details_${widget.item.uri}'),
        item: widget.item,
        record: widget.record,
        appSettings: widget.appSettings,
        onOpen: widget.onOpen,
        onEdit: widget.onEdit,
        onDelete: widget.onDelete,
        onLocked: widget.onLocked,
        width: widget.rowWidth,
      ),
    };

    // The details table is one continuous surface: its rows carry their own
    // divider instead of a gap.
    final bottomGap = switch (widget.layout) {
      DashboardLayoutMode.cards || DashboardLayoutMode.grid => 14.0,
      DashboardLayoutMode.list => 8.0,
      DashboardLayoutMode.details => 0.0,
    };

    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 300),
        opacity: isHidden ? 0.0 : 1.0,
        child: isHidden
            ? const SizedBox(width: double.infinity, height: 0)
            : Padding(
                padding: EdgeInsets.only(bottom: bottomGap),
                child: _maybeDragWrap(
                  child: SizedBox(width: double.infinity, child: card),
                ),
              ),
      ),
    );
  }

  Widget _cardView() => switch (widget.item) {
        MountedVaultItem(:final container) => ContainerCard(
            key: ValueKey('mounted_${widget.item.uri}'),
            container: container,
            record: widget.record,
            appSettings: widget.appSettings,
            onLocked: widget.onLocked,
            onBrowse: widget.onOpen,
            onEdit: widget.onEdit,
            onDelete: widget.onDelete,
          ),
        LockedVaultItem(:final record) => SavedContainerCard(
            key: ValueKey('locked_${widget.item.uri}'),
            name: widget.item.name,
            uri: widget.item.uri,
            containerFormat: record.containerFormat,
            onUnlock: widget.onOpen,
            onEdit: widget.onEdit,
            onDelete: widget.onDelete,
          ),
      };
}