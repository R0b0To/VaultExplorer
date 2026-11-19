import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/features/browser/gallery/filter/gallery_meta_index.dart';

/// Session memory for gallery metadata that has no writable persistent store.
///
/// It stays alive when a gallery view is replaced by the regular file view, so
/// toggling gallery mode does not reread every image. Vault entries are removed
/// as soon as that container locks.
final galleryMetaMemoryProvider = Provider<GalleryMetaMemory>((ref) {
  final memory = GalleryMetaMemory.app;
  final events = ref.watch(vaultEngineEventsProvider);

  void onContainerLocked(int volId) => memory.clear(volId);

  events.addContainerLockedListener(onContainerLocked);
  ref.onDispose(() {
    events.removeContainerLockedListener(onContainerLocked);
    memory.clear();
  });

  return memory;
});
