// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'folder_document_provider_service.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// No internal mutable state of its own -> pure keep-alive provider per the
/// migration plan's Phase 3 rule, constructor-injected with the shared
/// [ContainerRepository] through [containerRepositoryProvider] instead of
/// reaching for `ContainerRepository.instance` directly. There was exactly
/// one call site (`_FileBrowserScreenState`, already a `ConsumerState`), so
/// this went straight to the provider rather than keeping a transitional
/// `.instance` bridge.

@ProviderFor(folderDocumentProviderService)
final folderDocumentProviderServiceProvider =
    FolderDocumentProviderServiceProvider._();

/// No internal mutable state of its own -> pure keep-alive provider per the
/// migration plan's Phase 3 rule, constructor-injected with the shared
/// [ContainerRepository] through [containerRepositoryProvider] instead of
/// reaching for `ContainerRepository.instance` directly. There was exactly
/// one call site (`_FileBrowserScreenState`, already a `ConsumerState`), so
/// this went straight to the provider rather than keeping a transitional
/// `.instance` bridge.

final class FolderDocumentProviderServiceProvider
    extends
        $FunctionalProvider<
          FolderDocumentProviderService,
          FolderDocumentProviderService,
          FolderDocumentProviderService
        >
    with $Provider<FolderDocumentProviderService> {
  /// No internal mutable state of its own -> pure keep-alive provider per the
  /// migration plan's Phase 3 rule, constructor-injected with the shared
  /// [ContainerRepository] through [containerRepositoryProvider] instead of
  /// reaching for `ContainerRepository.instance` directly. There was exactly
  /// one call site (`_FileBrowserScreenState`, already a `ConsumerState`), so
  /// this went straight to the provider rather than keeping a transitional
  /// `.instance` bridge.
  FolderDocumentProviderServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'folderDocumentProviderServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$folderDocumentProviderServiceHash();

  @$internal
  @override
  $ProviderElement<FolderDocumentProviderService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  FolderDocumentProviderService create(Ref ref) {
    return folderDocumentProviderService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(FolderDocumentProviderService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<FolderDocumentProviderService>(
        value,
      ),
    );
  }
}

String _$folderDocumentProviderServiceHash() =>
    r'af396c9d58458910c23d88233b19dbd8b30fe781';
