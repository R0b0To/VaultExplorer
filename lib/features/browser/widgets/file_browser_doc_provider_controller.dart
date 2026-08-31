// Folder Document Provider Controller extracted from
// _FileBrowserScreenState. Family-keyed by the container's volId, same
// reasoning as the other FileBrowserScreen controllers: one screen
// instance covers a whole container's directory tree, and which folders
// are currently exposed to other apps via Android's Storage Access
// Framework is a per-container concern.
//
// Unlike the pins/bookmarks extraction, the original here already used
// immutable reconstruction correctly ({...set, path} / {...set}..remove) --
// nothing to fix, just relocate behind the same controller boundary the
// rest of this screen's coherent slices already use.
//
// mount/unmount can fail (native SAF call returning false); the original
// showed a snackbar directly via BuildContext, which a Notifier doesn't
// have. toggle()/unmount() return a bool so the widget decides what to
// show, matching TextEditorLoad.save()'s established shape elsewhere in
// this codebase (return an outcome, let the widget own presentation).
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/services/folder_document_provider_service.dart';

part 'file_browser_doc_provider_controller.g.dart';

@riverpod
class FileBrowserDocProvider extends _$FileBrowserDocProvider {
  @override
  Set<String> build(int volId) => const {};

  Future<void> refresh(MountedContainer container) async {
    final folders = await ref.read(folderDocumentProviderServiceProvider).loadMountedFolders(container);
    if (ref.mounted) state = folders;
  }

  /// Returns true on success. On failure, state is left unchanged and the
  /// widget shows its own "couldn't expose" message -- matches the
  /// original's early-return-before-mutating-state on a failed native call.
  Future<bool> toggle(MountedContainer container, String path, String displayName) async {
    final ok =
        await ref.read(folderDocumentProviderServiceProvider).mountNative(container, path, displayName);
    if (!ref.mounted || !ok) return false;
    state = {...state, path};
    await ref.read(folderDocumentProviderServiceProvider).persistExposed(container, path, exposed: true);
    return true;
  }

  /// Returns true on success, same reasoning as [toggle].
  Future<bool> unmount(MountedContainer container, String path) async {
    final ok = await ref.read(folderDocumentProviderServiceProvider).unmountNative(container, path);
    if (!ref.mounted || !ok) return false;
    state = {...state}..remove(path);
    await ref.read(folderDocumentProviderServiceProvider).persistExposed(container, path, exposed: false);
    return true;
  }
}
