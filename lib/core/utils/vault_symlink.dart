import 'package:flutter/foundation.dart';

/// A symbolic link inside a Cryptomator vault.
///
/// Links are fetched separately from the general filesystem listing so sync,
/// export and scanners do not recurse through them. The interactive browser
/// merges them into its visible listing as shortcut entries. Path access follows
/// relative targets within the same vault; link-node rename/delete remain no-follow.
///
/// Wire shape (from `foldervault_bridge.cpp`, only ever produced by the symlink listing):
///   "L|targetBytes|unixSecs|name"   (file target or broken link)
///   "LD|0|unixSecs|name"           (directory target)
@immutable
class VaultSymlink {
  const VaultSymlink({
    required this.name,
    required this.targetBytes,
    required this.modifiedSecs,
    this.isDir = false,
  });

  final String name;

  /// Length of the link target in bytes (UTF-8).
  final int targetBytes;

  /// Last-modified time in Unix seconds (UTC); 0 = unknown.
  final int modifiedSecs;

  /// Whether the link currently resolves to a directory inside the vault.
  final bool isDir;

  /// Parses one `L|...` or `LD|...` wire entry; null for anything else (never throws).
  static VaultSymlink? tryParse(String raw) {
    final a = raw.indexOf('|');
    if (a < 0 ||
        (raw.substring(0, a) != 'L' && raw.substring(0, a) != 'LD')) {
      return null;
    }
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
      isDir: raw.substring(0, a) == 'LD',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is VaultSymlink &&
      other.name == name &&
      other.targetBytes == targetBytes &&
      other.modifiedSecs == modifiedSecs &&
      other.isDir == isDir;

  @override
  int get hashCode => Object.hash(name, targetBytes, modifiedSecs, isDir);
}
