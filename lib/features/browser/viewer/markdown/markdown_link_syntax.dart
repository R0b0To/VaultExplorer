import 'dart:convert';

import 'markdown_entities.dart';

// CommonMark 0.31.2 inline links and images (spec section 6.3).
//
// One module owns every rule about link destinations so that the editor
// (which WRITES `![alt](path)`) and the viewer (which READS it) can never
// disagree again:
//
//   * a bare destination may not contain spaces, ASCII control characters or
//     unbalanced parentheses; anything else must be percent-encoded or wrapped
//     in `<...>`,
//   * `\` before ASCII punctuation is an escape,
//   * an optional title may follow the destination.
//
// Percent-encoding is what gets WRITTEN (it is the most portable form, and is
// what Obsidian / GitHub / Pandoc emit); both forms are READ.

/// The app used to write `![a](my file.png)`, which is not a link in
/// CommonMark (spec example 488). Notes created that way still render while
/// this is true. Set it to false to become strictly spec-conformant on input.
const bool kAcceptLegacySpacedDestinations = true;

/// ASCII punctuation per the spec: ``!"#$%&'()*+,-./:;<=>?@[\]^_`{|}~``.
bool isAsciiPunctuation(int c) =>
    (c >= 0x21 && c <= 0x2F) ||
    (c >= 0x3A && c <= 0x40) ||
    (c >= 0x5B && c <= 0x60) ||
    (c >= 0x7B && c <= 0x7E);

/// Parses what follows the `(` of an inline link: `destination "title" )`.
///
/// [from] is the index just after the `(`. Returns the destination (enclosing
/// `<>` removed, backslash escapes resolved, NOT percent-decoded) and the index
/// just past the closing `)`, or null when it is not a valid inline link tail.
({String destination, int end})? matchInlineLinkTail(String text, int from) {
  final strict = _parseDestinationAndTitle(text, from);
  if (strict != null) return strict;
  if (kAcceptLegacySpacedDestinations) {
    return _parseLegacySpacedDestination(text, from);
  }
  return null;
}

/// Parses one link destination at [i] (`<...>` or bare). Returns the value
/// with escapes resolved and the index just past it, or null.
({String value, int end})? parseLinkDestinationAt(String text, int i) =>
    _parseDestination(text, i);

/// Returns the index just past a link title starting at [i], or null.
int? skipLinkTitleAt(String text, int i) => _skipTitle(text, i);

/// Spaces / tabs and at most one line ending, starting at [i].
int skipLinkWhitespaceAt(String text, int i) => _skipLinkWhitespace(text, i);

/// Spaces, tabs and at most one line ending (spec: "optional spaces or tabs
/// (including up to one line ending)").
int _skipLinkWhitespace(String text, int i) {
  var sawNewline = false;
  while (i < text.length) {
    final c = text.codeUnitAt(i);
    if (c == 0x20 || c == 0x09) {
      i++;
    } else if (c == 0x0A && !sawNewline) {
      sawNewline = true;
      i++;
    } else {
      break;
    }
  }
  return i;
}

({String destination, int end})? _parseDestinationAndTitle(
  String text,
  int from,
) {
  final destStart = _skipLinkWhitespace(text, from);
  final dest = _parseDestination(text, destStart);
  if (dest == null) return null;

  var k = _skipLinkWhitespace(text, dest.end);
  final separated = k > dest.end;
  if (k < text.length && text[k] == ')') {
    return (destination: dest.value, end: k + 1);
  }

  // Anything but ')' must be a title, and a title needs whitespace before it.
  if (!separated) return null;
  final titleEnd = _skipTitle(text, k);
  if (titleEnd == null) return null;
  k = _skipLinkWhitespace(text, titleEnd);
  if (k < text.length && text[k] == ')') {
    return (destination: dest.value, end: k + 1);
  }
  return null;
}

