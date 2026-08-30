// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'file_browser_sort_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(FileBrowserSort)
final fileBrowserSortProvider = FileBrowserSortFamily._();

final class FileBrowserSortProvider
    extends $NotifierProvider<FileBrowserSort, FileBrowserSortState> {
  FileBrowserSortProvider._({
    required FileBrowserSortFamily super.from,
    required int super.argument,
  }) : super(
         retry: null,
         name: r'fileBrowserSortProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$fileBrowserSortHash();

  @override
  String toString() {
    return r'fileBrowserSortProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  FileBrowserSort create() => FileBrowserSort();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(FileBrowserSortState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<FileBrowserSortState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is FileBrowserSortProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$fileBrowserSortHash() => r'1446e097b4e916a1fb478944165ac1dab2f17e94';

final class FileBrowserSortFamily extends $Family
    with
        $ClassFamilyOverride<
          FileBrowserSort,
          FileBrowserSortState,
          FileBrowserSortState,
          FileBrowserSortState,
          int
        > {
  FileBrowserSortFamily._()
    : super(
        retry: null,
        name: r'fileBrowserSortProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  FileBrowserSortProvider call(int volId) =>
      FileBrowserSortProvider._(argument: volId, from: this);

  @override
  String toString() => r'fileBrowserSortProvider';
}

abstract class _$FileBrowserSort extends $Notifier<FileBrowserSortState> {
  late final _$args = ref.$arg as int;
  int get volId => _$args;

  FileBrowserSortState build(int volId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<FileBrowserSortState, FileBrowserSortState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<FileBrowserSortState, FileBrowserSortState>,
              FileBrowserSortState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
