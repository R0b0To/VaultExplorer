// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'file_browser_navigation_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(FileBrowserNavigation)
final fileBrowserNavigationProvider = FileBrowserNavigationFamily._();

final class FileBrowserNavigationProvider
    extends
        $NotifierProvider<FileBrowserNavigation, FileBrowserNavigationState> {
  FileBrowserNavigationProvider._({
    required FileBrowserNavigationFamily super.from,
    required int super.argument,
  }) : super(
         retry: null,
         name: r'fileBrowserNavigationProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$fileBrowserNavigationHash();

  @override
  String toString() {
    return r'fileBrowserNavigationProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  FileBrowserNavigation create() => FileBrowserNavigation();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(FileBrowserNavigationState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<FileBrowserNavigationState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is FileBrowserNavigationProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$fileBrowserNavigationHash() =>
    r'923029f00210d17681efd6f87464f646a2c6ac96';

final class FileBrowserNavigationFamily extends $Family
    with
        $ClassFamilyOverride<
          FileBrowserNavigation,
          FileBrowserNavigationState,
          FileBrowserNavigationState,
          FileBrowserNavigationState,
          int
        > {
  FileBrowserNavigationFamily._()
    : super(
        retry: null,
        name: r'fileBrowserNavigationProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  FileBrowserNavigationProvider call(int volId) =>
      FileBrowserNavigationProvider._(argument: volId, from: this);

  @override
  String toString() => r'fileBrowserNavigationProvider';
}

abstract class _$FileBrowserNavigation
    extends $Notifier<FileBrowserNavigationState> {
  late final _$args = ref.$arg as int;
  int get volId => _$args;

  FileBrowserNavigationState build(int volId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<FileBrowserNavigationState, FileBrowserNavigationState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                FileBrowserNavigationState,
                FileBrowserNavigationState
              >,
              FileBrowserNavigationState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
