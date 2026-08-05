import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

import 'filesystem_type.dart';

/// Whether the entry being named is a file or a folder. Validation rules
/// themselves don't differ by this (a reserved device name is reserved for
/// both), but it's threaded through so messages can say "folder" or "file"
/// instead of the generic "entry".
enum EntryType { file, folder }

/// Every distinct reason [validateEntryName] can reject a name. Kept
/// separate from the human-readable message so callers (tests, or a future
/// UI that wants icons per reason) can switch on it without parsing text.
enum NameValidationReason {
  empty,
  isDotOrDotDot,
  illegalCharacter,
  controlCharacter,
  reservedDeviceName,
  trailingSpace,
  trailingDot,
  componentTooLong,
}

/// One specific problem with a candidate name. A single name can have more
/// than one — [validateEntryName] collects all of them rather than
/// stopping at the first, so the UI can show the complete list at once.
class NameValidationIssue {
  final NameValidationReason reason;

  /// Precise, user-facing explanation. Always mentions *why* — which
  /// filesystem, which character, which limit — never a generic
  /// "invalid name".
  final String message;

  /// UTF-16 code-unit index into the original (unmodified) input string
  /// where the problem is, if the reason is tied to a specific character.
  /// Null for reasons that describe the name as a whole (too long, empty).
  final int? charIndex;

  const NameValidationIssue({
    required this.reason,
    required this.message,
    this.charIndex,
  });

  @override
  String toString() => message;
}

/// Outcome of validating one path component. Never carries a "corrected"
/// name — only ever the original input plus a verdict.
class NameValidationResult {
  final String name;
  final List<NameValidationIssue> issues;

  const NameValidationResult({required this.name, required this.issues});

  bool get isValid => issues.isEmpty;

  @override
  String toString() => isValid
      ? 'NameValidationResult(valid: "$name")'
      : 'NameValidationResult(invalid: "$name", ${issues.length} issue(s))';
}

/// Validates [name] as a single path component (a file or folder name, not
/// a full path — see path_components.dart for validating a whole path) for
/// [fsType].
///
/// This function is pure: it never trims, normalizes, replaces, truncates,
/// or otherwise changes [name]. It only classifies it. Every violated rule
/// is reported (not just the first) so the caller can show the complete
/// picture in one pass. See docs/architecture.md ADR-002.
NameValidationResult validateEntryName(
  String name,
  FilesystemType fsType, {
  required EntryType entryType,
  required AppLocalizations l10n,
}) {
  final issues = <NameValidationIssue>[];
  final rules = FilesystemRules.of(fsType);
  final noun = entryType == EntryType.file ? l10n.nounFile : l10n.nounFolder;
  final nounCapitalized =
      entryType == EntryType.file ? l10n.nounFileCapitalized : l10n.nounFolderCapitalized;

  // Empty / "." / ".." are path-navigation tokens on every filesystem this
  // app deals with, not fs-specific rules, so they're checked unconditionally.
  if (name.isEmpty) {
    issues.add(NameValidationIssue(
      reason: NameValidationReason.empty,
      message: l10n.validationEmptyName,
    ));
    // Nothing else to check on an empty string.
    return NameValidationResult(name: name, issues: issues);
  }

  if (name == '.' || name == '..') {
    issues.add(NameValidationIssue(
      reason: NameValidationReason.isDotOrDotDot,
      message: l10n.validationReservedNavName(name, noun),
    ));
  }

  // Character-level checks: walk UTF-16 code units so [charIndex] lines up
  // exactly with what the user sees/edits in a standard text field.
  for (var i = 0; i < name.length; i++) {
    final code = name.codeUnitAt(i);

    if (rules.illegalCharCodes.contains(code)) {
      issues.add(NameValidationIssue(
        reason: NameValidationReason.illegalCharacter,
        message: l10n.validationIllegalChar(
          String.fromCharCode(code),
          i + 1,
          fsType.label(l10n),
        ),
        charIndex: i,
      ));
      continue;
    }

    final isControl = code <= 0x1F || code == 0x7F;
    if (isControl && rules.disallowControlChars) {
      issues.add(NameValidationIssue(
        reason: NameValidationReason.controlCharacter,
        message: l10n.validationControlChar(
          i + 1,
          '0x${code.toRadixString(16).padLeft(2, '0')}',
          fsType.label(l10n),
        ),
        charIndex: i,
      ));
    }
  }

  if (rules.disallowReservedDeviceNames && isReservedDeviceName(name)) {
    issues.add(NameValidationIssue(
      reason: NameValidationReason.reservedDeviceName,
      message: l10n.validationReservedDeviceName(name, fsType.label(l10n)),
    ));
  }

  if (rules.disallowTrailingSpaceOrDot) {
    if (name.endsWith(' ')) {
      issues.add(NameValidationIssue(
        reason: NameValidationReason.trailingSpace,
        message: l10n.validationTrailingSpace(nounCapitalized, fsType.label(l10n)),
        charIndex: name.length - 1,
      ));
    }
    if (name.endsWith('.')) {
      issues.add(NameValidationIssue(
        reason: NameValidationReason.trailingDot,
        message: l10n.validationTrailingDot(nounCapitalized, fsType.label(l10n)),
        charIndex: name.length - 1,
      ));
    }
  }

  final measuredLength = rules.maxComponentLengthIsUtf8Bytes
      ? _utf8Length(name)
      : name.length;
  if (measuredLength > rules.maxComponentLength) {
    final unit = rules.maxComponentLengthIsUtf8Bytes ? l10n.unitBytes : l10n.unitCharacters;
    issues.add(NameValidationIssue(
      reason: NameValidationReason.componentTooLong,
      message: l10n.validationNameTooLong(
        measuredLength,
        unit,
        fsType.label(l10n),
        rules.maxComponentLength,
        noun,
      ),
    ));
  }

  return NameValidationResult(name: name, issues: issues);
}

/// Byte length of [s] when encoded as UTF-8, without allocating the byte
/// list (used only to size-check ext2/3/4 names, which are limited in
/// bytes rather than characters).
int _utf8Length(String s) {
  var length = 0;
  for (final rune in s.runes) {
    if (rune <= 0x7F) {
      length += 1;
    } else if (rune <= 0x7FF) {
      length += 2;
    } else if (rune <= 0xFFFF) {
      length += 3;
    } else {
      length += 4;
    }
  }
  return length;
}
