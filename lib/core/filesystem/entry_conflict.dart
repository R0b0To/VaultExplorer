import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

import '../utils/raw_entry.dart';

/// Result of checking a candidate name against a directory's existing
/// entries. See docs/architecture.md ADR-004.
enum EntryConflictKind {
  /// No existing entry has this exact name.
  none,

  /// An entry with this exact name already exists, and it's the same type
  /// (file vs. folder) as what's being created/renamed to.
  sameType,

  /// An entry with this exact name already exists, but it's the *other*
  /// type — e.g. creating a folder called "Notes" when a file called
  /// "Notes" is already there, or vice versa. This is the case the request
  /// specifically calls out: it must never be silently allowed to
  /// overwrite or merge.
  crossType,
}

class EntryConflictResult {
  final EntryConflictKind kind;

  /// The existing entry that collides, if [kind] isn't [EntryConflictKind.none].
  final RawEntry? existing;

  const EntryConflictResult(this.kind, this.existing);

  bool get isConflict => kind != EntryConflictKind.none;

  String? message(AppLocalizations l10n, String candidateName) {
    switch (kind) {
      case EntryConflictKind.none:
        return null;
      case EntryConflictKind.sameType:
        final noun = existing!.isDir ? l10n.nounFolder : l10n.nounFile;
        return l10n.conflictSameType(noun, candidateName);
      case EntryConflictKind.crossType:
        final existingNoun = existing!.isDir ? l10n.nounFolder : l10n.nounFile;
        final candidateNoun = existing!.isDir ? l10n.nounFile : l10n.nounFolder;
        return l10n.conflictCrossType(existingNoun, candidateName, candidateNoun);
    }
  }
}

/// Checks [candidateName] (an exact, unmutated name — see name_validation.dart)
/// against [existingEntries] (the directory listing already loaded for the
/// current folder) for a same-name collision, distinguishing "collides with
/// a same-type entry" from "collides with the opposite type" so callers can
/// give a precise message for each. This mirrors, at the Dart/UI layer, the
/// fail-closed behavior ADR-004 makes the native create/rename calls
/// enforce as well — this check exists to give the user an immediate,
/// specific reason *before* the native call is even made, not to replace
/// the native guard (which also covers races and non-UI callers).
///
/// [candidateIsDir] is which type the candidate itself is (what's being
/// created, or what's being renamed — the type never changes across a
/// rename).
///
/// [caseSensitive] must reflect the target filesystem: FAT32/exFAT/NTFS
/// treat "Notes" and "notes" as the same name (so pass `false`); ext2/3/4
/// treats them as different names (pass `true`). See
/// [FilesystemRules.of]/`FilesystemType` — callers should derive this from
/// the same [FilesystemType] used for [validateEntryName], not guess
/// independently.
EntryConflictResult checkEntryConflict({
  required String candidateName,
  required bool candidateIsDir,
  required List<RawEntry> existingEntries,
  required bool caseSensitive,
  RawEntry? excluding,
}) {
  final candidateKey = caseSensitive ? candidateName : candidateName.toLowerCase();
  for (final entry in existingEntries) {
    if (excluding != null && entry == excluding) continue;
    final entryKey = caseSensitive ? entry.name : entry.name.toLowerCase();
    if (entryKey != candidateKey) continue;
    final kind = entry.isDir == candidateIsDir
        ? EntryConflictKind.sameType
        : EntryConflictKind.crossType;
    return EntryConflictResult(kind, entry);
  }
  return const EntryConflictResult(EntryConflictKind.none, null);
}
