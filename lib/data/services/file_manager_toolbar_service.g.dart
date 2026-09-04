// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'file_manager_toolbar_service.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(fileManagerToolbarService)
final fileManagerToolbarServiceProvider = FileManagerToolbarServiceProvider._();

final class FileManagerToolbarServiceProvider
    extends
        $FunctionalProvider<
          FileManagerToolbarService,
          FileManagerToolbarService,
          FileManagerToolbarService
        >
    with $Provider<FileManagerToolbarService> {
  FileManagerToolbarServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'fileManagerToolbarServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$fileManagerToolbarServiceHash();

  @$internal
  @override
  $ProviderElement<FileManagerToolbarService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  FileManagerToolbarService create(Ref ref) {
    return fileManagerToolbarService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(FileManagerToolbarService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<FileManagerToolbarService>(value),
    );
  }
}

String _$fileManagerToolbarServiceHash() =>
    r'0009559f044553a8abcac5e358ab9e69749557de';
