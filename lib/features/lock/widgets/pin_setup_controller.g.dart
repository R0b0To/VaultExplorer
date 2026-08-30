// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pin_setup_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(PinSetup)
final pinSetupProvider = PinSetupProvider._();

final class PinSetupProvider
    extends $NotifierProvider<PinSetup, PinSetupState> {
  PinSetupProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'pinSetupProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$pinSetupHash();

  @$internal
  @override
  PinSetup create() => PinSetup();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PinSetupState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PinSetupState>(value),
    );
  }
}

String _$pinSetupHash() => r'caaa9a4736faee07493423a03eb31209662aad3a';

abstract class _$PinSetup extends $Notifier<PinSetupState> {
  PinSetupState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<PinSetupState, PinSetupState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<PinSetupState, PinSetupState>,
              PinSetupState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
