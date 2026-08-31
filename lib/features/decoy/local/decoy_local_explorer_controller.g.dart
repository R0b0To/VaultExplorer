// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'decoy_local_explorer_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(DecoyLocalExplorer)
final decoyLocalExplorerProvider = DecoyLocalExplorerProvider._();

final class DecoyLocalExplorerProvider
    extends $NotifierProvider<DecoyLocalExplorer, DecoyLocalExplorerState> {
  DecoyLocalExplorerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'decoyLocalExplorerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$decoyLocalExplorerHash();

  @$internal
  @override
  DecoyLocalExplorer create() => DecoyLocalExplorer();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DecoyLocalExplorerState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DecoyLocalExplorerState>(value),
    );
  }
}

String _$decoyLocalExplorerHash() =>
    r'e094a2d6592fbcfa5497b2b15f31bcb15d1a0718';

abstract class _$DecoyLocalExplorer extends $Notifier<DecoyLocalExplorerState> {
  DecoyLocalExplorerState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<DecoyLocalExplorerState, DecoyLocalExplorerState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<DecoyLocalExplorerState, DecoyLocalExplorerState>,
              DecoyLocalExplorerState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
