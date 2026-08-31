// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'duplicate_finder_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(DuplicateFinder)
final duplicateFinderProvider = DuplicateFinderProvider._();

final class DuplicateFinderProvider
    extends $NotifierProvider<DuplicateFinder, DuplicateFinderState> {
  DuplicateFinderProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'duplicateFinderProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$duplicateFinderHash();

  @$internal
  @override
  DuplicateFinder create() => DuplicateFinder();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DuplicateFinderState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DuplicateFinderState>(value),
    );
  }
}

String _$duplicateFinderHash() => r'965bff47c04c4d68330b56b99cc2e260ff1d27c3';

abstract class _$DuplicateFinder extends $Notifier<DuplicateFinderState> {
  DuplicateFinderState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<DuplicateFinderState, DuplicateFinderState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<DuplicateFinderState, DuplicateFinderState>,
              DuplicateFinderState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
