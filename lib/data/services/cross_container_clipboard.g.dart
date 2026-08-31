// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cross_container_clipboard.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Holds clipboard items which survive navigation between containers and
/// back to the dashboard -- app-wide state, hence `keepAlive: true` (same
/// reasoning as [ContainerRepository]/[FileOperationService] in
/// legacy_services_providers.dart: this must not reset just because nothing
/// happens to be watching it for a moment while the user is mid-navigation).
///
/// ### What changed from the old version
/// - Was a hand-rolled `ChangeNotifier` singleton (`CrossContainerClipboard
///   .instance`) with mutable fields + `notifyListeners()`. Now a
///   `@riverpod` Notifier over an immutable [ClipboardState] record, same
///   shape as [FileBrowserSelection] in file_browser_selection_controller
///   .dart: `state = ...` replaces mutate-then-notifyListeners(), and
///   widgets that need to rebuild use `ref.watch(crossContainerClipboardProvider)`
///   instead of `ListenableBuilder(listenable: CrossContainerClipboard.instance)`.
/// - `hasItems`/`isFromVolume`/`summary` are re-exposed as instance
///   forwarders below (delegating to `state` via [ClipboardStateX]) purely
///   so imperative call sites (`ref.read(crossContainerClipboardProvider
///   .notifier)`) keep the exact same `clip.hasItems` / `clip.items` shape
///   the old singleton had -- same "forwarders on the resolved object"
///   approach ThumbnailCacheService uses and documents on itself, for the
///   same reason (less churn per call site). Reactive/build-time reads go
///   through `ref.watch(...)` + the extension directly (see
///   AppBarClipboardButton, DecoyLocalExplorerScreen._canPaste).
/// - `items` stays `List<ClipboardItem>`, unchanged from the pre-Riverpod
///   version.
/// - `sourceVolId`/`sourceDisplayName` still store only identity scalars,
///   not a full `MountedContainer`, to avoid keeping the container alive in
///   memory after it is locked.

@ProviderFor(CrossContainerClipboard)
final crossContainerClipboardProvider = CrossContainerClipboardProvider._();

/// Holds clipboard items which survive navigation between containers and
/// back to the dashboard -- app-wide state, hence `keepAlive: true` (same
/// reasoning as [ContainerRepository]/[FileOperationService] in
/// legacy_services_providers.dart: this must not reset just because nothing
/// happens to be watching it for a moment while the user is mid-navigation).
///
/// ### What changed from the old version
/// - Was a hand-rolled `ChangeNotifier` singleton (`CrossContainerClipboard
///   .instance`) with mutable fields + `notifyListeners()`. Now a
///   `@riverpod` Notifier over an immutable [ClipboardState] record, same
///   shape as [FileBrowserSelection] in file_browser_selection_controller
///   .dart: `state = ...` replaces mutate-then-notifyListeners(), and
///   widgets that need to rebuild use `ref.watch(crossContainerClipboardProvider)`
///   instead of `ListenableBuilder(listenable: CrossContainerClipboard.instance)`.
/// - `hasItems`/`isFromVolume`/`summary` are re-exposed as instance
///   forwarders below (delegating to `state` via [ClipboardStateX]) purely
///   so imperative call sites (`ref.read(crossContainerClipboardProvider
///   .notifier)`) keep the exact same `clip.hasItems` / `clip.items` shape
///   the old singleton had -- same "forwarders on the resolved object"
///   approach ThumbnailCacheService uses and documents on itself, for the
///   same reason (less churn per call site). Reactive/build-time reads go
///   through `ref.watch(...)` + the extension directly (see
///   AppBarClipboardButton, DecoyLocalExplorerScreen._canPaste).
/// - `items` stays `List<ClipboardItem>`, unchanged from the pre-Riverpod
///   version.
/// - `sourceVolId`/`sourceDisplayName` still store only identity scalars,
///   not a full `MountedContainer`, to avoid keeping the container alive in
///   memory after it is locked.
final class CrossContainerClipboardProvider
    extends $NotifierProvider<CrossContainerClipboard, ClipboardState> {
  /// Holds clipboard items which survive navigation between containers and
  /// back to the dashboard -- app-wide state, hence `keepAlive: true` (same
  /// reasoning as [ContainerRepository]/[FileOperationService] in
  /// legacy_services_providers.dart: this must not reset just because nothing
  /// happens to be watching it for a moment while the user is mid-navigation).
  ///
  /// ### What changed from the old version
  /// - Was a hand-rolled `ChangeNotifier` singleton (`CrossContainerClipboard
  ///   .instance`) with mutable fields + `notifyListeners()`. Now a
  ///   `@riverpod` Notifier over an immutable [ClipboardState] record, same
  ///   shape as [FileBrowserSelection] in file_browser_selection_controller
  ///   .dart: `state = ...` replaces mutate-then-notifyListeners(), and
  ///   widgets that need to rebuild use `ref.watch(crossContainerClipboardProvider)`
  ///   instead of `ListenableBuilder(listenable: CrossContainerClipboard.instance)`.
  /// - `hasItems`/`isFromVolume`/`summary` are re-exposed as instance
  ///   forwarders below (delegating to `state` via [ClipboardStateX]) purely
  ///   so imperative call sites (`ref.read(crossContainerClipboardProvider
  ///   .notifier)`) keep the exact same `clip.hasItems` / `clip.items` shape
  ///   the old singleton had -- same "forwarders on the resolved object"
  ///   approach ThumbnailCacheService uses and documents on itself, for the
  ///   same reason (less churn per call site). Reactive/build-time reads go
  ///   through `ref.watch(...)` + the extension directly (see
  ///   AppBarClipboardButton, DecoyLocalExplorerScreen._canPaste).
  /// - `items` stays `List<ClipboardItem>`, unchanged from the pre-Riverpod
  ///   version.
  /// - `sourceVolId`/`sourceDisplayName` still store only identity scalars,
  ///   not a full `MountedContainer`, to avoid keeping the container alive in
  ///   memory after it is locked.
  CrossContainerClipboardProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'crossContainerClipboardProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$crossContainerClipboardHash();

  @$internal
  @override
  CrossContainerClipboard create() => CrossContainerClipboard();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ClipboardState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ClipboardState>(value),
    );
  }
}

