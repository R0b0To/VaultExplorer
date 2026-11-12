import 'package:flutter/foundation.dart';

/// A symbolic link inside a Cryptomator vault.
///
/// A link is neither a file nor a folder as far as this app is concerned: it is never followed (its target could
/// point anywhere), it is never read, exported or synced as content, and it is not part of a normal directory
/// listing at all -- [RawEntry] therefore cannot represent one. It is fetched through its own call
/// (`VaultFileIoApi.listVaultSymlinks`) by the one screen that knows how to show it.
///
/// Wire shape (from `foldervault_bridge.cpp`, only ever produced by the symlink listing):
///   "L|targetBytes|unixSecs|name"
@immutable
class VaultSymlink {
  const VaultSymlink({
    required this.name,
    required this.targetBytes,
    required this.modifiedSecs,
  });

  final String name;

  /// Length of the link target in bytes (UTF-8).
  final int targetBytes;

  /// Last-modified time in Unix seconds (UTC); 0 = unknown.
  final int modifiedSecs;

  /// Parses one `L|...` wire entry; null for anything else (never throws).
  static VaultSymlink? tryParse(String raw) {
    final a = raw.indexOf('|');
    if (a < 0 || raw.substring(0, a) != 'L') return null;
    final b = raw.indexOf('|', a + 1);
    if (b < 0) return null;
    final c = raw.indexOf('|', b + 1);
    if (c < 0) return null;
    final name = raw.substring(c + 1);
    if (name.isEmpty) return null;
    return VaultSymlink(
      name: name,
      targetBytes: int.tryParse(raw.substring(a + 1, b)) ?? 0,
      modifiedSecs: int.tryParse(raw.substring(b + 1, c)) ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is VaultSymlink &&
      other.name == name &&
      other.targetBytes == targetBytes &&
      other.modifiedSecs == modifiedSecs;

  @override
  int get hashCode => Object.hash(name, targetBytes, modifiedSecs);
}
