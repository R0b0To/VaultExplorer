// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'lock_gate_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(LockGate)
final lockGateProvider = LockGateProvider._();

final class LockGateProvider
    extends $NotifierProvider<LockGate, LockGateState> {
  LockGateProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'lockGateProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$lockGateHash();

  @$internal
  @override
  LockGate create() => LockGate();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LockGateState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LockGateState>(value),
    );
  }
}

String _$lockGateHash() => r'd3c9abf3bd2ac04305f2c296ffd616211792d6b2';

abstract class _$LockGate extends $Notifier<LockGateState> {
  LockGateState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<LockGateState, LockGateState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<LockGateState, LockGateState>,
              LockGateState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
