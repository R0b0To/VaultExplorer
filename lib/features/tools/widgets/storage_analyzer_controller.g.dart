// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'storage_analyzer_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(StorageAnalyzer)
final storageAnalyzerProvider = StorageAnalyzerProvider._();

final class StorageAnalyzerProvider
    extends $NotifierProvider<StorageAnalyzer, StorageAnalyzerState> {
  StorageAnalyzerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'storageAnalyzerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$storageAnalyzerHash();

  @$internal
  @override
  StorageAnalyzer create() => StorageAnalyzer();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(StorageAnalyzerState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<StorageAnalyzerState>(value),
    );
  }
}

String _$storageAnalyzerHash() => r'27c07f567cd13a1fbc1db630561005e0a32e1d7d';

abstract class _$StorageAnalyzer extends $Notifier<StorageAnalyzerState> {
  StorageAnalyzerState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<StorageAnalyzerState, StorageAnalyzerState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<StorageAnalyzerState, StorageAnalyzerState>,
              StorageAnalyzerState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
