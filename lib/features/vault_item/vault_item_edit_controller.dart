// VaultItemEditScreen keeps its TextEditingControllers (title + one per
// dynamic field), the field schema, and dirty-tracking local -- those are
// genuinely tied to Flutter's widget lifecycle and to each other (fields
// and their controllers are created together in didChangeDependencies()
// using context.l10n, which a Notifier has no access to). What moves out
// here is exactly the domain/async part: the container-locked listener and
// the actual save (uniqueness resolution, rename-on-title-change, item
// persistence).
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/file_operation.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/vault_item.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/data/services/vault_items_service.dart';

part 'vault_item_edit_controller.g.dart';

class VaultItemEditState {
  final bool isContainerLocked;
  final bool saving;

  const VaultItemEditState({
    this.isContainerLocked = false,
    this.saving = false,
  });
}

@riverpod
class VaultItemEdit extends _$VaultItemEdit {
  @override
  VaultItemEditState build(int volId) {
    void onContainerLocked(int lockedVolId) {
      if (lockedVolId == volId) {
        state = VaultItemEditState(isContainerLocked: true, saving: state.saving);
      }
    }

    VaultExplorerApi.addContainerLockedListener(onContainerLocked);
    ref.onDispose(
      () => VaultExplorerApi.removeContainerLockedListener(onContainerLocked),
    );

    return const VaultItemEditState();
  }

  /// Runs validation-adjacent-but-not-validation logic: resolves a unique
  /// on-disk name, renames on-disk if an existing item's title changed,
  /// and persists the item. Returns the final saved path on success, null
  /// on failure -- the widget (which owns the TextEditingControllers this
  /// needs as plain values) decides what to do with either outcome.
  Future<String?> save({
    required MountedContainer container,
    required VaultItemType type,
    required VaultItem? existing,
    required String? filePath,
    required String currentDirPath,
    required String newTitle,
    required Map<String, String> fieldMap,
  }) async {
    state = VaultItemEditState(
      isContainerLocked: state.isContainerLocked,
      saving: true,
    );
    try {
      final isNew = existing == null;
      String finalPath = filePath ?? '';

      final destDirPath = isNew
          ? currentDirPath
          : (filePath!.contains('/')
                ? filePath.substring(0, filePath.lastIndexOf('/'))
                : '');

      final existingRaw =
          await vaultExplorerApi.listDirectory(container, destDirPath) ?? [];
      final existingNames = existingRaw
          .where((e) => !e.startsWith('System:'))
          .map((e) => RawEntry.parse(e).name.toLowerCase())
          .toSet();

      if (isNew) {
        final desiredName = '$newTitle.${type.name}';
        final uniqueName = FileOperationService.makeUniqueName(
          desiredName,
          existingNames,
        );
        finalPath = destDirPath.isEmpty
            ? uniqueName
            : '$destDirPath/$uniqueName';
      } else if (existing.title != newTitle) {
        final oldPath = filePath!;
        final oldName = oldPath.contains('/')
            ? oldPath.substring(oldPath.lastIndexOf('/') + 1)
            : oldPath;

        final namesExcludingSelf = existingNames.difference({
          oldName.toLowerCase(),
        });

        final desiredName = '$newTitle.${type.name}';
        final uniqueName = FileOperationService.makeUniqueName(
          desiredName,
          namesExcludingSelf,
        );
        final newPath = destDirPath.isEmpty
            ? uniqueName
            : '$destDirPath/$uniqueName';

        await vaultExplorerApi.renameFile(container, oldPath, newPath);
        finalPath = newPath;
      }

      final item = isNew
          ? VaultItem.create(type, newTitle).copyWithFields(fieldMap, newTitle)
          : existing.copyWithFields(fieldMap, newTitle);

      final ok = await ref
          .read(vaultItemsServiceProvider)
          .saveItem(container, finalPath, item);

      return ok ? finalPath : null;
    } finally {
      if (ref.mounted) {
        state = VaultItemEditState(
          isContainerLocked: state.isContainerLocked,
          saving: false,
        );
      }
    }
  }
}
