import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/data/models/archive_context.dart';
import 'package:vaultexplorer/data/models/archive_models.dart';
import 'package:vaultexplorer/data/models/clipboard_item.dart';

part 'cross_container_clipboard.g.dart';

enum ClipboardAction {
  copy,
  move,
  archiveCreate,
  archiveExtract;

  bool get isArchive =>
      this == ClipboardAction.archiveCreate ||
      this == ClipboardAction.archiveExtract;
}

/// Immutable snapshot of the cross-container clipboard.
typedef ClipboardState = ({
  int? sourceVolId,
  String? sourceDisplayName,
  int? returnToTabId,
  String? returnToFilter,
  ClipboardAction action,
  List<ClipboardItem> items,
  String? archiveName,
  ArchiveFormatType? archiveFormat,
  String? passphrase,
  // 7z archive creation: also encrypt the file names (the archive header).
  bool encryptFilenames,
  ArchiveCompressionLevel? compressionLevel,
  // 7z archive creation: which codec (LZMA2 / LZMA / Deflate). `auto` for every
  // other format and for everything that isn't an archive create.
  ArchiveCompressionMethod compressionMethod,
  // ZIP / 7z archive creation: part size in bytes, 0 = a single file.
  int splitSizeBytes,
  ArchiveContext? archiveContext,
  List<String>? selectedEntryPaths,
});

const _emptyClipboard = (
  sourceVolId: null,
  sourceDisplayName: null,
  returnToTabId: null,
  returnToFilter: null,
  action: ClipboardAction.copy,
  items: <ClipboardItem>[],
  archiveName: null,
  archiveFormat: null,
  passphrase: null,
  encryptFilenames: false,
  compressionLevel: null,
  compressionMethod: ArchiveCompressionMethod.auto,
  splitSizeBytes: 0,
  archiveContext: null,
  selectedEntryPaths: null,
);

/// All public readable properties live on ClipboardState / ClipboardStateX.
extension ClipboardStateX on ClipboardState {
  bool get hasItems => items.isNotEmpty;
  bool get isCutOperation => action == ClipboardAction.move;
  bool get isCopyOperation => action == ClipboardAction.copy;
  bool get isArchiveCreate => action == ClipboardAction.archiveCreate;
  bool get isArchiveExtract => action == ClipboardAction.archiveExtract;

  bool get isPartialExtract =>
      action == ClipboardAction.archiveExtract &&
      selectedEntryPaths != null &&
      selectedEntryPaths!.isNotEmpty;

  bool isFromVolume(int volId) => sourceVolId == volId;
}

@Riverpod(keepAlive: true)
class CrossContainerClipboard extends _$CrossContainerClipboard {
  @override
  ClipboardState build() => _emptyClipboard;

  // ── Mutations Only ────────────────────────────────────────────────────────

  void set({
    required int volId,
    required String displayName,
    required bool cut,
    required List<ClipboardItem> clipItems,
    int? returnToTabId,
    String? returnToFilter,
  }) {
    _replace((
      sourceVolId: volId,
      sourceDisplayName: displayName,
      returnToTabId: returnToTabId,
      returnToFilter: returnToFilter,
      action: cut ? ClipboardAction.move : ClipboardAction.copy,
      items: List.unmodifiable(clipItems),
      archiveName: null,
      archiveFormat: null,
      passphrase: null,
      encryptFilenames: false,
      compressionLevel: null,
      compressionMethod: ArchiveCompressionMethod.auto,
      splitSizeBytes: 0,
      archiveContext: null,
      selectedEntryPaths: null,
    ));
  }

