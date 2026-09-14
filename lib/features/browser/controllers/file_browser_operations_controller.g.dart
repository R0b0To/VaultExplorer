// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'file_browser_operations_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// No internal mutable state of its own -> pure keep-alive provider per the
/// migration plan's Phase 3 rule, matching [MediaScanService]'s shape.

@ProviderFor(fileBrowserOperationsController)
final fileBrowserOperationsControllerProvider =
    FileBrowserOperationsControllerProvider._();

/// No internal mutable state of its own -> pure keep-alive provider per the
/// migration plan's Phase 3 rule, matching [MediaScanService]'s shape.

final class FileBrowserOperationsControllerProvider
    extends
        $FunctionalProvider<
          FileBrowserOperationsController,
          FileBrowserOperationsController,
          FileBrowserOperationsController
        >
    with $Provider<FileBrowserOperationsController> {
  /// No internal mutable state of its own -> pure keep-alive provider per the
  /// migration plan's Phase 3 rule, matching [MediaScanService]'s shape.
  FileBrowserOperationsControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'fileBrowserOperationsControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$fileBrowserOperationsControllerHash();

  @$internal
  @override
  $ProviderElement<FileBrowserOperationsController> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  FileBrowserOperationsController create(Ref ref) {
    return fileBrowserOperationsController(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(FileBrowserOperationsController value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<FileBrowserOperationsController>(
        value,
      ),
    );
  }
}

String _$fileBrowserOperationsControllerHash() =>
    r'7e25625f0fae2df1eb3d57ede533006a245c4af6';
