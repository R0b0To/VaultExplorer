// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'file_browser_selection_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(FileBrowserSelection)
final fileBrowserSelectionProvider = FileBrowserSelectionFamily._();

final class FileBrowserSelectionProvider
    extends $NotifierProvider<FileBrowserSelection, FileBrowserSelectionState> {
  FileBrowserSelectionProvider._({
    required FileBrowserSelectionFamily super.from,
    required TabId super.argument,
  }) : super(
         retry: null,
         name: r'fileBrowserSelectionProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$fileBrowserSelectionHash();

  @override
  String toString() {
    return r'fileBrowserSelectionProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  FileBrowserSelection create() => FileBrowserSelection();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(FileBrowserSelectionState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<FileBrowserSelectionState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is FileBrowserSelectionProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$fileBrowserSelectionHash() =>
    r'cc0a0826a87c05d7ab217954f7a5c4bb377c9667';

final class FileBrowserSelectionFamily extends $Family
    with
        $ClassFamilyOverride<
          FileBrowserSelection,
          FileBrowserSelectionState,
          FileBrowserSelectionState,
          FileBrowserSelectionState,
          TabId
        > {
  FileBrowserSelectionFamily._()
    : super(
        retry: null,
        name: r'fileBrowserSelectionProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  FileBrowserSelectionProvider call(TabId tabId) =>
      FileBrowserSelectionProvider._(argument: tabId, from: this);

  @override
  String toString() => r'fileBrowserSelectionProvider';
}

abstract class _$FileBrowserSelection
    extends $Notifier<FileBrowserSelectionState> {
  late final _$args = ref.$arg as TabId;
  TabId get tabId => _$args;

  FileBrowserSelectionState build(TabId tabId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<FileBrowserSelectionState, FileBrowserSelectionState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<FileBrowserSelectionState, FileBrowserSelectionState>,
              FileBrowserSelectionState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
