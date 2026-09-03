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
  archiveContext: null,
  selectedEntryPaths: null,
);

extension ClipboardStateX on ClipboardState {
  bool get hasItems => items.isNotEmpty;
  bool get isCutOperation => action == ClipboardAction.move;
  bool get isCopyOperation => action == ClipboardAction.copy;
  bool get isArchiveCreate => action == ClipboardAction.archiveCreate;
  bool get isArchiveExtract => action == ClipboardAction.archiveExtract;

  /// True when only specific entries from inside an archive are staged.
  bool get isPartialExtract =>
      action == ClipboardAction.archiveExtract &&
      selectedEntryPaths != null &&
      selectedEntryPaths!.isNotEmpty;

  /// True when the clipboard was populated from [volId].
  bool isFromVolume(int volId) => sourceVolId == volId;

  /// Short human-readable summary for status strips and banners.
  String get summary {
    if (!hasItems) return '';
    final String verb;
    switch (action) {
      case ClipboardAction.move:
        verb = 'Moving';
        break;
      case ClipboardAction.copy:
        verb = 'Copying';
        break;
      case ClipboardAction.archiveCreate:
        verb = 'Archiving';
        break;
      case ClipboardAction.archiveExtract:
        verb = 'Extracting';
        break;
    }
    final from = sourceDisplayName ?? '?';
    return '$verb ${items.length} item(s) from "$from"';
  }
}

@Riverpod(keepAlive: true)
class CrossContainerClipboard extends _$CrossContainerClipboard {
  @override
  ClipboardState build() => _emptyClipboard;

  // ── Instance forwarders ───────────────────────────────────────────────────

  bool get hasItems => state.hasItems;
  int? get sourceVolId => state.sourceVolId;
  String? get sourceDisplayName => state.sourceDisplayName;
  ClipboardAction get action => state.action;
  bool get isCutOperation => state.isCutOperation;
  bool get isArchiveCreate => state.isArchiveCreate;
  bool get isArchiveExtract => state.isArchiveExtract;
  bool get isPartialExtract => state.isPartialExtract;
  List<ClipboardItem> get items => state.items;
  String? get archiveName => state.archiveName;
  ArchiveFormatType? get archiveFormat => state.archiveFormat;
  String? get passphrase => state.passphrase;
  ArchiveContext? get archiveContext => state.archiveContext;
  List<String>? get selectedEntryPaths => state.selectedEntryPaths;
  bool isFromVolume(int volId) => state.isFromVolume(volId);
  String get summary => state.summary;

  // ── Mutations ─────────────────────────────────────────────────────────────

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
  }) {
    state = (
      sourceVolId: volId,
      sourceDisplayName: displayName,
      action: ClipboardAction.archiveCreate,
      items: List.unmodifiable(clipItems),
      archiveName: archiveName,
      archiveFormat: format,
      passphrase: passphrase,
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