import 'package:vaultexplorer/core/utils/cancellation_token.dart';

/// Thrown by an in-flight transfer that noticed [SyncCancellationToken]
/// was cancelled. Caught by the executor, which cleans up and stops.
class SyncCancelledException implements Exception {
  const SyncCancelledException();

  @override
  String toString() => 'SyncCancelledException';
}

/// The app-wide [CancellationToken] only keeps a single `bindOnCancel`
/// callback. A sync run needs several at once (cancel the native copy in
/// flight, cancel a hash session, ...), so this subclass keeps a list.
///
/// Still a plain [CancellationToken] to everything that only polls
/// [isCancelled].
class SyncCancellationToken extends CancellationToken {
  final List<void Function()> _listeners = [];

  /// Adds [onCancel] to the callbacks run when [cancel] is called; runs it
  /// immediately if the token is already cancelled.
  @override
  void bindOnCancel(void Function() onCancel) {
    if (isCancelled) {
      onCancel();
      return;
    }
    _listeners.add(onCancel);
  }

  /// Removes a callback added with [bindOnCancel] (call once the operation
  /// it guarded has finished).
  void unbind(void Function() onCancel) => _listeners.remove(onCancel);

  @override
  void cancel() {
    if (isCancelled) return;
    super.cancel();
    final pending = List<void Function()>.of(_listeners);
    _listeners.clear();
    for (final callback in pending) {
      try {
        callback();
      } catch (_) {
        // A failing cancel hook must not stop the others from running.
      }
    }
  }
}
