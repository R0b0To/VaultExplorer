import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/data/models/vault_list_item.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/features/dashboard/widgets/container_card.dart';

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

    final card = SizedBox(
      width: double.infinity,
      child: switch (widget.item) {
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
      },
    );

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
                padding: const EdgeInsets.only(bottom: 14),
                child: _maybeDragWrap(child: card),
              ),
      ),
    );
  }
}