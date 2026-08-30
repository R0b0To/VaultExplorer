import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/providers/legacy_services_providers.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/container_repository.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';

part 'folder_document_provider_service.g.dart';

/// No internal mutable state of its own -> pure keep-alive provider per the
/// migration plan's Phase 3 rule, constructor-injected with the shared
/// [ContainerRepository] through [containerRepositoryProvider] instead of
/// reaching for `ContainerRepository.instance` directly. There was exactly
/// one call site (`_FileBrowserScreenState`, already a `ConsumerState`), so
/// this went straight to the provider rather than keeping a transitional
/// `.instance` bridge.
@Riverpod(keepAlive: true)
FolderDocumentProviderService folderDocumentProviderService(Ref ref) =>
    FolderDocumentProviderService(ref.watch(containerRepositoryProvider));

/// Exposing/unexposing a vault subfolder to other Android apps via the SAF
/// DocumentsProvider, plus persisting that choice (and auto-mount-on-unlock)
/// in [ContainerRepository]. Pulled out of `_FileBrowserScreenState` so this
/// I/O logic can be exercised without a widget tree, and so a future format
/// (or a bug fix here) only needs to change in one place.
///
/// Deliberately stateless: the mounted-folders set itself stays owned by
/// the State class, since it's read on every rebuild via `isFolderMounted`
/// callbacks threaded through the app-bar/body builders -- moving that
/// ownership here too is a larger, separate change from this pass.
///
/// mount/unmount are split from persistExposed (rather than one combined
/// call) so callers can update local UI state in between the two awaits --
/// exactly the ordering `_FileBrowserScreenState` used before this
/// extraction: flip the UI as soon as the native call succeeds, persist
/// afterward without blocking that UI update on a repository write.
class FolderDocumentProviderService {
  const FolderDocumentProviderService(this._containerRepository);

  final ContainerRepository _containerRepository;

  /// Every path (relative to the container root) currently exposed via the
  /// DocumentsProvider for [container].
  Future<Set<String>> loadMountedFolders(MountedContainer container) async {
    final paths = await vaultExplorerApi.getMountedContainerFolders(container.uri);
    return paths.toSet();
  }

  /// Exposes [path] (display name [displayName]) via the DocumentsProvider.
  /// Does not persist -- call [persistExposed] afterward.
  Future<bool> mountNative(MountedContainer container, String path, String displayName) {
    return vaultExplorerApi.mountContainerFolder(
      container.uri,
      path,
      displayName: displayName,
    );
  }

  /// Un-exposes [path] via the DocumentsProvider. Does not persist -- call
  /// [persistExposed] afterward.
  Future<bool> unmountNative(MountedContainer container, String path) {
    return vaultExplorerApi.unmountContainerFolder(container.uri, path);
  }

  Future<void> persistExposed(MountedContainer container, String path, {required bool exposed}) {
    return _containerRepository.setFolderExposed(container.uri, path, exposed: exposed);
  }

  Future<void> setAutoMount(MountedContainer container, String path, bool autoMount) {
    return _containerRepository.setFolderAutoMount(container.uri, path, autoMount);
  }
}
