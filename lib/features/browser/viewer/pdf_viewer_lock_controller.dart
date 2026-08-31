import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';

part 'pdf_viewer_lock_controller.g.dart';

/// Tracks whether the vault backing one PDF-viewer instance has locked.
///
/// PDF rendering, scrolling, zoom, and chrome remain local to the viewer;
/// only the cross-cutting engine event belongs in Riverpod.
@riverpod
class PdfViewerLock extends _$PdfViewerLock {
  @override
  bool build(int volId) {
    void onContainerLocked(int lockedVolId) {
      if (lockedVolId == volId) state = true;
    }

    final events = ref.read(vaultEngineEventsProvider);
    events.addContainerLockedListener(onContainerLocked);
    ref.onDispose(
      () => events.removeContainerLockedListener(onContainerLocked),
    );
    return false;
  }
}
