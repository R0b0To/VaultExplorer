import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/data/models/clipboard_item.dart';

part 'cross_container_clipboard.g.dart';

/// Immutable snapshot of the cross-container clipboard.
typedef ClipboardState = ({
  int? sourceVolId,
  String? sourceDisplayName,
  bool isCutOperation,
  List<ClipboardItem> items,
});

const _emptyClipboard = (
  sourceVolId: null,
  sourceDisplayName: null,
  isCutOperation: false,
  items: <ClipboardItem>[],
);

/// Computed reads shared by both the reactive path ([CrossContainerClipboard]'s
/// watched `state`) and the imperative path ([CrossContainerClipboard]'s own
/// forwarders below) so the logic lives in exactly one place.
extension ClipboardStateX on ClipboardState {
  bool get hasItems => items.isNotEmpty;

  /// True when the clipboard was populated from [volId].
  bool isFromVolume(int volId) => sourceVolId == volId;

  /// Short human-readable summary for status strips and banners.
  String get summary {
    if (!hasItems) return '';
    final verb = isCutOperation ? 'Moving' : 'Copying';
    final from = sourceDisplayName ?? '?';
    return '$verb ${items.length} item(s) from "$from"';
  }
}

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
@Riverpod(keepAlive: true)
class CrossContainerClipboard extends _$CrossContainerClipboard {
  @override
  ClipboardState build() => _emptyClipboard;

  // ── Instance forwarders (imperative call sites) ─────────────────────────

  bool get hasItems => state.hasItems;
  int? get sourceVolId => state.sourceVolId;
  String? get sourceDisplayName => state.sourceDisplayName;
  bool get isCutOperation => state.isCutOperation;
  List<ClipboardItem> get items => state.items;
  bool isFromVolume(int volId) => state.isFromVolume(volId);
  String get summary => state.summary;

  // ── Mutations ─────────────────────────────────────────────────────────────

  /// Populates the clipboard.
  void set({
    required int volId,
    required String displayName,
    required bool cut,
    required List<ClipboardItem> clipItems,
  }) {
    state = (
      sourceVolId: volId,
      sourceDisplayName: displayName,
      isCutOperation: cut,
      items: List.unmodifiable(clipItems),
    );
  }

  /// Clears the clipboard.
  void clear() {
    state = _emptyClipboard;
  }
}
