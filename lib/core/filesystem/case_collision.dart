/// Finds sets of relative paths that name the *same* entry on a
/// case-insensitive filesystem even though they are different strings
/// ("Docs/Notes.txt" and "docs/notes.txt"), which is what makes extracting
/// both of them silently overwrite one with the other.
///
/// [filePaths] are the files that would be written, as `/`-separated paths
/// relative to the extraction target. Every ancestor directory of each file
/// is considered too, so a file `docs` colliding with the implied directory
/// `Docs/` of another entry is also reported. Two directories that differ
/// only by case are *not* reported on their own: merging them loses nothing
/// unless two files inside them collide, and that case is caught by the
/// file comparison.
///
/// Returns one list per colliding group, each holding every distinct
/// spelling in the group (at least two, in first-seen order). An empty
/// result means the paths can be written to a case-insensitive destination
/// without any of them replacing another.
List<List<String>> findCaseCollisions(Iterable<String> filePaths) {
  final files = <String, List<String>>{};
  final dirs = <String, String>{};

  for (final raw in filePaths) {
    final path = raw.replaceAll('\\', '/');
    final spellings = files.putIfAbsent(path.toLowerCase(), () => <String>[]);
    if (!spellings.contains(path)) spellings.add(path);

    var slash = path.indexOf('/');
    while (slash != -1) {
      final dir = path.substring(0, slash);
      dirs.putIfAbsent(dir.toLowerCase(), () => dir);
      slash = path.indexOf('/', slash + 1);
    }
  }

  final result = <List<String>>[];
  for (final entry in files.entries) {
    final group = List<String>.of(entry.value);
    final dir = dirs[entry.key];
    if (dir != null && !group.contains(dir)) group.add(dir);
    if (group.length > 1) result.add(group);
  }
  return result;
}
