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
  ClipboardAction action,
  List<ClipboardItem> items,
  String? archiveName,
  ArchiveFormatType? archiveFormat,
  String? passphrase,
  // 7z archive creation: also encrypt the file names (the archive header).
  bool encryptFilenames,
  ArchiveCompressionLevel? compressionLevel,
  ArchiveContext? archiveContext,
  List<String>? selectedEntryPaths,
});

const _emptyClipboard = (
  sourceVolId: null,
  sourceDisplayName: null,
  action: ClipboardAction.copy,
  items: <ClipboardItem>[],
  archiveName: null,
  archiveFormat: null,
  passphrase: null,
  encryptFilenames: false,
  compressionLevel: null,
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
  }) {
    state = (
      sourceVolId: volId,
      sourceDisplayName: displayName,
      action: cut ? ClipboardAction.move : ClipboardAction.copy,
      items: List.unmodifiable(clipItems),
      archiveName: null,
      archiveFormat: null,
      passphrase: null,
      encryptFilenames: false,
      compressionLevel: null,
      archiveContext: null,
      selectedEntryPaths: null,
    );
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
  }) {
    state = (
      sourceVolId: volId,
      sourceDisplayName: displayName,
      action: ClipboardAction.archiveCreate,
      items: List.unmodifiable(clipItems),
      archiveName: archiveName,
      archiveFormat: format,
      passphrase: passphrase,
      encryptFilenames: encryptFilenames,
      compressionLevel: compressionLevel,
      archiveContext: null,
      selectedEntryPaths: null,
    );
  }

  void setArchiveExtract({
    required int volId,
    required String displayName,
    required ClipboardItem archiveItem,
    required ArchiveContext archiveContext,
    List<String>? selectedEntryPaths,
    List<ClipboardItem>? stagedItems,
  }) {
    state = (
      sourceVolId: volId,
      sourceDisplayName: displayName,
      action: ClipboardAction.archiveExtract,
      items: List.unmodifiable(stagedItems ?? [archiveItem]),
      archiveName: archiveItem.name,
      archiveFormat: null,
      passphrase: archiveContext.passphrase,
      encryptFilenames: false,
      compressionLevel: null,
      archiveContext: archiveContext,
      selectedEntryPaths: selectedEntryPaths != null
          ? List.unmodifiable(selectedEntryPaths)
          : null,
    );
  }

  void clear() {
    state = _emptyClipboard;
  }
}