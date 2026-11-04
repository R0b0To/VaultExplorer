/// The file groups the drawer's category shortcuts gather from a whole storage
/// or vault into one view.
///
/// A category is the same idea as the file manager's type filter (see
/// `matchesFilter` in `file_browser_predicates.dart`): each one maps onto a
/// filter key, so what counts as an "image" or a "document" is defined in one
/// place and a category view agrees with the filter menu.
enum FileCategory {
  images('image'),
  videos('video'),
  audio('audio'),
  documents('document');

  const FileCategory(this.filterKey);

  /// The key `matchesFilter` and the browser's type filter use for this group.
  final String filterKey;

  /// Stable key for persisting which categories the drawer shows.
  String get storageKey => name;

  /// The categories in their default drawer order, as storage keys.
  static const List<String> defaultOrderKeys = [
    'images',
    'videos',
    'audio',
    'documents',
  ];

  /// [keys] as categories, in that order: unknown keys and repeats dropped,
  /// and any category the list lacks appended in its default position, so a
  /// stored order from before a category existed still shows every one.
  static List<FileCategory> orderedFrom(Iterable<String> keys) {
    final ordered = <FileCategory>[];
    for (final key in keys) {
      final category = fromStorageKey(key);
      if (category != null && !ordered.contains(category)) {
        ordered.add(category);
      }
    }
    for (final category in values) {
      if (!ordered.contains(category)) ordered.add(category);
    }
    return ordered;
  }

  static FileCategory? fromStorageKey(String? key) {
    for (final category in values) {
      if (category.name == key) return category;
    }
    return null;
  }

  static FileCategory? fromFilterKey(String? key) {
    for (final category in values) {
      if (category.filterKey == key) return category;
    }
    return null;
  }
}

/// Which kinds of storage the drawer offers category shortcuts for.
///
/// Device storage and vaults are kept apart on purpose: a vault's files only
/// exist decrypted in memory while it is unlocked, and mixing them into a view
/// of plain device files would hide which of the two a file lives in.
enum DrawerCategoryScope {
  both('both'),
  device('device'),
  vaults('vaults');

  const DrawerCategoryScope(this.storageKey);

  final String storageKey;

  bool get includesDevice => this != vaults;
  bool get includesVaults => this != device;

  static DrawerCategoryScope fromStorageKey(String? key) {
    for (final scope in values) {
      if (scope.storageKey == key) return scope;
    }
    return both;
  }
}
