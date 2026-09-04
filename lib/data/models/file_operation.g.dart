// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'file_operation.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(fileOperationService)
final fileOperationServiceProvider = FileOperationServiceProvider._();

final class FileOperationServiceProvider
    extends
        $FunctionalProvider<
          Raw<FileOperationService>,
          Raw<FileOperationService>,
          Raw<FileOperationService>
        >
    with $Provider<Raw<FileOperationService>> {
  FileOperationServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'fileOperationServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$fileOperationServiceHash();

  @$internal
  @override
  $ProviderElement<Raw<FileOperationService>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  Raw<FileOperationService> create(Ref ref) {
    return fileOperationService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Raw<FileOperationService> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Raw<FileOperationService>>(value),
    );
  }
}

String _$fileOperationServiceHash() =>
    r'd0ca4fb7f1d37159b76c03e77836187148a32000';
