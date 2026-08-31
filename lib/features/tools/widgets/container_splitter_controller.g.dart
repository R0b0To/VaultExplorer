// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'container_splitter_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ContainerSplitter)
final containerSplitterProvider = ContainerSplitterProvider._();

final class ContainerSplitterProvider
    extends $NotifierProvider<ContainerSplitter, ContainerSplitterState> {
  ContainerSplitterProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'containerSplitterProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$containerSplitterHash();

  @$internal
  @override
  ContainerSplitter create() => ContainerSplitter();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ContainerSplitterState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ContainerSplitterState>(value),
    );
  }
}

String _$containerSplitterHash() => r'3ece5cf3c606c4af1096798f40dc1a9d9dc44191';

abstract class _$ContainerSplitter extends $Notifier<ContainerSplitterState> {
  ContainerSplitterState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<ContainerSplitterState, ContainerSplitterState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ContainerSplitterState, ContainerSplitterState>,
              ContainerSplitterState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
