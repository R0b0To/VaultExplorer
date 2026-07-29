import 'package:flutter/services.dart';

import 'filesystem_type.dart';

/// Blocks illegal characters and control characters as the user types,
/// instead of accepting them into the field and then flagging them.
///
/// This is *not* the same category of thing `sanitizeFatFileName` used to
/// do (see docs/architecture.md ADR-002): that mutated an already-typed
/// name after the fact, so the field could show one string while a
/// different one got saved. Here, the character never enters the field in
/// the first place — what's on screen is always exactly what gets sent to
/// [validateEntryName]/[PathComponents], letter for letter. Nothing is
/// changed after the user has typed it; a keystroke that isn't legal on
/// [fsType] simply doesn't produce a character.
///
/// Only handles the "is this character allowed at all" rule, since that's
/// the one rule that can be meaningfully enforced one keystroke at a time.
/// Reserved device names, trailing space/dot, length limits, and name
/// conflicts are still surfaced as explicit messages by
/// [validateEntryName]/`checkEntryConflict` — silently absorbing those
/// would either be incoherent (you can't know a name "ends with a dot"
/// until the dot is the last character typed, by which point silently
/// dropping it *is* the old mismatch bug) or would hide a real conflict
/// the user needs to see and act on.
class IllegalCharacterInputFormatter extends TextInputFormatter {
  final FilesystemType fsType;

  const IllegalCharacterInputFormatter(this.fsType);

  bool _isBlocked(int codeUnit, FilesystemRules rules) {
    if (rules.illegalCharCodes.contains(codeUnit)) return true;
    if (rules.disallowControlChars && (codeUnit <= 0x1F || codeUnit == 0x7F)) {
      return true;
    }
    return false;
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final rules = FilesystemRules.of(fsType);
    final text = newValue.text;

    var blockedBeforeSelection = 0;
    final buffer = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      final codeUnit = text.codeUnitAt(i);
      if (_isBlocked(codeUnit, rules)) {
        if (i < newValue.selection.end) blockedBeforeSelection++;
        continue;
      }
      buffer.writeCharCode(codeUnit);
    }

    final filtered = buffer.toString();
    if (filtered == text) return newValue;

    final newOffset = (newValue.selection.end - blockedBeforeSelection)
        .clamp(0, filtered.length);
    return TextEditingValue(
      text: filtered,
      selection: TextSelection.collapsed(offset: newOffset),
    );
  }
}
