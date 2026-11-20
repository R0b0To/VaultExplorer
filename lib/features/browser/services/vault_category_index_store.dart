import 'dart:convert';
import 'dart:typed_data';

import 'package:vaultexplorer/features/browser/models/category_index.dart';

/// The few file operations the index needs from one vault. A small interface
/// instead of the whole file API, so the store is tested with a map standing
/// in for the vault.
abstract interface class CategoryIndexStorage {
  /// Whether [dir] holds a file called [name].
  Future<bool> fileExists(String dir, String name);

  Future<Uint8List?> read(String path);

  /// Creates [dir] if needed and writes [bytes] to [path]; false when the
  /// vault cannot be written to.
  Future<bool> write(String dir, String path, Uint8List bytes);

  Future<bool> delete(String path);
}

/// Reads and writes the category index of one vault.
///
/// The file sits in the vault's own configuration folder, next to its
/// bookmarks and sync settings: encrypted at rest, carried with the vault, and
/// never synchronized. A vault that cannot be written to (read-only) can still
/// have an index read from it, but never gets one written.
class VaultCategoryIndexStore {
  VaultCategoryIndexStore(
    this._storage, {
    required String metaDir,
    this.fileName = 'category_index.json',
  }) : _metaDir = metaDir;

  final CategoryIndexStorage _storage;
  final String _metaDir;
  final String fileName;

  String get _path => '$_metaDir/$fileName';

  /// The stored index, or [VaultCategoryIndex.empty] when there is none, it
  /// cannot be read, or it is of another version.
  Future<VaultCategoryIndex> load() async {
    try {
      if (!await _storage.fileExists(_metaDir, fileName)) {
        return VaultCategoryIndex.empty;
      }
      final bytes = await _storage.read(_path);
      if (bytes == null || bytes.isEmpty) return VaultCategoryIndex.empty;
      return VaultCategoryIndex.fromJson(jsonDecode(utf8.decode(bytes)));
    } on FormatException {
      // A damaged file counts as no index; the next scan replaces it.
      return VaultCategoryIndex.empty;
    }
  }

  /// Stores [section] for [categoryKey], keeping what the index already holds
  /// for the other categories. Returns whether it was written.
  Future<bool> saveSection(
    String categoryKey,
    CategoryIndexSection section,
  ) async {
    final current = await load();
    final existing = current.sections[categoryKey];
    // Nothing changed since the last scan: leave the file alone.
    if (existing != null && existing.hasSameEntriesAs(section)) return true;
    final updated = current.withSection(categoryKey, section);
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(updated.toJson())));
    return _storage.write(_metaDir, _path, bytes);
  }

  /// Removes the index file. Returns whether it is gone afterwards.
  Future<bool> delete() async {
    if (!await _storage.fileExists(_metaDir, fileName)) return true;
    return _storage.delete(_path);
  }
}
