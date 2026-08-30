// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'session_lock_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(sessionLockController)
final sessionLockControllerProvider = SessionLockControllerProvider._();

final class SessionLockControllerProvider
    extends
        $FunctionalProvider<
          SessionLockController,
          SessionLockController,
          SessionLockController
        >
    with $Provider<SessionLockController> {
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
