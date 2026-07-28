/// Wire-format-safe filename sanitization, shared by every UI path that
/// lets the user type a plain file/folder name destined for the FAT/exFAT
/// volume and later re-parsed via [RawEntry] (see raw_entry.dart).
///
/// Native's `buildDirectoryListing()` (vaultexplorer.cpp) encodes each
/// directory entry as `"name|sizeBytes|unixSecs"`, prefixed with `"[DIR] "`
/// for directories. `RawEntry.parse()` splits on `|` and checks for a
/// literal `"[DIR] "` prefix to tell files from folders. Neither of those
/// wire-format decisions know anything about what characters a *file's own
/// name* is allowed to contain, so a name that happens to collide with the
/// wire format silently corrupts the listing for that one entry:
///
///   - A name containing `|` shifts every field after it — the displayed
///     name gets truncated at the first `|`, and the size/date fields get
///     parsed from whatever text landed in their slot instead (usually
///     silently defaulting to 0 / epoch via the `int.tryParse(...) ?? 0`
///     fallbacks in RawEntry.parse).
///   - A FILE literally named starting with `"[DIR] "` is indistinguishable
///     from the DIRECTORY marker native prepends, so `RawEntry.parse()`
///     misreports it as a folder (wrong icon; tapping it tries to
///     navigate in rather than open it) and silently drops the `"[DIR] "`
///     text from the displayed name.
///
/// Previously this was handled ad hoc and inconsistently: vault_item_edit_
/// screen.dart and vault_items_service.dart each carried their own copy of
/// the same `[\\/:*?"<>|]` regex (neither guarded the `"[DIR] "` case),
/// while BrowserDialogs.showCreateFolder/showCreateFile/showRename — the
/// far more common path for creating a plain file or folder — did no
/// sanitization at all. This is now the one place that logic lives.
String sanitizeFatFileName(String name) {
  // Replace illegal characters (\ / : * ? " < > |) and control chars (0x00-0x1F, 0x7F) with '_'
  var result = name.replaceAll(RegExp(r'[\x00-\x1F\x7F\\/:*?"<>|]'), '_');
  
  // Trim trailing dots and spaces (invalid in FAT/NTFS)
  result = result.replaceAll(RegExp(r'[\s.]+$'), '');

  if (result.startsWith('[DIR] ')) {
    result = '(DIR) ${result.substring(6)}';
  }
  
  // Ensure name is not empty or single hyphen
  if (result.isEmpty || result == '-') {
    result = 'unnamed';
  }
  
  return result;
}
