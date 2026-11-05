/// One indexed file of a category: where it is inside the vault, and the size
/// and date the scan saw.
class CategoryIndexEntry {
  const CategoryIndexEntry(this.path, this.sizeBytes, this.modifiedSecs);

  /// Path from the vault root ('DCIM/Camera/1.jpg').
  final String path;
  final int sizeBytes;
  final int modifiedSecs;

  List<Object> toJson() => [path, sizeBytes, modifiedSecs];

  /// Null for anything that is not a well-formed entry, so one bad element
  /// cannot throw away the rest of the index.
  static CategoryIndexEntry? tryFromJson(Object? raw) {
    if (raw is! List || raw.length != 3) return null;
    final path = raw[0];
    final size = raw[1];
    final modified = raw[2];
    if (path is! String || path.isEmpty || size is! int || modified is! int) {
      return null;
    }
    return CategoryIndexEntry(path, size, modified);
  }

  @override
  bool operator ==(Object other) =>
      other is CategoryIndexEntry &&
      other.path == path &&
      other.sizeBytes == sizeBytes &&
      other.modifiedSecs == modifiedSecs;

  @override
  int get hashCode => Object.hash(path, sizeBytes, modifiedSecs);
}

/// What one full scan of a vault found for one category.
class CategoryIndexSection {
  const CategoryIndexSection({
    required this.builtAtSecs,
    required this.entries,
  });

  /// When the scan finished, in seconds since the epoch.
  final int builtAtSecs;
  final List<CategoryIndexEntry> entries;

  /// Whether [other] lists exactly the same files, so a rescan that found
  /// nothing new does not rewrite the index.
  bool hasSameEntriesAs(CategoryIndexSection other) {
    if (entries.length != other.entries.length) return false;
    final mine = entries.toSet();
    for (final entry in other.entries) {
      if (!mine.contains(entry)) return false;
    }
    return true;
  }
}

/// The category index of one vault: for each category that has been opened, the
/// files a scan found. It lets the category browser show a vault's files
/// straight away and refresh them in the background.
///
/// It is kept inside the vault, with the vault's other configuration (see
/// `VaultCategoryIndexStore`), so it is encrypted with the vault, travels with
/// it, and is only readable while it is unlocked.
class VaultCategoryIndex {
  const VaultCategoryIndex(this.sections);

  static const VaultCategoryIndex empty = VaultCategoryIndex({});

  /// Bumped when the stored layout changes; an index of another version is
  /// ignored (and replaced by the next scan) rather than misread.
  static const int version = 1;

  /// By `FileCategory.storageKey`.
  final Map<String, CategoryIndexSection> sections;

  VaultCategoryIndex withSection(String categoryKey, CategoryIndexSection s) =>
      VaultCategoryIndex({...sections, categoryKey: s});

  Map<String, Object?> toJson() => {
    'v': version,
    'categories': {
      for (final e in sections.entries)
        e.key: {
          'built': e.value.builtAtSecs,
          'files': [for (final f in e.value.entries) f.toJson()],
        },
    },
  };

  /// Reads a stored index; anything unrecognised is [empty].
  static VaultCategoryIndex fromJson(Object? raw) {
    if (raw is! Map || raw['v'] != version) return empty;
    final categories = raw['categories'];
    if (categories is! Map) return empty;
    final sections = <String, CategoryIndexSection>{};
    for (final e in categories.entries) {
      final key = e.key;
      final value = e.value;
      if (key is! String || value is! Map) continue;
      final built = value['built'];
      final files = value['files'];
      if (built is! int || files is! List) continue;
      sections[key] = CategoryIndexSection(
        builtAtSecs: built,
        entries: [
          for (final f in files)
            if (CategoryIndexEntry.tryFromJson(f) case final entry?) entry,
        ],
      );
    }
    return VaultCategoryIndex(sections);
  }
}
