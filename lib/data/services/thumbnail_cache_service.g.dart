// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'thumbnail_cache_service.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(thumbnailCacheService)
final thumbnailCacheServiceProvider = ThumbnailCacheServiceProvider._();

final class ThumbnailCacheServiceProvider
    extends
        $FunctionalProvider<
          ThumbnailCacheService,
          ThumbnailCacheService,
          ThumbnailCacheService
        >
    with $Provider<ThumbnailCacheService> {
  ThumbnailCacheServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'thumbnailCacheServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$thumbnailCacheServiceHash();

  @$internal
  @override
  $ProviderElement<ThumbnailCacheService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ThumbnailCacheService create(Ref ref) {
    return thumbnailCacheService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ThumbnailCacheService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ThumbnailCacheService>(value),
    );
  }
}

String _$thumbnailCacheServiceHash() =>
    r'26796588358b85c5731774ddfdba80ec2cfdcd90';
