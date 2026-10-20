// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'file_browser_search_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(FileBrowserSearch)
final fileBrowserSearchProvider = FileBrowserSearchFamily._();

final class FileBrowserSearchProvider
    extends $NotifierProvider<FileBrowserSearch, FileBrowserSearchState> {
  FileBrowserSearchProvider._({
    required FileBrowserSearchFamily super.from,
    required TabId super.argument,
  }) : super(
         retry: null,
         name: r'fileBrowserSearchProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$fileBrowserSearchHash();

  @override
  String toString() {
    return r'fileBrowserSearchProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  FileBrowserSearch create() => FileBrowserSearch();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(FileBrowserSearchState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<FileBrowserSearchState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is FileBrowserSearchProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$fileBrowserSearchHash() => r'c8353f0ea2ae0ae0252859a7ced80afac660f805';

final class FileBrowserSearchFamily extends $Family
    with
        $ClassFamilyOverride<
          FileBrowserSearch,
          FileBrowserSearchState,
          FileBrowserSearchState,
          FileBrowserSearchState,
          TabId
        > {
  FileBrowserSearchFamily._()
    : super(
        retry: null,
        name: r'fileBrowserSearchProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  FileBrowserSearchProvider call(TabId tabId) =>
      FileBrowserSearchProvider._(argument: tabId, from: this);

  @override
  String toString() => r'fileBrowserSearchProvider';
}

abstract class _$FileBrowserSearch extends $Notifier<FileBrowserSearchState> {
  late final _$args = ref.$arg as TabId;
  TabId get tabId => _$args;

  FileBrowserSearchState build(TabId tabId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<FileBrowserSearchState, FileBrowserSearchState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<FileBrowserSearchState, FileBrowserSearchState>,
              FileBrowserSearchState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
