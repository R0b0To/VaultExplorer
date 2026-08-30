// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'unlock_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(UnlockController)
final unlockControllerProvider = UnlockControllerFamily._();

final class UnlockControllerProvider
    extends $NotifierProvider<UnlockController, UnlockState> {
  UnlockControllerProvider._({
    required UnlockControllerFamily super.from,
    required UnlockParams super.argument,
  }) : super(
         retry: null,
         name: r'unlockControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$unlockControllerHash();

  @override
  String toString() {
    return r'unlockControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  UnlockController create() => UnlockController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(UnlockState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<UnlockState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is UnlockControllerProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$unlockControllerHash() => r'f45a4bfc0db5558e4932e4f7ef504c3a39f37930';

final class UnlockControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          UnlockController,
          UnlockState,
          UnlockState,
          UnlockState,
          UnlockParams
        > {
  UnlockControllerFamily._()
    : super(
        retry: null,
        name: r'unlockControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  UnlockControllerProvider call(UnlockParams params) =>
      UnlockControllerProvider._(argument: params, from: this);

  @override
  String toString() => r'unlockControllerProvider';
}

abstract class _$UnlockController extends $Notifier<UnlockState> {
  late final _$args = ref.$arg as UnlockParams;
  UnlockParams get params => _$args;

  UnlockState build(UnlockParams params);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<UnlockState, UnlockState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<UnlockState, UnlockState>,
              UnlockState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
