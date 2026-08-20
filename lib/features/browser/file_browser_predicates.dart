// First step of pulling pure, side-effect-free logic out of
// file_browser_screen.dart's _FileBrowserScreenState -- at 2,400+ lines
// and 50+ methods, it's the largest file in the app by a wide margin,
// mixing this kind of stateless predicate logic in with navigation,
// search, clipboard, and viewer-launching side effects. These five
// functions were the cleanly-separable slice: each is a pure function of
// its explicit inputs, with no setState, no BuildContext, and no calls
// back into the rest of the State class. _FileBrowserScreenState keeps
// its existing method names as one-line forwarding wrappers (see that
// file) so no call site anywhere else in that 2,400-line file had to
// change -- only the logic itself moved, here, where it's directly
// unit-testable (see file_browser_predicates_test.dart) without needing a
// widget-test harness.
//
// Further decomposition of the stateful parts (search, navigation,
// clipboard, viewer launching) is intentionally out of scope here: unlike
// these five, that logic is deeply coupled to setState/lifecycle and
// cross-calls between the State class's own methods, and splitting it
// safely needs a compiler in the loop to catch what a purely textual
// extraction could miss.

import 'package:vaultexplorer/core/utils/file_type_utils.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';

/// Extensions the 'document' quick-filter matches, in addition to whatever
/// [MediaViewerConstants]/[vaultIconForExt] already cover for the other
/// filter categories. Extracted alongside [matchesFilter] itself (see the
/// top-of-file comment for why) rather than left as a private constant on
/// `_FileBrowserScreenState`.
const Set<String> kBrowserFilterDocumentExtensions = {
  'pdf',
  'doc',
  'docx',
  'xls',
  'xlsx',
  'ppt',
  'pptx',
  'txt',
  'rtf',
  'csv',
  'zip',
  'tar',
  'gz',
  'json',
  'xml',
};

/// The full virtual path of a bare leaf [name] given the directory
/// currently being browsed. This is the same join [fullPathOf] applies to
/// a [RawEntry]'s name -- pulled out on its own because several call
/// sites in `_FileBrowserScreenState` build a path from a plain `String`
/// they already have (a selection's resolved names, an export list)
/// rather than from a `RawEntry`.
String joinPath(String name, String currentDirPath) =>
    currentDirPath.isEmpty ? name : '$currentDirPath/$name';

/// The full virtual path of [entry] given the directory currently being
/// browsed. Root-level entries (`currentDirPath` empty) are just their own
/// name; anything deeper is `$currentDirPath/${entry.name}`.
String fullPathOf(RawEntry entry, String currentDirPath) =>
    joinPath(entry.name, currentDirPath);

/// Whether [entry] is a directory that's currently exposed to other apps
/// via the Storage Access Framework document-provider integration.
bool isFolderMounted(
  RawEntry entry,
  String currentDirPath,
  Set<String> mountedDocProviderFolders,
) =>
    entry.isDir && mountedDocProviderFolders.contains(fullPathOf(entry, currentDirPath));

/// Whether [entry] is pinned (shown in the dashboard's pinned-items
/// shortcut list).
bool isPinned(RawEntry entry, String currentDirPath, Set<String> pinnedPaths) =>
    pinnedPaths.contains(fullPathOf(entry, currentDirPath));

/// Whether [entry] is bookmarked (shown in the browser's bookmark bar).
bool isBookmark(RawEntry entry, String currentDirPath, List<String> bookmarkPaths) =>
    bookmarkPaths.contains(fullPathOf(entry, currentDirPath));

/// Whether [fileName] matches the active quick filter (`null` = no filter,
/// everything matches). `currentFilter` is one of the string constants
/// used by `FilterMenuButton` ('image' / 'video' / 'audio' / 'document' /
/// 'secure'); an unrecognized value matches everything, same as `null`,
/// rather than hiding every file.
bool matchesFilter(String fileName, String? currentFilter) {
  if (currentFilter == null) return true;
  final ext = fileName.split('.').last;
  switch (currentFilter) {
    case 'image':
      return MediaViewerConstants.isImage(fileName);
    case 'video':
      return MediaViewerConstants.isVideo(fileName);
    case 'audio':
      return MediaViewerConstants.isAudio(fileName);
    case 'document':
      return kBrowserFilterDocumentExtensions.contains(ext.toLowerCase());
    case 'secure':
      // Deliberately NOT lowercased, unlike the 'document' branch above.
      // vaultIconForExt()'s switch is case-sensitive over VaultItemType's
      // enum .name values ('paymentCard', 'bankAccount',
      // 'softwareLicense', ...), exactly as every other call site in the
      // app passes it (file_tile.dart, bookmark_bar.dart,
      // file_grid_view.dart, file_masonry_view.dart all use
      // `name.split('.').last` with no .toLowerCase()). Lowercasing here
      // silently broke this filter for 5 of the 6 vault item types before
      // this fix -- only 'password' has no uppercase letters to lose, so
      // it was the only one that ever matched.
      return vaultIconForExt(ext) != null;
    default:
      return true;
  }
}
