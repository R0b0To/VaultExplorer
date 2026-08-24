import 'package:vaultexplorer/core/utils/file_type_utils.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
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

String joinPath(String name, String currentDirPath) =>
    currentDirPath.isEmpty ? name : '$currentDirPath/$name';

String fullPathOf(RawEntry entry, String currentDirPath) =>
    joinPath(entry.name, currentDirPath);

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
  if (name.startsWith('.')) return true;
  final lower = name.toLowerCase();
  if (lower == 'lost+found' ||
      lower == 'lost.dir' ||
      lower == 'system volume information' ||
      lower == '\$recycle.bin' ||
      lower == 'recycled' ||
      lower == 'recycler') {
    return true;
  }
  if (RegExp(r'^found\.\d+$', caseSensitive: false).hasMatch(lower)) {
    return true;
  }
  return false;
}

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
      return vaultIconForExt(ext) != null;
    default:
      return true;
  }
}