/// What a staged [ClipboardItem] (see clipboard_item.dart) batch is
/// destined to become when the user pastes it.
///
/// Generalizes the old `isCutOperation: bool` on [ClipboardState] (see
/// cross_container_clipboard.dart) to also cover the two archive
/// operations, which now stage through the exact same "select, press a
/// button, it shows up in the app bar, navigate somewhere, paste" flow as
/// copy/move instead of running immediately in the current folder.
enum ClipboardAction {
  /// Plain copy: paste duplicates the staged items at the destination,
  /// leaving the originals in place.
  copy,

  /// Cut/move: paste moves the staged items to the destination, removing
  /// them from the source.
  move,

  /// Paste creates a new archive file at the destination from the staged
  /// items. Format, file name, and password (if any) are decided up
  /// front when the operation is staged (see
  /// BrowserDialogs.showCreateArchive) -- paste only has to answer
  /// *where*, plus whether to delete the originals afterward.
  archiveCreate,

  /// Paste extracts the staged archive's contents at the destination.
  /// The archive was already opened (and, if needed, its password
  /// already verified) when the operation was staged -- paste only has
  /// to answer whether to wrap the contents in a new folder or extract
  /// flat, plus whether to delete the source archive afterward.
  archiveExtract,
}
