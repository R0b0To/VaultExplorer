import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';

part 'camera_capture_lock_controller.g.dart';

/// Per-camera-screen projection of the vault lock event.
///
/// The native camera session and recorder stay widget-owned because their
/// teardown must remain coupled to the platform texture and app lifecycle.
@riverpod
class CameraCaptureLock extends _$CameraCaptureLock {
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