({String value, int end})? _parseDestination(String text, int i) {
  if (i >= text.length) return null;

  if (text[i] == '<') {
    var j = i + 1;
    while (j < text.length) {
      final ch = text[j];
      if (ch == '\n' || ch == '\r' || ch == '<') return null;
      if (ch == '>') {
        return (value: resolveEscapesAndEntities(text.substring(i + 1, j)), end: j + 1);
      }
      if (ch == '\\' &&
          j + 1 < text.length &&
          isAsciiPunctuation(text.codeUnitAt(j + 1))) {
        j += 2;
        continue;
      }
      j++;
    }
    return null;
  }

  var depth = 0;
  var j = i;
  while (j < text.length) {
    final c = text.codeUnitAt(j);
    if (c <= 0x20 || c == 0x7F) break;
    if (c == 0x5C &&
        j + 1 < text.length &&
        isAsciiPunctuation(text.codeUnitAt(j + 1))) {
      j += 2;
      continue;
    }
    if (c == 0x28) {
      depth++;
    } else if (c == 0x29) {
      if (depth == 0) break;
      depth--;
    }
    j++;
  }
  if (depth != 0) return null;
  return (value: resolveEscapesAndEntities(text.substring(i, j)), end: j);
}

/// Returns the index just past a title starting at [i], or null.
int? _skipTitle(String text, int i) {
  if (i >= text.length) return null;
  final open = text[i];
  final String close;
  if (open == '"') {
    close = '"';
  } else if (open == "'") {
    close = "'";
  } else if (open == '(') {
    close = ')';
  } else {
    return null;
  }

  var j = i + 1;
  while (j < text.length) {
    final ch = text[j];
    if (ch == '\\' &&
        j + 1 < text.length &&
        isAsciiPunctuation(text.codeUnitAt(j + 1))) {
      j += 2;
      continue;
    }
    if (ch == close) return j + 1;
    if (open == '(' && ch == '(') return null;
    if (ch == '\n') {
      // A title may span lines but may not contain a blank line.
      var k = j + 1;
      while (k < text.length && (text[k] == ' ' || text[k] == '\t')) {
        k++;
      }
      if (k < text.length && text[k] == '\n') return null;
    }
    j++;
  }
  return null;
}

/// Pre-spec behaviour: everything up to the matching ')' is the destination,
/// spaces included. Only used when the strict parse failed AND the content
/// really contains a space, so it never loosens any other spec rule.
({String destination, int end})? _parseLegacySpacedDestination(
  String text,
  int from,
) {
  var j = from;
  var parenDepth = 1;
  while (j < text.length) {
    if (text[j] == '(') {
      parenDepth++;
    } else if (text[j] == ')') {
      parenDepth--;
      if (parenDepth == 0) break;
    }
    j++;
  }
  if (parenDepth != 0) return null;

  final raw = text.substring(from, j).trim();
  if (raw.isEmpty || raw.startsWith('<')) return null;
  if (raw.contains('\n') || raw.contains('\r')) return null;
  if (!raw.contains(' ') && !raw.contains('\t')) return null;
  return (destination: raw, end: j + 1);
}

/// Resolves backslash escapes (`\[` -> `[`), for image alt text.
String unescapeMarkdown(String text) {
  if (!text.contains('\\')) return text;
  final out = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    if (text[i] == '\\' &&
        i + 1 < text.length &&
        isAsciiPunctuation(text.codeUnitAt(i + 1))) {
      out.write(text[i + 1]);
      i++;
    } else {
      out.write(text[i]);
    }
  }
  return out.toString();
}

final RegExp _percentRun = RegExp(r'(?:%[0-9A-Fa-f]{2})+');

/// Percent-decodes a destination into a vault path (`my%20image.png` ->
/// `my image.png`). Lenient: a `%` that is not part of a valid UTF-8 escape
/// sequence stays as written, so a literal `100%.png` still resolves.
String decodeLinkPath(String destination) {
  if (!destination.contains('%')) return destination;
  return destination.replaceAllMapped(_percentRun, (m) {
    try {
      return Uri.decodeComponent(m[0]!);
    } on FormatException {
      return m[0]!;
    }
  });
}

