import 'dart:convert';

/// The longest link target the engine stores: 32767 bytes of UTF-8 (the size official Cryptomator can read back).
const int kMaxSymlinkTargetBytes = 32767;

/// Why a symbolic-link target cannot be stored. Mirrors `createSymlink` in the native engine, which refuses
/// exactly these (and malformed UTF-8, which a Dart string cannot produce).
enum SymlinkTargetIssue { empty, tooLong, containsNul, outsideVault }

/// Checks target encoding and storage size without testing whether it exists.
/// For native ext/NTFS links, [requireRelativeInsideVault] additionally
/// enforces the container-root boundary. Cryptomator keeps its existing target
/// representation. Null means the target can be stored.
SymlinkTargetIssue? validateSymlinkTarget(
  String target, {
  String parentPath = '',
  bool requireRelativeInsideVault = false,
}) {
  if (target.isEmpty) return SymlinkTargetIssue.empty;
  if (target.contains('\u0000')) return SymlinkTargetIssue.containsNul;
  // Cheap bound first: a code unit is at least 1 byte, so this many cannot fit in 32767 bytes.
  if (target.length > kMaxSymlinkTargetBytes) return SymlinkTargetIssue.tooLong;
  if (utf8.encode(target).length > kMaxSymlinkTargetBytes) {
    return SymlinkTargetIssue.tooLong;
  }

  if (requireRelativeInsideVault) {
    // Treat both slash styles as separators so Windows drive/UNC/absolute
    // paths cannot bypass the same-container restriction on NTFS.
    if (target.startsWith('/') ||
        target.startsWith('\\') ||
        RegExp(r'^[A-Za-z]:').hasMatch(target)) {
      return SymlinkTargetIssue.outsideVault;
    }

    final stack = <String>[];
    bool consume(String value) {
      for (final part in value.split(RegExp(r'[/\\]+'))) {
        if (part.isEmpty || part == '.') continue;
        if (part == '..') {
          if (stack.isEmpty) return false;
          stack.removeLast();
        } else {
          stack.add(part);
        }
      }
      return true;
    }

    if (!consume(parentPath) || !consume(target)) {
      return SymlinkTargetIssue.outsideVault;
    }
  }
  return null;
}