String _$crossContainerClipboardHash() =>
    r'7361923f2f401e3c44dff618d95331da1621e3bf';

/// Holds clipboard items which survive navigation between containers and
/// back to the dashboard -- app-wide state, hence `keepAlive: true` (same
/// reasoning as [ContainerRepository]/[FileOperationService] in
/// legacy_services_providers.dart: this must not reset just because nothing
/// happens to be watching it for a moment while the user is mid-navigation).
///
/// ### What changed from the old version
/// - Was a hand-rolled `ChangeNotifier` singleton (`CrossContainerClipboard
///   .instance`) with mutable fields + `notifyListeners()`. Now a
///   `@riverpod` Notifier over an immutable [ClipboardState] record, same
///   shape as [FileBrowserSelection] in file_browser_selection_controller
///   .dart: `state = ...` replaces mutate-then-notifyListeners(), and
///   widgets that need to rebuild use `ref.watch(crossContainerClipboardProvider)`
///   instead of `ListenableBuilder(listenable: CrossContainerClipboard.instance)`.
/// - `hasItems`/`isFromVolume`/`summary` are re-exposed as instance
///   forwarders below (delegating to `state` via [ClipboardStateX]) purely
///   so imperative call sites (`ref.read(crossContainerClipboardProvider
///   .notifier)`) keep the exact same `clip.hasItems` / `clip.items` shape
///   the old singleton had -- same "forwarders on the resolved object"
///   approach ThumbnailCacheService uses and documents on itself, for the
///   same reason (less churn per call site). Reactive/build-time reads go
///   through `ref.watch(...)` + the extension directly (see
///   AppBarClipboardButton, DecoyLocalExplorerScreen._canPaste).
/// - `items` stays `List<ClipboardItem>`, unchanged from the pre-Riverpod
///   version.
/// - `sourceVolId`/`sourceDisplayName` still store only identity scalars,
///   not a full `MountedContainer`, to avoid keeping the container alive in
///   memory after it is locked.

abstract class _$CrossContainerClipboard extends $Notifier<ClipboardState> {
  ClipboardState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<ClipboardState, ClipboardState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ClipboardState, ClipboardState>,
              ClipboardState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
