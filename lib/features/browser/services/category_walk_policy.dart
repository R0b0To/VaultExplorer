/// Which folders of phone storage a category scan never needs to enter.
///
/// A scan that lists everything it can reach spends nearly all its time in
/// folders that can only ever hold app internals: package caches, build
/// output, the system's recovery folders. Skipping them is what keeps a walk
/// from turning into thousands of listings for a handful of results.
///
/// The same policy is applied to a walk and to the results of the platform's
/// media index (see `DeviceCategoryIndex`), so a category shows the same files
/// whichever way they were found.
library;

/// Folder names (compared lower-cased, at any depth) that hold nothing a
/// person would look for in a category.
///
/// Kept deliberately short and conservative: every entry hides real files if
/// someone keeps their own folder by that name.
const Set<String> kCategoryPrunedFolderNames = {
  'node_modules',
  '__pycache__',
  'lost+found',
  'lost.dir',
  '.thumbnails',
  '.cache',
  'cache',
  'caches',
};

/// Android keeps these two off limits to other apps; listing them only costs
/// time. [dirPath] is relative to the storage root.
bool skipPrivateAndroidFolders(String dirPath) =>
    dirPath == 'Android/data' || dirPath == 'Android/obb';

/// Whether the folder at [dirPath] (relative to the storage root) is one of
/// [kCategoryPrunedFolderNames].
bool isPrunedCategoryFolder(String dirPath) {
  final slash = dirPath.lastIndexOf('/');
  final name = slash < 0 ? dirPath : dirPath.substring(slash + 1);
  return kCategoryPrunedFolderNames.contains(name.toLowerCase());
}

/// The skip rule of a scan of plain phone storage: the folders Android keeps
/// private plus the ones that only hold app internals.
bool skipDeviceCategoryFolder(String dirPath) =>
    skipPrivateAndroidFolders(dirPath) || isPrunedCategoryFolder(dirPath);

/// Whether any folder above [filePath] (a path relative to the storage root,
/// the file name last) is one [skipDirectory] rejects.
///
/// This is how a flat list of paths, which never visits folders, applies the
/// same rule a walk applies when it decides not to descend. [verdicts] caches
/// the answer per folder, so a long list under few folders asks each folder
/// once; pass one map for the whole list.
bool hasSkippedAncestor(
  String filePath,
  bool Function(String dirPath) skipDirectory,
  Map<String, bool> verdicts,
) {
  var slash = filePath.indexOf('/');
  while (slash >= 0) {
    final dir = filePath.substring(0, slash);
    final skipped = verdicts[dir] ??= skipDirectory(dir);
    if (skipped) return true;
    slash = filePath.indexOf('/', slash + 1);
  }
  return false;
}
