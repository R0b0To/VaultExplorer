/// Which storage a category browser gathers files from.
enum CategorySourceKind { all, device, vaults, vault }

/// The source selector of a category browser: every accessible storage, only
/// phone storage, only unlocked vaults, or one particular vault.
class CategorySourceFilter {
  const CategorySourceFilter._(this.kind, [this.volId]);

  const CategorySourceFilter.vault(int volId)
    : this._(CategorySourceKind.vault, volId);

  static const all = CategorySourceFilter._(CategorySourceKind.all);
  static const device = CategorySourceFilter._(CategorySourceKind.device);
  static const vaults = CategorySourceFilter._(CategorySourceKind.vaults);

  final CategorySourceKind kind;

  /// The vault chosen, for [CategorySourceKind.vault] only.
  final int? volId;

  /// Persisted form: `all`, `device`, `vaults` or `vault:<volId>`.
  String get storageKey =>
      kind == CategorySourceKind.vault ? 'vault:$volId' : kind.name;

  /// Reads a persisted filter; anything unrecognised is [all].
  static CategorySourceFilter fromStorageKey(String? key) {
    if (key == null) return all;
    if (key == 'device') return device;
    if (key == 'vaults') return vaults;
    if (key.startsWith('vault:')) {
      final id = int.tryParse(key.substring('vault:'.length));
      if (id != null) return CategorySourceFilter.vault(id);
    }
    return all;
  }

  @override
  bool operator ==(Object other) =>
      other is CategorySourceFilter &&
      other.kind == kind &&
      other.volId == volId;

  @override
  int get hashCode => Object.hash(kind, volId);
}

/// What kind of storage a [CategorySource] is.
enum CategorySourceType { device, storageLocation, vault }

/// One storage a category scan can read: phone storage, a configured storage
/// location, or an unlocked vault. Everything the scan needs to know about it
/// is here, so the scanner and the listings never touch a container type.
class CategorySource {
  const CategorySource({
    required this.volId,
    required this.type,
    required this.label,
    this.dedupeRoot,
  });

  /// The container's volume id; unique among the sources of one scan.
  final int volId;
  final CategorySourceType type;

  /// The name shown for the source (phone storage, a vault's or a location's
  /// display name).
  final String label;

  /// For plain on-disk storage, the absolute root path. Two raw-path sources
  /// can overlap (a storage location inside phone storage); knowing the root
  /// lets the scan report a file reachable from both only once. Null for
  /// vaults and SAF trees, whose files cannot be identified that way.
  final String? dedupeRoot;

  bool get isVault => type == CategorySourceType.vault;

  /// Whether the selector [filter] includes this source.
  bool isIncludedBy(CategorySourceFilter filter) => switch (filter.kind) {
    CategorySourceKind.all => true,
    CategorySourceKind.device => !isVault,
    CategorySourceKind.vaults => isVault,
    CategorySourceKind.vault => isVault && volId == filter.volId,
  };
}
