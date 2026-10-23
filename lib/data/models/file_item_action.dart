import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

/// An action offered for a file or folder, in the item actions sheet and in
/// the selection bar's overflow menu.
///
/// The declaration order is the default order. It is chosen so that, with
/// nothing customised, both surfaces list their actions exactly as they did
/// before this was configurable.
///
/// [share], [copy], [move] and [delete] are the *quick* actions: the item
/// sheet lays them out as a horizontal row of icon buttons instead of list
/// rows. Everything else is a list row.
enum FileItemAction {
  openInNewTab,
  extract,
  openWith,
  share,
  editImage,
  editVideo,
  editAudio,
  rename,
  copy,
  move,
  archive,
  exportToDevice,
  encrypt,
  decrypt,
  docProvider,
  syncSettings,
  pin,
  bookmark,
  delete;

  /// Whether the item sheet shows this action in its horizontal quick row.
  bool get isQuickAction => switch (this) {
    FileItemAction.share ||
    FileItemAction.copy ||
    FileItemAction.move ||
    FileItemAction.delete => true,
    _ => false,
  };

  /// Visual group of a list row in the item sheet. A small gap separates two
  /// neighbouring rows of different groups, which reproduces the original
  /// grouping while the order is the default one and degrades gracefully
  /// when the user mixes groups.
  int get group => switch (this) {
    FileItemAction.openInNewTab => 0,
    FileItemAction.extract => 1,
    FileItemAction.openWith ||
    FileItemAction.editImage ||
    FileItemAction.editVideo ||
    FileItemAction.editAudio => 2,
    FileItemAction.rename || FileItemAction.archive => 3,
    FileItemAction.exportToDevice ||
    FileItemAction.encrypt ||
    FileItemAction.decrypt ||
    FileItemAction.docProvider ||
    FileItemAction.syncSettings => 4,
    FileItemAction.pin || FileItemAction.bookmark => 5,
    // Quick actions are not list rows; any value works.
    FileItemAction.share ||
    FileItemAction.copy ||
    FileItemAction.move ||
    FileItemAction.delete => 6,
  };

  IconData get icon => switch (this) {
    FileItemAction.openInNewTab => Icons.tab_rounded,
    FileItemAction.extract => Icons.unarchive_outlined,
    FileItemAction.openWith => Icons.open_in_new_rounded,
    FileItemAction.share => Icons.share_rounded,
    FileItemAction.editImage => Icons.edit_outlined,
    FileItemAction.editVideo => Icons.content_cut_rounded,
    FileItemAction.editAudio => Icons.graphic_eq_rounded,
    FileItemAction.rename => Icons.drive_file_rename_outline_rounded,
    FileItemAction.copy => Icons.copy_rounded,
    FileItemAction.move => Icons.cut_rounded,
    FileItemAction.archive => Icons.archive_outlined,
    FileItemAction.exportToDevice => Icons.drive_folder_upload_rounded,
    FileItemAction.encrypt => Icons.lock_outline_rounded,
    FileItemAction.decrypt => Icons.lock_open_rounded,
    FileItemAction.docProvider => Icons.folder_shared_outlined,
    FileItemAction.syncSettings => Icons.sync_rounded,
    FileItemAction.pin => Icons.push_pin_rounded,
    FileItemAction.bookmark => Icons.star_rounded,
    FileItemAction.delete => Icons.delete_outline_rounded,
  };

  /// Label used in the settings list. Reuses the strings the menus already
  /// show; actions whose menu label flips with state (pin/unpin, ...) use
  /// their neutral form.
  String getLocalizedLabel(AppLocalizations l10n) => switch (this) {
    FileItemAction.openInNewTab => l10n.browserTabOpenInNewTab,
    FileItemAction.extract => l10n.extract,
    FileItemAction.openWith => l10n.openWithAppAction,
    FileItemAction.share => l10n.shareAction,
    FileItemAction.editImage => l10n.editImageAction,
    FileItemAction.editVideo => l10n.videoEditorEditAction,
    FileItemAction.editAudio => l10n.audioEditorEditAction,
    FileItemAction.rename => l10n.renameAction,
    FileItemAction.copy => l10n.copyAction,
    FileItemAction.move => l10n.moveAction,
    FileItemAction.archive => l10n.archiveSelectionAction,
    FileItemAction.exportToDevice => l10n.exportToDeviceAction,
    FileItemAction.encrypt => l10n.cryptoDirectionEncrypt,
    FileItemAction.decrypt => l10n.cryptoDirectionDecrypt,
    FileItemAction.docProvider => l10n.exposeAsDocumentProviderMenu,
    FileItemAction.syncSettings => l10n.autoSyncMenuAction,
    FileItemAction.pin => l10n.pinAction,
    FileItemAction.bookmark => l10n.bookmarkAction,
    FileItemAction.delete => l10n.delete,
  };

  String toJson() => name;

  static FileItemAction? fromJson(String? value) {
    for (final a in FileItemAction.values) {
      if (a.name == value) return a;
    }
    return null;
  }
}
