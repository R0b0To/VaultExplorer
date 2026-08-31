// VaultItemDetailScreen was a StatefulWidget holding the displayed item,
// current file path, container-locked flag, and per-field reveal toggles
// directly as State fields. Family-keyed by (volId, filePath, initialItem):
// a fresh screen instance is pushed per item, so this scopes cleanly to
// "this screen's session" the same way FileBrowserSelection/Sort scope to
// a container. `initialItem`/`filePath` only seed the state -- once
// loaded, the current values live in `state.item`/`state.filePath`, not
// re-read from the family key.
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/vault_item.dart';
import 'package:vaultexplorer/data/services/vault_items_service.dart';

part 'vault_item_detail_controller.g.dart';

class VaultItemDetailState {
  final VaultItem item;
  final String filePath;
  final bool isContainerLocked;
  final Map<String, bool> revealed;

  const VaultItemDetailState({
    required this.item,
    required this.filePath,
    this.isContainerLocked = false,
    this.revealed = const {},
  });
}

@riverpod
class VaultItemDetail extends _$VaultItemDetail {
  @override
  VaultItemDetailState build(int volId, String filePath, VaultItem initialItem) {
    void onContainerLocked(int lockedVolId) {
      if (lockedVolId == volId) {
        state = VaultItemDetailState(
          item: state.item,
          filePath: state.filePath,
          isContainerLocked: true,
          revealed: state.revealed,
        );
      }
    }

    final engineEvents = ref.read(vaultEngineEventsProvider);
    engineEvents.addContainerLockedListener(onContainerLocked);
    ref.onDispose(
      () => engineEvents.removeContainerLockedListener(onContainerLocked),
    );

    return VaultItemDetailState(item: initialItem, filePath: filePath);
  }

  void toggleRevealed(String key) {
    final next = {...state.revealed};
    next[key] = !(next[key] ?? false);
    state = VaultItemDetailState(
      item: state.item,
      filePath: state.filePath,
      isContainerLocked: state.isContainerLocked,
      revealed: next,
    );
  }

  Future<void> delete(MountedContainer container) =>
      ref.read(vaultFileIoApiProvider).deleteFile(container, state.filePath);

  /// Called after VaultItemEditScreen returns a new file path (the edit
  /// may have renamed the item), reloading the saved item from disk.
  Future<void> reloadAfterEdit(
    MountedContainer container,
    String newFilePath,
  ) async {
    final updated = await ref
        .read(vaultItemsServiceProvider)
        .loadItem(container, newFilePath);
    if (updated != null && ref.mounted) {
      state = VaultItemDetailState(
        item: updated,
        filePath: newFilePath,
        isContainerLocked: state.isContainerLocked,
        revealed: state.revealed,
      );
    }
  }

  Future<void> toggleBookmark(MountedContainer container) async {
    final updated = state.item.copyWithBookmark(!state.item.bookmark);
    await ref
        .read(vaultItemsServiceProvider)
        .saveItem(container, state.filePath, updated);
    if (ref.mounted) {
      state = VaultItemDetailState(
        item: updated,
        filePath: state.filePath,
        isContainerLocked: state.isContainerLocked,
        revealed: state.revealed,
      );
    }
  }
}
