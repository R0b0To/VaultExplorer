// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'file_browser_pins_bookmarks_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(FileBrowserPinsBookmarks)
final fileBrowserPinsBookmarksProvider = FileBrowserPinsBookmarksFamily._();

final class FileBrowserPinsBookmarksProvider
    extends
        $NotifierProvider<
          FileBrowserPinsBookmarks,
          FileBrowserPinsBookmarksState
        > {
  FileBrowserPinsBookmarksProvider._({
    required FileBrowserPinsBookmarksFamily super.from,
    required int super.argument,
  }) : super(
         retry: null,
         name: r'fileBrowserPinsBookmarksProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$fileBrowserPinsBookmarksHash();

  @override
  String toString() {
    return r'fileBrowserPinsBookmarksProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  FileBrowserPinsBookmarks create() => FileBrowserPinsBookmarks();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(FileBrowserPinsBookmarksState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<FileBrowserPinsBookmarksState>(
        value,
      ),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is FileBrowserPinsBookmarksProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$fileBrowserPinsBookmarksHash() =>
    r'3087cd88b68b3513302599bdf5e1e846c9f524e8';

final class FileBrowserPinsBookmarksFamily extends $Family
    with
        $ClassFamilyOverride<
          FileBrowserPinsBookmarks,
          FileBrowserPinsBookmarksState,
          FileBrowserPinsBookmarksState,
          FileBrowserPinsBookmarksState,
          int
        > {
  FileBrowserPinsBookmarksFamily._()
    : super(
        retry: null,
        name: r'fileBrowserPinsBookmarksProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  FileBrowserPinsBookmarksProvider call(int volId) =>
      FileBrowserPinsBookmarksProvider._(argument: volId, from: this);

  @override
  String toString() => r'fileBrowserPinsBookmarksProvider';
}

abstract class _$FileBrowserPinsBookmarks
    extends $Notifier<FileBrowserPinsBookmarksState> {
  late final _$args = ref.$arg as int;
  int get volId => _$args;

  FileBrowserPinsBookmarksState build(int volId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              FileBrowserPinsBookmarksState,
              FileBrowserPinsBookmarksState
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                FileBrowserPinsBookmarksState,
                FileBrowserPinsBookmarksState
              >,
              FileBrowserPinsBookmarksState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
