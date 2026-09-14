// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'media_scan_service.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// No internal mutable state of its own -> pure keep-alive provider per the
/// migration plan's Phase 3 rule, matching [FolderDocumentProviderService]'s
/// shape. Constructor-injected with [VaultFileIoApi] through
/// [vaultFileIoApiProvider] rather than each call site reading the provider
/// itself.

@ProviderFor(mediaScanService)
final mediaScanServiceProvider = MediaScanServiceProvider._();

/// No internal mutable state of its own -> pure keep-alive provider per the
/// migration plan's Phase 3 rule, matching [FolderDocumentProviderService]'s
/// shape. Constructor-injected with [VaultFileIoApi] through
/// [vaultFileIoApiProvider] rather than each call site reading the provider
/// itself.

final class MediaScanServiceProvider
    extends
        $FunctionalProvider<
          MediaScanService,
          MediaScanService,
          MediaScanService
        >
    with $Provider<MediaScanService> {
  /// No internal mutable state of its own -> pure keep-alive provider per the
  /// migration plan's Phase 3 rule, matching [FolderDocumentProviderService]'s
  /// shape. Constructor-injected with [VaultFileIoApi] through
  /// [vaultFileIoApiProvider] rather than each call site reading the provider
  /// itself.
  MediaScanServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'mediaScanServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$mediaScanServiceHash();

  @$internal
  @override
  $ProviderElement<MediaScanService> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  MediaScanService create(Ref ref) {
    return mediaScanService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MediaScanService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MediaScanService>(value),
    );
  }
}

String _$mediaScanServiceHash() => r'98653a8cc39bc99c5e6ba0bf87cd7373becf8cce';
