// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'session_lock_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Was constructed directly by VaultDashboardState (with the 3 callbacks
/// passed to its constructor); a @riverpod keepAlive function provider
/// can't take widget-owned closures as construction params (they aren't
/// `==`-stable across rebuilds, which breaks Riverpod's caching), so the
/// callbacks are now supplied once via [configure] from the owning
/// screen's `initState` instead. Everything else -- the timer/lifecycle
/// logic itself -- is unchanged from the pre-Riverpod version.

@ProviderFor(sessionLockController)
final sessionLockControllerProvider = SessionLockControllerProvider._();

/// Was constructed directly by VaultDashboardState (with the 3 callbacks
/// passed to its constructor); a @riverpod keepAlive function provider
/// can't take widget-owned closures as construction params (they aren't
/// `==`-stable across rebuilds, which breaks Riverpod's caching), so the
/// callbacks are now supplied once via [configure] from the owning
/// screen's `initState` instead. Everything else -- the timer/lifecycle
/// logic itself -- is unchanged from the pre-Riverpod version.

final class SessionLockControllerProvider
    extends
        $FunctionalProvider<
          SessionLockController,
          SessionLockController,
          SessionLockController
        >
    with $Provider<SessionLockController> {
  /// Was constructed directly by VaultDashboardState (with the 3 callbacks
  /// passed to its constructor); a @riverpod keepAlive function provider
  /// can't take widget-owned closures as construction params (they aren't
  /// `==`-stable across rebuilds, which breaks Riverpod's caching), so the
  /// callbacks are now supplied once via [configure] from the owning
  /// screen's `initState` instead. Everything else -- the timer/lifecycle
  /// logic itself -- is unchanged from the pre-Riverpod version.
  SessionLockControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sessionLockControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sessionLockControllerHash();

  @$internal
  @override
  $ProviderElement<SessionLockController> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  SessionLockController create(Ref ref) {
    return sessionLockController(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SessionLockController value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SessionLockController>(value),
    );
  }
}

String _$sessionLockControllerHash() =>
    r'5f294df98f6780d6b7d4b0fe32c4817398746673';
