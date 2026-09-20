import 'package:flutter_riverpod/flutter_riverpod.dart';

final syncLockBarrierProvider = Provider<SyncLockBarrier>(
  (ref) => SyncLockBarrier(),
);

/// Lets `VaultLifecycleApi.lockContainer` stop a vault's running sync
/// *before* the container is unmounted.
///
/// Same idea, and same reason for living behind `lockContainer`, as
/// `ActiveRecordingRegistry` (a camera recording has to be saved before its
/// container locks): a container can be locked by the screen-off setting,
/// the idle timer, the per-container auto-close timer or a tap on "Lock",
/// and every one of those already funnels through `lockContainer` -- so
/// that is the one place this is consulted, not each caller.
///
/// A lock that does *not* go through `lockContainer` (a force-lock, the
/// panic wipe, a USB unplug) can't wait for anyone, and shouldn't. The
/// engine survives that anyway: its native calls simply start failing, the
/// run winds down, and `.vexp_tmp` / `.vexp_old` leftovers are repaired at
/// the next unlock.
class SyncLockBarrier {
  final Map<String, Future<void> Function()> _handlers = {};

  /// [cancelAndWait] must cancel that container's sync work and complete
  /// once it has stopped (or given up waiting).
  void register(String containerUri, Future<void> Function() cancelAndWait) {
    _handlers[containerUri] = cancelAndWait;
  }

  void unregister(String containerUri) => _handlers.remove(containerUri);

  bool isActiveFor(String containerUri) => _handlers.containsKey(containerUri);

  /// Cancels any sync for [containerUri] and waits for it to stop. No-op
  /// when there is none. Never throws: a lock must not be blocked by it.
  Future<void> cancelAndWait(String containerUri) async {
    final handler = _handlers[containerUri];
    if (handler == null) return;
    try {
      await handler();
    } catch (_) {
      // Best effort: the container is about to be locked either way.
    }
  }
}
