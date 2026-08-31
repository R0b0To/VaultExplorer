// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'async_thumbnail_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Family-scoped replacement for `_AsyncThumbnailState`'s manual
/// load/cancel/retry/debounce logic. Family key is (volId, mountedAt,
/// filePath, quality) -- identity-only, deliberately excluding [fetchFn]/
/// [syncLookup]/[cache]/[limiter], which can't be family arguments (fresh
/// closure identity on every parent rebuild would make Riverpod treat
/// every rebuild as a new family instance). Those are instead handed to
/// [ensureLoaded] imperatively by the widget's `initState`/
/// `didUpdateWidget` -- guarded by [_started] so only the first call per
/// provider instance actually does anything, mirroring the old
/// `initState`-runs-once contract this replaces.
///
/// Every call site keys the widget itself by content
/// (`ValueKey('img:$filePath')` etc., never by list position), so a
/// filePath change in practice always means Flutter tears down the old
/// Element and mounts a fresh one -- a new family instance, not this same
/// instance being redirected. The old `_loadingPath`/`targetPath`
/// staleness comparisons this replaces are therefore collapsed to a
/// single [ref.mounted] check throughout: there is no "this instance now
/// wants a different path" case to distinguish anymore, since a
/// different path is a different family instance entirely.

@ProviderFor(AsyncThumbnailLoader)
final asyncThumbnailLoaderProvider = AsyncThumbnailLoaderFamily._();

