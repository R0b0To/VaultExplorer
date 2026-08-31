// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pattern_setup_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(PatternSetup)
final patternSetupProvider = PatternSetupProvider._();

final class PatternSetupProvider
    extends $NotifierProvider<PatternSetup, PatternSetupState> {
  PatternSetupProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'patternSetupProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$patternSetupHash();

  @$internal
  @override
  PatternSetup create() => PatternSetup();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PatternSetupState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PatternSetupState>(value),
    );
  }
}

String _$patternSetupHash() => r'21ec16b3039a178ca1d5a1f52b1d6aac3c472801';

abstract class _$PatternSetup extends $Notifier<PatternSetupState> {
  PatternSetupState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<PatternSetupState, PatternSetupState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<PatternSetupState, PatternSetupState>,
              PatternSetupState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
