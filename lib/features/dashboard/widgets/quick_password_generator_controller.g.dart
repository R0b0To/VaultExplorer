// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'quick_password_generator_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(QuickPasswordGenerator)
final quickPasswordGeneratorProvider = QuickPasswordGeneratorProvider._();

final class QuickPasswordGeneratorProvider
    extends
        $NotifierProvider<QuickPasswordGenerator, QuickPasswordGeneratorState> {
  QuickPasswordGeneratorProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'quickPasswordGeneratorProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$quickPasswordGeneratorHash();

  @$internal
  @override
  QuickPasswordGenerator create() => QuickPasswordGenerator();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(QuickPasswordGeneratorState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<QuickPasswordGeneratorState>(value),
    );
  }
}

String _$quickPasswordGeneratorHash() =>
    r'ae4db187570138503c6e062f66fec6542a73d585';

abstract class _$QuickPasswordGenerator
    extends $Notifier<QuickPasswordGeneratorState> {
  QuickPasswordGeneratorState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<QuickPasswordGeneratorState, QuickPasswordGeneratorState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                QuickPasswordGeneratorState,
                QuickPasswordGeneratorState
              >,
              QuickPasswordGeneratorState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
