// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'file_browser_doc_provider_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(FileBrowserDocProvider)
final fileBrowserDocProviderProvider = FileBrowserDocProviderFamily._();

final class FileBrowserDocProviderProvider
    extends $NotifierProvider<FileBrowserDocProvider, Set<String>> {
  FileBrowserDocProviderProvider._({
    required FileBrowserDocProviderFamily super.from,
    required int super.argument,
  }) : super(
         retry: null,
         name: r'fileBrowserDocProviderProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$fileBrowserDocProviderHash();

  @override
  String toString() {
    return r'fileBrowserDocProviderProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  FileBrowserDocProvider create() => FileBrowserDocProvider();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Set<String> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Set<String>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is FileBrowserDocProviderProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$fileBrowserDocProviderHash() =>
    r'ba311bfb848df19fd7a1cb1b1a20df1d8bdfee38';

final class FileBrowserDocProviderFamily extends $Family
    with
        $ClassFamilyOverride<
          FileBrowserDocProvider,
          Set<String>,
          Set<String>,
          Set<String>,
          int
        > {
  FileBrowserDocProviderFamily._()
    : super(
        retry: null,
        name: r'fileBrowserDocProviderProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  FileBrowserDocProviderProvider call(int volId) =>
      FileBrowserDocProviderProvider._(argument: volId, from: this);

  @override
  String toString() => r'fileBrowserDocProviderProvider';
}

abstract class _$FileBrowserDocProvider extends $Notifier<Set<String>> {
  late final _$args = ref.$arg as int;
  int get volId => _$args;

  Set<String> build(int volId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<Set<String>, Set<String>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Set<String>, Set<String>>,
              Set<String>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