  void setArchiveCreate({
    required int volId,
    required String displayName,
    required List<ClipboardItem> clipItems,
    required String archiveName,
    required ArchiveFormatType format,
    String? passphrase,
    bool encryptFilenames = false,
    ArchiveCompressionLevel? compressionLevel,
    ArchiveCompressionMethod compressionMethod = ArchiveCompressionMethod.auto,
    int splitSizeBytes = 0,
    int? returnToTabId,
    String? returnToFilter,
  }) {
    _replace((
      sourceVolId: volId,
      sourceDisplayName: displayName,
      returnToTabId: returnToTabId,
      returnToFilter: returnToFilter,
      action: ClipboardAction.archiveCreate,
      items: List.unmodifiable(clipItems),
      archiveName: archiveName,
      archiveFormat: format,
      passphrase: passphrase,
      encryptFilenames: encryptFilenames,
      compressionLevel: compressionLevel,
      compressionMethod: compressionMethod,
      splitSizeBytes: splitSizeBytes,
      archiveContext: null,
      selectedEntryPaths: null,
    ));
  }

  void setArchiveExtract({
    required int volId,
    required String displayName,
    required ClipboardItem archiveItem,
    required ArchiveContext archiveContext,
    List<String>? selectedEntryPaths,
    List<ClipboardItem>? stagedItems,
  }) {
    _replace((
      sourceVolId: volId,
      sourceDisplayName: displayName,
      returnToTabId: null,
      returnToFilter: null,
      action: ClipboardAction.archiveExtract,
      items: List.unmodifiable(stagedItems ?? [archiveItem]),
      archiveName: archiveItem.name,
      archiveFormat: null,
      passphrase: archiveContext.passphrase,
      encryptFilenames: false,
      compressionLevel: null,
      compressionMethod: ArchiveCompressionMethod.auto,
      splitSizeBytes: 0,
      archiveContext: archiveContext,
      selectedEntryPaths: selectedEntryPaths != null
          ? List.unmodifiable(selectedEntryPaths)
          : null,
    ));
  }

  void clear() {
    _replace(_emptyClipboard);
  }

  /// Removes any clipboard items that match [deletedPaths] on volume [volId],
  /// or are children of deleted directories. If all items were removed, the
  /// clipboard is cleared entirely.
  void removeDeletedPaths(int volId, Iterable<String> deletedPaths) {
    if (!state.hasItems) return;
    final deletedSet = deletedPaths.toSet();
    if (deletedSet.isEmpty) return;

    bool matches(ClipboardItem item) {
      final itemVol = item.volId ?? state.sourceVolId;
      if (itemVol != volId) return false;
      for (final dp in deletedSet) {
        if (item.path == dp || item.path.startsWith('$dp/')) {
          return true;
        }
      }
      return false;
    }

    final remaining = state.items.where((it) => !matches(it)).toList();
    if (remaining.isEmpty) {
      clear();
    } else if (remaining.length != state.items.length) {
      _replace((
        sourceVolId: state.sourceVolId,
        sourceDisplayName: state.sourceDisplayName,
        returnToTabId: state.returnToTabId,
        returnToFilter: state.returnToFilter,
        action: state.action,
        items: List.unmodifiable(remaining),
        archiveName: state.archiveName,
        archiveFormat: state.archiveFormat,
        passphrase: state.passphrase,
        encryptFilenames: state.encryptFilenames,
        compressionLevel: state.compressionLevel,
        compressionMethod: state.compressionMethod,
        splitSizeBytes: state.splitSizeBytes,
        archiveContext: state.archiveContext,
        selectedEntryPaths: state.selectedEntryPaths,
      ));
    }
  }

  /// Swaps in [next], keeping a nested archive's temporary copy alive for
  /// exactly as long as the clipboard refers to it. A partial extract staged
  /// from inside a nested archive is pasted later, possibly after that archive
  /// was closed; without this hold, closing it would wipe the file the paste
  /// needs.
  void _replace(ClipboardState next) {
    final previous = state.archiveContext;
    final incoming = next.archiveContext;
    if (!identical(previous, incoming)) {
      incoming?.retainSource();
      previous?.releaseSource();
    }
    state = next;
  }
}
