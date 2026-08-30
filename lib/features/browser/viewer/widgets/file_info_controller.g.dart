// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'file_info_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(FileInfo)
final fileInfoProvider = FileInfoFamily._();

final class FileInfoProvider
    extends $NotifierProvider<FileInfo, FileInfoState> {
  FileInfoProvider._({
    required FileInfoFamily super.from,
    required (int, String) super.argument,
  }) : super(
         retry: null,
         name: r'fileInfoProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$fileInfoHash();

  @override
  String toString() {
    return r'fileInfoProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  FileInfo create() => FileInfo();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(FileInfoState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<FileInfoState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is FileInfoProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$fileInfoHash() => r'b2fc9b803a1122fe7d7f4aeeb5bc4432a4849f0d';

final class FileInfoFamily extends $Family
    with
        $ClassFamilyOverride<
          FileInfo,
          FileInfoState,
          FileInfoState,
          FileInfoState,
          (int, String)
        > {
  FileInfoFamily._()
    : super(
        retry: null,
        name: r'fileInfoProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  FileInfoProvider call(int volId, String fullPath) =>
      FileInfoProvider._(argument: (volId, fullPath), from: this);

  @override
  String toString() => r'fileInfoProvider';
}

abstract class _$FileInfo extends $Notifier<FileInfoState> {
  late final _$args = ref.$arg as (int, String);
  int get volId => _$args.$1;
  String get fullPath => _$args.$2;

  FileInfoState build(int volId, String fullPath);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<FileInfoState, FileInfoState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<FileInfoState, FileInfoState>,
              FileInfoState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args.$1, _$args.$2));
  }
}
