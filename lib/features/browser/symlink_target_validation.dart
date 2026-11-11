import 'dart:convert';

/// The longest link target the engine stores: 32767 bytes of UTF-8 (the size official Cryptomator can read back).
const int kMaxSymlinkTargetBytes = 32767;

/// Why a symbolic-link target cannot be stored. Mirrors `createSymlink` in the native engine, which refuses
/// exactly these (and malformed UTF-8, which a Dart string cannot produce).
enum SymlinkTargetIssue { empty, tooLong, containsNul }

/// Checks [target] the way the engine will, without resolving, normalising or testing it in any way: a target
/// is stored exactly as written and never followed, so "does it exist" is not a question this app asks.
/// Null when the target is fine.
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
