import 'dart:convert';

/// The longest link target the engine stores: 32767 bytes of UTF-8 (the size official Cryptomator can read back).
const int kMaxSymlinkTargetBytes = 32767;

/// Why a symbolic-link target cannot be stored. Mirrors `createSymlink` in the native engine, which refuses
/// exactly these (and malformed UTF-8, which a Dart string cannot produce).
enum SymlinkTargetIssue { empty, tooLong, containsNul }

/// Checks whether [target] can be stored. The text is preserved exactly; at access time the native engine
/// resolves relative targets within the same vault and refuses absolute paths. Existence is checked when used.
/// Null when the target can be stored.
SymlinkTargetIssue? validateSymlinkTarget(String target) {
  if (target.isEmpty) return SymlinkTargetIssue.empty;
  if (target.contains('\u0000')) return SymlinkTargetIssue.containsNul;
  // Cheap bound first: a code unit is at least 1 byte, so this many cannot fit in 32767 bytes.
  if (target.length > kMaxSymlinkTargetBytes) return SymlinkTargetIssue.tooLong;
  if (utf8.encode(target).length > kMaxSymlinkTargetBytes) {
    return SymlinkTargetIssue.tooLong;
  }
  return null;
}
