import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';

part 'media_viewer_lock_controller.g.dart';

/// Per-viewer projection of the application-wide container-lock event.
///
/// Playback controllers, timers, and platform-view gesture state remain owned
/// by MediaViewerScreen. The vault-lock event is shared asynchronous state and
/// is therefore kept in this family provider.
@riverpod
class MediaViewerLock extends _$MediaViewerLock {
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