const String _uriSafeChars =
    'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
    "-._~:/?#@!\$&'()*+,;=";

final Set<int> _uriSafeBytes = _uriSafeChars.codeUnits.toSet();

bool _isHexByte(int c) =>
    (c >= 0x30 && c <= 0x39) ||
    (c >= 0x41 && c <= 0x46) ||
    (c >= 0x61 && c <= 0x66);

/// Makes a destination safe to hand to a URL launcher: percent-encodes
/// anything that is not valid in a URI (spaces from `<...>` destinations,
/// non-ASCII, ...) without double-encoding existing `%XX` sequences. This is
/// the `href` normalisation CommonMark renderers apply (spec example 489).
String normalizeLinkUri(String destination) {
  final bytes = utf8.encode(destination);
  final out = StringBuffer();
  for (var i = 0; i < bytes.length; i++) {
    final b = bytes[i];
    final validEscape =
        b == 0x25 &&
        i + 2 < bytes.length &&
        _isHexByte(bytes[i + 1]) &&
        _isHexByte(bytes[i + 2]);
    if (validEscape || _uriSafeBytes.contains(b)) {
      out.writeCharCode(b);
    } else {
      out
        ..write('%')
        ..write(b.toRadixString(16).toUpperCase().padLeft(2, '0'));
    }
  }
  return out.toString();
}

// ---------------------------------------------------------------------------
// Writing
// ---------------------------------------------------------------------------

/// Turns a vault-relative path into a spec-conformant link destination.
///
/// Only what the spec forbids (or what would change the meaning) is encoded:
/// spaces and control characters, `<` `>` `(` `)` `\`, and `%` / `#` / `?`
/// so that [decodeLinkPath] round-trips the original file name exactly.
/// Everything else, including non-ASCII, is left readable.
String encodeMarkdownDestination(String path) {
  const needsEncoding = {
    0x25, // %
    0x23, // #
    0x3F, // ?
    0x3C, // <
    0x3E, // >
    0x28, // (
    0x29, // )
    0x5C, // \
  };
  final out = StringBuffer();
  for (final rune in path.runes) {
    if (rune <= 0x20 || rune == 0x7F || needsEncoding.contains(rune)) {
      out
        ..write('%')
        ..write(rune.toRadixString(16).toUpperCase().padLeft(2, '0'));
    } else {
      out.writeCharCode(rune);
    }
  }
  return out.toString();
}

bool _isWordCodeUnit(int c) =>
    (c >= 0x30 && c <= 0x39) ||
    (c >= 0x41 && c <= 0x5A) ||
    (c >= 0x61 && c <= 0x7A) ||
    c >= 0x80;

/// Escapes text for use inside `[...]`. Intraword `_` (as in `IMG_2024`) is
/// left alone: it can never open emphasis, so escaping it only hurts the
/// readability of the source.
String escapeMarkdownLinkText(String text) {
  final out = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    switch (ch) {
      case r'\':
      case '[':
      case ']':
      case '`':
      case '*':
      case '<':
      case '&':
      case '~':
        out
          ..write(r'\')
          ..write(ch);
      case '_':
        final intraword =
            i > 0 &&
            i + 1 < text.length &&
            _isWordCodeUnit(text.codeUnitAt(i - 1)) &&
            _isWordCodeUnit(text.codeUnitAt(i + 1));
        if (!intraword) out.write(r'\');
        out.write(ch);
      default:
        out.write(ch);
    }
  }
  return out.toString();
}

/// The Markdown the editors insert for an attached image / file:
/// `![alt](relative/path%20with%20spaces.png)`.
String markdownImageTemplate({required String alt, required String path}) =>
    '![${escapeMarkdownLinkText(alt)}](${encodeMarkdownDestination(path)})';