/// Family-scoped replacement for `_AsyncThumbnailState`'s manual
/// load/cancel/retry/debounce logic. Family key is (volId, mountedAt,
/// filePath, quality) -- identity-only, deliberately excluding [fetchFn]/
/// [syncLookup]/[cache]/[limiter], which can't be family arguments (fresh
/// closure identity on every parent rebuild would make Riverpod treat
/// every rebuild as a new family instance). Those are instead handed to
/// [ensureLoaded] imperatively by the widget's `initState`/
/// `didUpdateWidget` -- guarded by [_started] so only the first call per
/// provider instance actually does anything, mirroring the old
/// `initState`-runs-once contract this replaces.
///
/// Every call site keys the widget itself by content
/// (`ValueKey('img:$filePath')` etc., never by list position), so a
/// filePath change in practice always means Flutter tears down the old
/// Element and mounts a fresh one -- a new family instance, not this same
/// instance being redirected. The old `_loadingPath`/`targetPath`
/// staleness comparisons this replaces are therefore collapsed to a
/// single [ref.mounted] check throughout: there is no "this instance now
/// wants a different path" case to distinguish anymore, since a
/// different path is a different family instance entirely.
final class AsyncThumbnailLoaderProvider
    extends $NotifierProvider<AsyncThumbnailLoader, AsyncThumbnailState> {
  /// Family-scoped replacement for `_AsyncThumbnailState`'s manual
  /// load/cancel/retry/debounce logic. Family key is (volId, mountedAt,
  /// filePath, quality) -- identity-only, deliberately excluding [fetchFn]/
  /// [syncLookup]/[cache]/[limiter], which can't be family arguments (fresh
  /// closure identity on every parent rebuild would make Riverpod treat
  /// every rebuild as a new family instance). Those are instead handed to
  /// [ensureLoaded] imperatively by the widget's `initState`/
  /// `didUpdateWidget` -- guarded by [_started] so only the first call per
  /// provider instance actually does anything, mirroring the old
  /// `initState`-runs-once contract this replaces.
  ///
  /// Every call site keys the widget itself by content
  /// (`ValueKey('img:$filePath')` etc., never by list position), so a
  /// filePath change in practice always means Flutter tears down the old
  /// Element and mounts a fresh one -- a new family instance, not this same
  /// instance being redirected. The old `_loadingPath`/`targetPath`
  /// staleness comparisons this replaces are therefore collapsed to a
  /// single [ref.mounted] check throughout: there is no "this instance now
  /// wants a different path" case to distinguish anymore, since a
  /// different path is a different family instance entirely.
  AsyncThumbnailLoaderProvider._({
    required AsyncThumbnailLoaderFamily super.from,
    required (int, DateTime, String, ThumbnailQuality) super.argument,
  }) : super(
         retry: null,
         name: r'asyncThumbnailLoaderProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$asyncThumbnailLoaderHash();

  @override
  String toString() {
    return r'asyncThumbnailLoaderProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  AsyncThumbnailLoader create() => AsyncThumbnailLoader();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AsyncThumbnailState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AsyncThumbnailState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AsyncThumbnailLoaderProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$asyncThumbnailLoaderHash() =>
    r'ed3701fb7d9ddbb4fe0fca70f4d1eafabe21212f';

/// Family-scoped replacement for `_AsyncThumbnailState`'s manual
/// load/cancel/retry/debounce logic. Family key is (volId, mountedAt,
/// filePath, quality) -- identity-only, deliberately excluding [fetchFn]/
/// [syncLookup]/[cache]/[limiter], which can't be family arguments (fresh
/// closure identity on every parent rebuild would make Riverpod treat
/// every rebuild as a new family instance). Those are instead handed to
/// [ensureLoaded] imperatively by the widget's `initState`/
/// `didUpdateWidget` -- guarded by [_started] so only the first call per
/// provider instance actually does anything, mirroring the old
/// `initState`-runs-once contract this replaces.
///
/// Every call site keys the widget itself by content
/// (`ValueKey('img:$filePath')` etc., never by list position), so a
/// filePath change in practice always means Flutter tears down the old
/// Element and mounts a fresh one -- a new family instance, not this same
/// instance being redirected. The old `_loadingPath`/`targetPath`
/// staleness comparisons this replaces are therefore collapsed to a
/// single [ref.mounted] check throughout: there is no "this instance now
/// wants a different path" case to distinguish anymore, since a
/// different path is a different family instance entirely.

final class AsyncThumbnailLoaderFamily extends $Family
    with
        $ClassFamilyOverride<
          AsyncThumbnailLoader,
          AsyncThumbnailState,
          AsyncThumbnailState,
          AsyncThumbnailState,
          (int, DateTime, String, ThumbnailQuality)
        > {
  AsyncThumbnailLoaderFamily._()
    : super(
        retry: null,
        name: r'asyncThumbnailLoaderProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Family-scoped replacement for `_AsyncThumbnailState`'s manual
  /// load/cancel/retry/debounce logic. Family key is (volId, mountedAt,
  /// filePath, quality) -- identity-only, deliberately excluding [fetchFn]/
  /// [syncLookup]/[cache]/[limiter], which can't be family arguments (fresh
  /// closure identity on every parent rebuild would make Riverpod treat
  /// every rebuild as a new family instance). Those are instead handed to
  /// [ensureLoaded] imperatively by the widget's `initState`/
  /// `didUpdateWidget` -- guarded by [_started] so only the first call per
  /// provider instance actually does anything, mirroring the old
  /// `initState`-runs-once contract this replaces.
  ///
  /// Every call site keys the widget itself by content
  /// (`ValueKey('img:$filePath')` etc., never by list position), so a
  /// filePath change in practice always means Flutter tears down the old
  /// Element and mounts a fresh one -- a new family instance, not this same
  /// instance being redirected. The old `_loadingPath`/`targetPath`
  /// staleness comparisons this replaces are therefore collapsed to a
  /// single [ref.mounted] check throughout: there is no "this instance now
  /// wants a different path" case to distinguish anymore, since a
  /// different path is a different family instance entirely.

  AsyncThumbnailLoaderProvider call(
    int volId,
    DateTime mountedAt,
    String filePath,
    ThumbnailQuality quality,
  ) => AsyncThumbnailLoaderProvider._(
    argument: (volId, mountedAt, filePath, quality),
    from: this,
  );

  @override
  String toString() => r'asyncThumbnailLoaderProvider';
}

/// Family-scoped replacement for `_AsyncThumbnailState`'s manual
/// load/cancel/retry/debounce logic. Family key is (volId, mountedAt,
/// filePath, quality) -- identity-only, deliberately excluding [fetchFn]/
/// [syncLookup]/[cache]/[limiter], which can't be family arguments (fresh
/// closure identity on every parent rebuild would make Riverpod treat
/// every rebuild as a new family instance). Those are instead handed to
/// [ensureLoaded] imperatively by the widget's `initState`/
/// `didUpdateWidget` -- guarded by [_started] so only the first call per
/// provider instance actually does anything, mirroring the old
/// `initState`-runs-once contract this replaces.
///
/// Every call site keys the widget itself by content
/// (`ValueKey('img:$filePath')` etc., never by list position), so a
/// filePath change in practice always means Flutter tears down the old
/// Element and mounts a fresh one -- a new family instance, not this same
/// instance being redirected. The old `_loadingPath`/`targetPath`
/// staleness comparisons this replaces are therefore collapsed to a
/// single [ref.mounted] check throughout: there is no "this instance now
/// wants a different path" case to distinguish anymore, since a
/// different path is a different family instance entirely.

abstract class _$AsyncThumbnailLoader extends $Notifier<AsyncThumbnailState> {
  late final _$args = ref.$arg as (int, DateTime, String, ThumbnailQuality);
  int get volId => _$args.$1;
  DateTime get mountedAt => _$args.$2;
  String get filePath => _$args.$3;
  ThumbnailQuality get quality => _$args.$4;

  AsyncThumbnailState build(
    int volId,
    DateTime mountedAt,
    String filePath,
    ThumbnailQuality quality,
  );
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncThumbnailState, AsyncThumbnailState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncThumbnailState, AsyncThumbnailState>,
              AsyncThumbnailState,
              Object?,
              Object?
            >;
    return element.handleCreate(
      ref,
      () => build(_$args.$1, _$args.$2, _$args.$3, _$args.$4),
    );
  }
}
