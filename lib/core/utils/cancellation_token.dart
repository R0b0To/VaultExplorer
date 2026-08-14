/// Cooperative cancellation flag shared by the app's long-running,
/// step-by-step operations (duplicate-finder scan, vault sync scan, hash
/// compute) -- previously each had its own copy of this same
/// `bool _cancelled` + `cancel()` / `isCancelled` shape
/// (`DuplicateFinderService.CancellationToken`,
/// `VaultSyncService.VaultSyncCancellationToken`,
/// `HashVerifierService.HashCancellationToken`).
///
/// The common case is purely cooperative: a loop polls [isCancelled]
/// between steps and stops on its own. For operations that need to
/// actively interrupt something already in flight instead -- e.g. firing
/// a native cancel call for an in-progress platform-channel operation --
/// [bindOnCancel] registers a callback that runs the moment [cancel] is
/// called. See `HashCancellationToken` in `hash_verifier_service.dart`
/// for a subclass that adds exactly that.
class CancellationToken {
  bool _cancelled = false;
  void Function()? _onCancel;

  bool get isCancelled => _cancelled;

  /// Registers a callback to run the moment [cancel] is called, in
  /// addition to flipping [isCancelled].
  void bindOnCancel(void Function() onCancel) {
    _onCancel = onCancel;
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _onCancel?.call();
  }
}
