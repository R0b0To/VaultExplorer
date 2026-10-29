import 'package:vaultexplorer/core/utils/file_type_utils.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/core/utils/storage_uri_path.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';

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

/// Field keys, shared across every Item Vault entry type that has one
/// (`password`'s `username`, `identity`'s and `softwareLicense`'s `email`),
/// that search also matches against -- same idea real password managers
/// use: finding an entry by the login it's *for*, not just by its title.
/// Kept as a flat key list rather than switching on [VaultItemType] so a
/// future field named `username`/`email` on another item type is picked up
/// automatically.
const List<String> kVaultItemSearchableFieldKeys = ['username', 'email', 'issuer', 'account'];

/// Whether [name]'s extension identifies it as an Item Vault entry
/// (password/card/identity/note/bank account/license) rather than an
/// ordinary file -- the same extension set [vaultIconForExt] and the
/// `'secure'` browser filter already key off of.
bool isVaultItemFileName(String name) {
  final dot = name.lastIndexOf('.');
  if (dot == -1) return false;
  return vaultIconForExt(name.substring(dot + 1)) != null;
}

String joinPath(String name, String currentDirPath) =>
    currentDirPath.isEmpty ? name : '$currentDirPath/$name';

String fullPathOf(RawEntry entry, String currentDirPath) =>
    joinPath(entry.name, currentDirPath);

/// What "Copy path" puts on the clipboard for the item at [relativePath]
/// inside a storage rooted at [rootPath] ('' [relativePath] is the root).
///
/// A device or external storage is a real folder, so its items get the real
/// path (root + relative) -- the form other apps and a terminal understand. A
/// root given as a SAF URI is turned back into its path first (see
/// [readablePathFromUri]). A vault's contents only exist inside the
/// container, so there the path is the in-vault one, the same "Full Path" the
/// file info sheet shows; it is also the fallback when a storage's root has
/// no filesystem path, since gluing a path onto a URI would not make one.
String clipboardPathFor({
  required String relativePath,
  required String rootPath,
  required bool isLocalStorage,
}) {
  if (!isLocalStorage) return relativePath;
  final root = readablePathFromUri(rootPath);
  if (!root.startsWith('/')) return relativePath;
  final trimmed = root.length > 1 && root.endsWith('/')
      ? root.substring(0, root.length - 1)
      : root;
  if (relativePath.isEmpty) return trimmed;
  return trimmed == '/' ? '/$relativePath' : '$trimmed/$relativePath';
}

/// Splits [fullPath] (`a/b/c.txt`) into the folder it lives in (`a/b`, or ''
/// for the vault root) and its last segment (`c.txt`).
({String parent, String name}) splitParentAndName(String fullPath) {
  final slash = fullPath.lastIndexOf('/');
  return slash == -1
      ? (parent: '', name: fullPath)
      : (
          parent: fullPath.substring(0, slash),
          name: fullPath.substring(slash + 1),
        );
}

bool isFolderMounted(
  RawEntry entry,
  String currentDirPath,
  Set<String> mountedDocProviderFolders,
) =>
    entry.isDir && mountedDocProviderFolders.contains(fullPathOf(entry, currentDirPath));

bool isPinned(RawEntry entry, String currentDirPath, Set<String> pinnedPaths) =>
    pinnedPaths.contains(fullPathOf(entry, currentDirPath));

bool isBookmark(RawEntry entry, String currentDirPath, List<String> bookmarkPaths) =>
    bookmarkPaths.contains(fullPathOf(entry, currentDirPath));

bool isHiddenEntryName(String name) {
  if (name.isEmpty) return false;
  if (name.contains('/')) {
    return name.split('/').any((seg) => seg.isNotEmpty && isHiddenSingleName(seg));
  }
  return isHiddenSingleName(name);
}

bool isHiddenSingleName(String name) {
  if (name.isEmpty) return false;
  final first = name.codeUnitAt(0);
  if (first == 0x2E) return true; // '.'
  // This runs once per entry on every listing rebuild, and nearly every name
  // is an ordinary one. The system names below start with l, s, r, f or $
  // (either case), so any other first character settles it without
  // lower-casing the whole name. No non-ASCII character lower-cases to one
  // of those five, so this cannot skip a name that would have matched.
  switch (first | 0x20) {
    case 0x6C: // l
    case 0x73: // s
    case 0x72: // r
    case 0x66: // f
    case 0x24: // $
      break;
    default:
      return false;
  }
  final lower = name.toLowerCase();
  switch (lower) {
    case 'lost+found':
    case 'lost.dir':
    case 'system volume information':
    case '\$recycle.bin':
    case 'recycled':
    case 'recycler':
      return true;
  }
  return _isFoundDotDigits(lower);
}

/// `found.<digits>` (chkdsk's recovered-fragment folders), already
/// lower-cased. Hand-rolled rather than a RegExp: the pattern was rebuilt on
/// every call.
bool _isFoundDotDigits(String lower) {
  const prefix = 'found.';
  if (lower.length <= prefix.length || !lower.startsWith(prefix)) return false;
  for (var i = prefix.length; i < lower.length; i++) {
    final c = lower.codeUnitAt(i);
    if (c < 0x30 || c > 0x39) return false;
  }
  return true;
}

bool matchesFilter(String fileName, String? currentFilter) {
  if (currentFilter == null) return true;
  switch (currentFilter) {
    case 'image':
      return MediaViewerConstants.isImage(fileName);
    case 'video':
      return MediaViewerConstants.isVideo(fileName);
    case 'audio':
      return MediaViewerConstants.isAudio(fileName);
    case 'document':
      return kBrowserFilterDocumentExtensions.contains(
        _extensionAfterLastDot(fileName).toLowerCase(),
      );
    case 'secure':
      return vaultIconForExt(_extensionAfterLastDot(fileName)) != null;
    default:
      return true;
  }
}

/// Everything after the last '.', or the whole name when it has none --
/// what `name.split('.').last` returns, without building the list.
String _extensionAfterLastDot(String fileName) {
  final dot = fileName.lastIndexOf('.');
  return dot == -1 ? fileName : fileName.substring(dot + 1);
}
