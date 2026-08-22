/// Tracks whether a container currently has an in-progress camera
/// recording writing into it, and how to stop it cleanly.
///
/// This exists because a container can get locked from several
/// independent triggers -- the "lock on screen off" setting, the idle
/// autoLockMins timer, the per-container auto-close timer, or the user
/// just tapping "Lock" -- and none of them know or care whether a
/// recording happens to be running at that moment. Rather than teach
/// every one of those call sites about the camera screen, they all
/// already funnel through [VaultExplorerApi.lockContainer], so that's
/// the single place this registry is consulted: stop and save whatever
/// was recorded so far, then let the lock proceed.
///
/// CameraCaptureScreen registers itself here for the duration of a
/// recording (including one continuing in the background via
/// VaultCameraRecordingService) and unregisters the moment the recording
/// stops for any other reason.
class ActiveRecordingRegistry {
  ActiveRecordingRegistry._();
  static final ActiveRecordingRegistry instance = ActiveRecordingRegistry._();

  final Map<String, Future<void> Function()> _stopCallbacks = {};

  void register(String containerUri, Future<void> Function() gracefulStop) {
    _stopCallbacks[containerUri] = gracefulStop;
  }

  void unregister(String containerUri) {
    _stopCallbacks.remove(containerUri);
  }

  bool isActiveFor(String containerUri) => _stopCallbacks.containsKey(containerUri);

  /// If [containerUri] has an active recording, stops and saves it and
  /// waits for that to finish. No-op otherwise.
  Future<void> stopIfActive(String containerUri) async {
    final stop = _stopCallbacks[containerUri];
    if (stop == null) return;
    try {
      await stop();
    } catch (_) {
      // Best-effort: the container is about to be locked either way: an
      // exception here shouldn't be able to block that.
    }
  }
}
