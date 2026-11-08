import 'package:flutter/services.dart';

/// Caps a text field at [maxBytes] **UTF-8 bytes** (not characters).
///
/// VeraCrypt limits a volume password to 128 UTF-8 bytes
/// (`VolumePassword::MaxSize`) and rejects anything longer instead of cutting
/// it. Counting bytes matters: an emoji is 4 bytes, an accented letter 2, so a
/// plain character limit would still let an over-long password through. An edit
/// (or paste) that would overflow is truncated at a whole character.
class Utf8ByteLimitingFormatter extends TextInputFormatter {
  const Utf8ByteLimitingFormatter(this.maxBytes);

  final int maxBytes;

  static int _bytesOf(int rune) {
    if (rune < 0x80) return 1;
    if (rune < 0x800) return 2;
    if (rune < 0x10000) return 3;
    return 4;
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var bytes = 0;
    var keptUnits = 0;
    for (final rune in newValue.text.runes) {
      final next = _bytesOf(rune);
      if (bytes + next > maxBytes) break;
      bytes += next;
      keptUnits += rune > 0xFFFF ? 2 : 1;
    }
    if (keptUnits >= newValue.text.length) return newValue;
    return TextEditingValue(
      text: newValue.text.substring(0, keptUnits),
      selection: TextSelection.collapsed(offset: keptUnits),
    );
  }
}
