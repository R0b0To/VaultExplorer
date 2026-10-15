/// Renames relative paths so that none of them names the same entry as
/// another on a case-insensitive filesystem, which is what would otherwise
/// make extracting "Docs/Notes.txt" and "docs/notes.txt" silently overwrite
/// one with the other.
///
/// [paths] are the files that would be written, as `/`-separated paths
/// relative to the extraction target (backslashes are normalised). The
/// result has the same length and order. A path that does not collide is
/// returned unchanged. For each group of paths that differ only by case,
/// the first keeps its name and every later one gets a unique
/// "name (1).ext" leaf in its own directory -- the same outcome as choosing
/// "keep both" on a paste conflict. The new name also avoids every other
/// path in the list, so a rename can never land on a real entry.
///
/// Two further cases count as collisions: a file whose name matches
/// another entry's directory ("docs" vs the implied "Docs/" of
/// "Docs/a.txt"), which is renamed, and two entries with the identical path,
/// which are left alone (an archive that lists a path twice means "the later
/// one wins", exactly as before). Two directories that differ only by case
/// merge harmlessly and are not touched; only files inside them that
/// collide are renamed.
List<String> resolveCaseCollisionPaths(List<String> paths) {
  final normalized = [for (final p in paths) p.replaceAll('\\', '/')];

  final taken = <String>{for (final p in normalized) p.toLowerCase()};
  final dirs = <String>{};
  for (final path in normalized) {
    var slash = path.indexOf('/');
    while (slash != -1) {
      dirs.add(path.substring(0, slash).toLowerCase());
      slash = path.indexOf('/', slash + 1);
    }
  }

  final claimedBy = <String, String>{}; // folded path -> exact spelling
  final result = <String>[];
  for (final path in normalized) {
    final key = path.toLowerCase();
    final owner = claimedBy[key];
    if (owner == path) {
      result.add(path); // identical duplicate: leave as before
      continue;
    }
    if (owner == null && !dirs.contains(key)) {
      claimedBy[key] = path;
      result.add(path);
      continue;
    }

    final slash = path.lastIndexOf('/');
    final dir = slash == -1 ? '' : path.substring(0, slash + 1);
    final leaf = path.substring(slash + 1);
    final dot = leaf.lastIndexOf('.');
    final hasExt = dot > 0 && dot < leaf.length - 1;
    final stem = hasExt ? leaf.substring(0, dot) : leaf;
    final ext = hasExt ? leaf.substring(dot) : '';

    var n = 1;
    while (true) {
      final candidate = '$dir$stem ($n)$ext';
      final ckey = candidate.toLowerCase();
      if (!taken.contains(ckey) &&
          !claimedBy.containsKey(ckey) &&
          !dirs.contains(ckey)) {
        taken.add(ckey);
        claimedBy[ckey] = candidate;
        result.add(candidate);
        break;
      }
      n++;
    }
  }
  return result;
}
