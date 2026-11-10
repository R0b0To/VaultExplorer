import 'markdown_ast.dart';
import 'markdown_case_fold.dart';
import 'markdown_entities.dart';
import 'markdown_link_syntax.dart';

// CommonMark 0.31.2 inline parsing (spec chapter 6), in the shape of the
// reference implementation: a left-to-right scan that builds a node list,
// a delimiter stack for emphasis, and a bracket stack for links and images.
//
// App extensions layered on top: ==highlight==, ~~strikethrough~~, the
// <b>/<i>/<u>/<s>/<mark>/<sub>/<sup>/<code>/<a> tags, <br>, hidden HTML
// comments and bare http(s) URLs.

/// The target of a link reference definition.
typedef MdLinkReference = ({String destination, String? title});

/// Link reference definitions by normalised label.
typedef MdReferenceMap = Map<String, MdLinkReference>;

List<MdInline> parseInline(
  String text, {
  MdReferenceMap? references,
  MdParseOptions options = MdParseOptions.app,
}) {
  final nodes = _InlineParser(text, references ?? const <String, MdLinkReference>{}, options).parse();
  return options.bareUrls ? _autoLinkify(nodes) : nodes;
}

/// Case-folds and collapses whitespace in a `[label]` (brackets included).
String normalizeReferenceLabel(String bracketed) {
  return caseFoldForMatching(
    bracketed.substring(1, bracketed.length - 1).trim().replaceAll(RegExp(r'[ \t\r\n]+'), ' '),
  );
}

/// Length of a link label `[...]` starting at [pos], or 0 when there is none.
int _scanLinkLabel(String s, int pos) {
  if (pos >= s.length || s.codeUnitAt(pos) != 0x5B) return 0;
  var i = pos + 1;
  var count = 0;
  while (i < s.length) {
    final c = s.codeUnitAt(i);
    if (c == 0x5C) {
      if (i + 1 >= s.length) return 0;
      i += 2;
    } else if (c == 0x5B) {
      return 0;
    } else if (c == 0x5D) {
      return i + 1 - pos;
    } else {
      i++;
    }
    if (++count > 1000) return 0;
  }
  return 0;
}

int? _endOfLine(String s, int pos) {
  var i = pos;
  while (i < s.length && (s.codeUnitAt(i) == 0x20 || s.codeUnitAt(i) == 0x09)) {
    i++;
  }
  if (i >= s.length) return i;
  if (s.codeUnitAt(i) == 0x0A) return i + 1;
  return null;
}

/// Parses one link reference definition at the start of [s] (spec 4.7) and
/// records it in [refs]. Returns the number of characters consumed, or 0.
int parseLinkReferenceDefinition(String s, MdReferenceMap refs) {
  final labelLen = _scanLinkLabel(s, 0);
  if (labelLen == 0) return 0;
  final rawLabel = s.substring(0, labelLen);
  var pos = labelLen;
  if (pos >= s.length || s.codeUnitAt(pos) != 0x3A) return 0;
  pos++;
  pos = skipLinkWhitespaceAt(s, pos);
  final dest = parseLinkDestinationAt(s, pos);
  if (dest == null || dest.end == pos) return 0;

  pos = dest.end;
  final beforeTitle = pos;
  pos = skipLinkWhitespaceAt(s, pos);
  String? title;
  if (pos != beforeTitle) {
    final parsed = parseLinkTitleAt(s, pos);
    if (parsed != null) {
      title = parsed.value;
      pos = parsed.end;
    }
  }
  if (title == null) pos = beforeTitle;

  var end = _endOfLine(s, pos);
  if (end == null) {
    if (title == null) return 0;
    // The title is not alone on its line: drop it and retry with just the URL.
    title = null;
    end = _endOfLine(s, beforeTitle);
    if (end == null) return 0;
  }

  final label = normalizeReferenceLabel(rawLabel);
  if (label.isEmpty) return 0;
  final reference = (destination: dest.value, title: title);
  refs.putIfAbsent(label, () => reference);
  return end;
}

// ── Node list ────────────────────────────────────────────────────────────

enum _K { root, text, softbreak, hardbreak, code, emph, strong, strike, mark, link, image, ready, html }

class _N {
  final _K kind;
  String text;
  String dest = '';
  String? title;
  MdInline? ready;
  _N? parent, prev, next, first, last;
  _N(this.kind, [this.text = '']);

  void append(_N child) {
    child.unlink();
    child.parent = this;
    final tail = last;
    if (tail != null) {
      tail.next = child;
      child.prev = tail;
    } else {
      first = child;
    }
    last = child;
  }

  void unlink() {
    final p = parent;
    if (prev != null) {
      prev!.next = next;
    } else if (p != null) {
      p.first = next;
    }
    if (next != null) {
      next!.prev = prev;
    } else if (p != null) {
      p.last = prev;
    }
    parent = null;
    next = null;
    prev = null;
  }

  void insertAfter(_N sibling) {
    sibling.unlink();
    sibling.next = next;
    if (sibling.next != null) sibling.next!.prev = sibling;
    sibling.prev = this;
    next = sibling;
    sibling.parent = parent;
    if (sibling.next == null) parent?.last = sibling;
  }
}

class _Delim {
  final int cc;
  int numdelims;
  final int origdelims;
  final _N node;
  _Delim? previous, next;
  final bool canOpen, canClose;
  _Delim(this.cc, this.numdelims, this.node, this.canOpen, this.canClose, this.previous)
    : origdelims = numdelims;
}

class _Bracket {
  final _N node;
  final _Bracket? previous;
  final _Delim? previousDelimiter;
  final int index;
  final bool image;
  bool active = true;
  bool bracketAfter = false;
  _Bracket(this.node, this.previous, this.previousDelimiter, this.index, this.image);
}

final RegExp _reUnicodeWhitespace = RegExp(r'[\p{Zs}\t\r\n\f]', unicode: true);
final RegExp _rePunctuation = RegExp(r'[\p{P}\p{S}]', unicode: true);
final RegExp _reEmailAutolink = RegExp(
  r"""<([a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*)>""",
);
final RegExp _reUriAutolink = RegExp(r'<([A-Za-z][A-Za-z0-9.+-]{1,31}:[^<>\x00-\x20]*)>');
const String mdHtmlTagName = '[A-Za-z][A-Za-z0-9-]*';
const String _htmlAttrName = '[a-zA-Z_:][a-zA-Z0-9:._-]*';
const String _htmlAttrValue = '(?:[^"\'=<>`\\x00-\\x20]+|\'[^\']*\'|"[^"]*")';
const String _htmlAttribute = '(?:\\s+$_htmlAttrName(?:\\s*=\\s*$_htmlAttrValue)?)';

/// Spec "open tag" / "closing tag" (6.6), as regex source for reuse.
const String mdHtmlOpenTag = '<$mdHtmlTagName$_htmlAttribute*\\s*/?>';
const String mdHtmlCloseTag = '</$mdHtmlTagName\\s*>';

const String _htmlOtherTokens =
    '$mdHtmlOpenTag|$mdHtmlCloseTag|<\\?[\\s\\S]*?\\?>|<![A-Za-z]+\\s+[^>]*>|<!\\[CDATA\\[[\\s\\S]*?\\]\\]>';
final RegExp _reRawHtml = RegExp(_htmlOtherTokens);
final RegExp _reRawHtmlOrComment = RegExp('<!--(?:>|->|[\\s\\S]*?-->)|$_htmlOtherTokens');
final RegExp _reBr = RegExp(r'<br\s*/?>', caseSensitive: false);
final RegExp _reHtmlComment = RegExp(r'<!--(?:>|->|[\s\S]*?-->)');
final RegExp _reOpenTag = RegExp(r'<([a-zA-Z]+)(?:\s+([^>]*))?>', caseSensitive: false);

const Set<String> _formattingTags = {
  'b', 'strong', 'i', 'em', 'u', 'ins', 's', 'del', 'strike',
  'mark', 'sub', 'sup', 'code', 'a',
};

bool _isSpecialInline(int c) =>
    c == 0x0A || c == 0x5C || c == 0x60 || c == 0x2A || c == 0x5F ||
    c == 0x5B || c == 0x5D || c == 0x21 || c == 0x3C || c == 0x26 ||
    c == 0x7E || c == 0x3D;

class _InlineParser {
  _InlineParser(this.s, this.refs, this.options);

  final String s;
  final MdReferenceMap refs;
  final MdParseOptions options;
  int pos = 0;
  _Delim? delimiters;
  _Bracket? brackets;
  final _N root = _N(_K.root);

  List<MdInline> parse() {
    while (pos < s.length) {
      if (!_parseInline()) {
        root.append(_N(_K.text, s[pos]));
        pos++;
      }
    }
    _processEmphasis(null);
    return _convert(root);
  }

  bool _parseInline() {
    switch (s.codeUnitAt(pos)) {
      case 0x0A:
        return _newline();
      case 0x5C:
        return _backslash();
      case 0x60:
        return _backticks();
      case 0x2A:
      case 0x5F:
      case 0x7E:
      case 0x3D:
        return _handleDelim(s.codeUnitAt(pos));
      case 0x5B:
        return _openBracket();
      case 0x21:
        return _bang();
      case 0x5D:
        return _closeBracket();
      case 0x3C:
        return _autolink() || _htmlLike();
      case 0x26:
        return _entity();
      default:
        return _string();
    }
  }

  bool _string() {
    final start = pos;
    while (pos < s.length && !_isSpecialInline(s.codeUnitAt(pos))) {
      pos++;
    }
    if (pos == start) return false;
    root.append(_N(_K.text, s.substring(start, pos)));
    return true;
  }

  bool _newline() {
    pos++;
    final last = root.last;
    if (last != null && last.kind == _K.text && last.text.endsWith(' ')) {
      final hard = last.text.length >= 2 && last.text[last.text.length - 2] == ' ';
      last.text = last.text.replaceFirst(RegExp(r' +$'), '');
      root.append(_N(hard ? _K.hardbreak : _K.softbreak));
    } else {
      root.append(_N(_K.softbreak));
    }
    while (pos < s.length && s.codeUnitAt(pos) == 0x20) {
      pos++;
    }
    return true;
  }

  bool _backslash() {
    pos++;
    if (pos < s.length && s.codeUnitAt(pos) == 0x0A) {
      pos++;
      root.append(_N(_K.hardbreak));
    } else if (pos < s.length && isAsciiPunctuation(s.codeUnitAt(pos))) {
      root.append(_N(_K.text, s[pos]));
      pos++;
    } else {
      root.append(_N(_K.text, r'\'));
    }
    return true;
  }

  bool _backticks() {
    var i = pos;
    while (i < s.length && s.codeUnitAt(i) == 0x60) {
      i++;
    }
    final ticks = i - pos;
    final afterOpen = i;
    var search = afterOpen;
    while (true) {
      final idx = s.indexOf('`', search);
      if (idx < 0) break;
      var j = idx;
      while (j < s.length && s.codeUnitAt(j) == 0x60) {
        j++;
      }
      if (j - idx == ticks) {
        var contents = s.substring(afterOpen, idx).replaceAll('\n', ' ');
        if (contents.length >= 2 &&
            contents.startsWith(' ') &&
            contents.endsWith(' ') &&
            RegExp(r'[^ ]').hasMatch(contents)) {
          contents = contents.substring(1, contents.length - 1);
        }
        root.append(_N(_K.code, contents));
        pos = j;
        return true;
      }
      search = j;
    }
    pos = afterOpen;
    root.append(_N(_K.text, '`' * ticks));
    return true;
  }

  String _charBefore(int i) {
    final c = s.codeUnitAt(i - 1);
    if (c >= 0xDC00 && c <= 0xDFFF && i >= 2) {
      final h = s.codeUnitAt(i - 2);
      if (h >= 0xD800 && h <= 0xDBFF) return s.substring(i - 2, i);
    }
    return s[i - 1];
  }

  String _charAt(int i) {
    final c = s.codeUnitAt(i);
    if (c >= 0xD800 && c <= 0xDBFF && i + 1 < s.length) return s.substring(i, i + 2);
    return s[i];
  }

  bool _handleDelim(int cc) {
    final start = pos;
    var n = 0;
    while (pos < s.length && s.codeUnitAt(pos) == cc) {
      n++;
      pos++;
    }
    final run = s.substring(start, pos);

    // ~~ and == are only ever a run of exactly two.
    if ((cc == 0x7E || cc == 0x3D) && n != 2) {
      root.append(_N(_K.text, run));
      return true;
    }

    final before = start == 0 ? '\n' : _charBefore(start);
    final after = pos >= s.length ? '\n' : _charAt(pos);
    final afterWs = _reUnicodeWhitespace.hasMatch(after);
    final afterPunct = _rePunctuation.hasMatch(after);
    final beforeWs = _reUnicodeWhitespace.hasMatch(before);
    final beforePunct = _rePunctuation.hasMatch(before);

    final leftFlanking = !afterWs && (!afterPunct || beforeWs || beforePunct);
    final rightFlanking = !beforeWs && (!beforePunct || afterWs || afterPunct);

    final bool canOpen;
    final bool canClose;
    if (cc == 0x5F) {
      canOpen = leftFlanking && (!rightFlanking || beforePunct);
      canClose = rightFlanking && (!leftFlanking || afterPunct);
    } else {
      canOpen = leftFlanking;
      canClose = rightFlanking;
    }

    final node = _N(_K.text, run);
    root.append(node);
    if (canOpen || canClose) {
      final d = _Delim(cc, n, node, canOpen, canClose, delimiters);
      delimiters?.next = d;
      delimiters = d;
    }
    return true;
  }

  void _removeDelimiter(_Delim d) {
    d.previous?.next = d.next;
    if (d.next == null) {
      delimiters = d.previous;
    } else {
      d.next!.previous = d.previous;
    }
  }

  void _processEmphasis(_Delim? stackBottom) {
    final openersBottom = List<_Delim?>.filled(16, stackBottom);
    _Delim? closer = delimiters;
    while (closer != null && closer.previous != stackBottom) {
      closer = closer.previous;
    }
    while (closer != null) {
      final cc = closer.cc;
      if (!closer.canClose) {
        closer = closer.next;
        continue;
      }
      var opener = closer.previous;
      var found = false;
      final idx = cc == 0x5F
          ? 2 + (closer.canOpen ? 3 : 0) + (closer.origdelims % 3)
          : cc == 0x2A
          ? 8 + (closer.canOpen ? 3 : 0) + (closer.origdelims % 3)
          : cc == 0x7E
          ? 14
          : 15;
      while (opener != null && opener != stackBottom && opener != openersBottom[idx]) {
        final oddMatch =
            (closer.canOpen || opener.canClose) &&
            closer.origdelims % 3 != 0 &&
            (opener.origdelims + closer.origdelims) % 3 == 0;
        if (opener.cc == cc && opener.canOpen && !oddMatch) {
          final pairable = (cc != 0x7E && cc != 0x3D) ||
              (opener.numdelims >= 2 && closer.numdelims >= 2);
          if (pairable) {
            found = true;
            break;
          }
        }
        opener = opener.previous;
      }
      final oldCloser = closer;
      if (!found) {
        closer = closer.next;
      } else {
        final use = (closer.numdelims >= 2 && opener!.numdelims >= 2) ? 2 : 1;
        final openerNode = opener!.node;
        final closerNode = closer.node;
        opener.numdelims -= use;
        closer.numdelims -= use;
        openerNode.text = openerNode.text.substring(0, openerNode.text.length - use);
        closerNode.text = closerNode.text.substring(0, closerNode.text.length - use);
        final wrap = _N(
          cc == 0x7E
              ? _K.strike
              : cc == 0x3D
              ? _K.mark
              : (use == 1 ? _K.emph : _K.strong),
        );
        var tmp = openerNode.next;
        while (tmp != null && tmp != closerNode) {
          final nx = tmp.next;
          tmp.unlink();
          wrap.append(tmp);
          tmp = nx;
        }
        openerNode.insertAfter(wrap);
        if (opener.next != closer) {
          opener.next = closer;
          closer.previous = opener;
        }
        if (opener.numdelims == 0) {
          openerNode.unlink();
          _removeDelimiter(opener);
        }
        if (closer.numdelims == 0) {
          closerNode.unlink();
          final after = closer.next;
          _removeDelimiter(closer);
          closer = after;
        }
      }
      if (!found) {
        openersBottom[idx] = oldCloser.previous;
        if (!oldCloser.canOpen) _removeDelimiter(oldCloser);
      }
    }
    while (delimiters != null && delimiters != stackBottom) {
      _removeDelimiter(delimiters!);
    }
  }

  // ── Links and images ───────────────────────────────────────────────────

  void _addBracket(_N node, int index, bool image) {
    brackets?.bracketAfter = true;
    brackets = _Bracket(node, brackets, delimiters, index, image);
  }

  bool _openBracket() {
    final start = pos;
    pos++;
    final node = _N(_K.text, '[');
    root.append(node);
    _addBracket(node, start, false);
    return true;
  }

  bool _bang() {
    final start = pos;
    pos++;
    if (pos < s.length && s.codeUnitAt(pos) == 0x5B) {
      pos++;
      final node = _N(_K.text, '![');
      root.append(node);
      _addBracket(node, start + 1, true);
    } else {
      root.append(_N(_K.text, '!'));
    }
    return true;
  }

  bool _closeBracket() {
    pos++;
    final startpos = pos;
    final opener = brackets;
    if (opener == null) {
      root.append(_N(_K.text, ']'));
      return true;
    }
    if (!opener.active) {
      root.append(_N(_K.text, ']'));
      brackets = opener.previous;
      return true;
    }

    final isImage = opener.image;
    String? dest;
    String? title;
    var matched = false;

    if (pos < s.length && s.codeUnitAt(pos) == 0x28) {
      final tail = matchInlineLinkTail(
        s,
        pos + 1,
        legacySpaces: isImage && options.spacedImageDestinations,
      );
      if (tail != null) {
        dest = tail.destination;
        title = tail.title;
        pos = tail.end;
        matched = true;
      }
    }

    if (!matched) {
      final beforeLabel = pos;
      final n = _scanLinkLabel(s, pos);
      String? refLabel;
      if (n > 2) {
        refLabel = s.substring(beforeLabel, beforeLabel + n);
        pos = beforeLabel + n;
      } else if (n == 2) {
        pos = beforeLabel + n;
        if (!opener.bracketAfter) refLabel = s.substring(opener.index, startpos);
      } else if (!opener.bracketAfter) {
        refLabel = s.substring(opener.index, startpos);
      }
      if (refLabel != null) {
        final key = normalizeReferenceLabel(refLabel);
        final target = key.isEmpty ? null : refs[key];
        if (target != null) {
          dest = target.destination;
          title = target.title;
          matched = true;
        }
      }
    }

    if (!matched) {
      brackets = opener.previous;
      pos = startpos;
      root.append(_N(_K.text, ']'));
      return true;
    }

    final node = _N(isImage ? _K.image : _K.link)
      ..dest = dest ?? ''
      ..title = title;
    var tmp = opener.node.next;
    while (tmp != null) {
      final nx = tmp.next;
      tmp.unlink();
      node.append(tmp);
      tmp = nx;
    }
    root.append(node);
    _processEmphasis(opener.previousDelimiter);
    brackets = opener.previous;
    opener.node.unlink();

    // Links may not contain links: deactivate earlier link openers.
    if (!isImage) {
      var o = brackets;
      while (o != null) {
        if (!o.image) o.active = false;
        o = o.previous;
      }
    }
    return true;
  }

  // ── Autolinks, HTML, entities ──────────────────────────────────────────

  bool _autolink() {
    final email = _reEmailAutolink.matchAsPrefix(s, pos);
    if (email != null) {
      final addr = email.group(1)!;
      final link = _N(_K.link)..dest = 'mailto:$addr';
      link.append(_N(_K.text, addr));
      root.append(link);
      pos = email.end;
      return true;
    }
    final uri = _reUriAutolink.matchAsPrefix(s, pos);
    if (uri != null) {
      final target = uri.group(1)!;
      final link = _N(_K.link)..dest = target;
      link.append(_N(_K.text, target));
      root.append(link);
      pos = uri.end;
      return true;
    }
    return false;
  }

  bool _htmlLike() {
    if (!options.interpretHtml) {
      // CommonMark profile: every HTML construct is an opaque raw token.
      final raw = _reRawHtmlOrComment.matchAsPrefix(s, pos);
      if (raw == null) return false;
      root.append(_N(_K.html, raw.group(0)!));
      pos = raw.end;
      return true;
    }

    final br = _reBr.matchAsPrefix(s, pos);
    if (br != null) {
      root.append(_N(_K.hardbreak));
      pos = br.end;
      return true;
    }

    final open = _reOpenTag.matchAsPrefix(s, pos);
    if (open != null) {
      final tag = open.group(1)!.toLowerCase();
      if (_formattingTags.contains(tag)) {
        final closeRe = RegExp('</$tag>', caseSensitive: false);
        final close = closeRe.allMatches(s, open.end).firstOrNull;
        if (close != null) {
          final inner = s.substring(open.end, close.start);
          final node = _formattingNode(tag, open.group(2) ?? '', inner);
          root.append(_N(_K.ready)..ready = node);
          pos = close.end;
          return true;
        }
      }
    }

    final comment = _reHtmlComment.matchAsPrefix(s, pos);
    if (comment != null) {
      pos = comment.end;
      return true;
    }

    // Any other tag is an opaque token: shown as written, and never parsed as
    // Markdown (so `<img src="my_img_v2.png">` keeps its underscores).
    final raw = _reRawHtml.matchAsPrefix(s, pos);
    if (raw != null) {
      root.append(_N(_K.text, raw.group(0)!));
      pos = raw.end;
      return true;
    }
    return false;
  }

  MdInline _formattingNode(String tag, String attrs, String inner) {
    if (tag == 'code') return MdInlineCode(inner);
    final children = _InlineParser(inner, refs, options).parse();
    switch (tag) {
      case 'a':
        final href = RegExp(r'''href=["']([^"']*)["']''', caseSensitive: false)
            .firstMatch(attrs)
            ?.group(1);
        return MdLink(children, href ?? '');
      case 'b':
      case 'strong':
        return MdBold(children);
      case 'i':
      case 'em':
        return MdItalic(children);
      case 'u':
      case 'ins':
        return MdUnderline(children);
      case 's':
      case 'del':
      case 'strike':
        return MdStrikethrough(children);
      case 'mark':
        return MdHighlight(children);
      case 'sub':
        return MdSubscript(children);
      default:
        return MdSuperscript(children);
    }
  }

  bool _entity() {
    final m = markdownEntityPattern.matchAsPrefix(s, pos);
    if (m == null) return false;
    final decoded = decodeEntityReference(m.group(0)!);
    if (decoded == null) return false;
    root.append(_N(_K.text, decoded));
    pos = m.end;
    return true;
  }

  // ── Node list -> app AST ───────────────────────────────────────────────

  List<MdInline> _convert(_N parent) {
    final out = <MdInline>[];
    final text = StringBuffer();
    void flush() {
      if (text.isNotEmpty) {
        out.add(MdText(text.toString()));
        text.clear();
      }
    }

    for (var n = parent.first; n != null; n = n.next) {
      switch (n.kind) {
        case _K.root:
          break;
        case _K.text:
          text.write(n.text);
        case _K.softbreak:
          text.write(options.softBreaksAsNewlines ? '\n' : ' ');
        case _K.hardbreak:
          flush();
          out.add(const MdLineBreak());
        case _K.code:
          flush();
          out.add(MdInlineCode(n.text));
        case _K.emph:
          flush();
          out.add(MdItalic(_convert(n)));
        case _K.strong:
          flush();
          out.add(MdBold(_convert(n)));
        case _K.strike:
          flush();
          out.add(MdStrikethrough(_convert(n)));
        case _K.mark:
          flush();
          out.add(MdHighlight(_convert(n)));
        case _K.link:
          flush();
          out.add(MdLink(_convert(n), n.dest, title: n.title));
        case _K.image:
          flush();
          out.add(MdInlineImage(_plainText(n), n.dest, title: n.title));
        case _K.ready:
          flush();
          out.add(n.ready!);
        case _K.html:
          flush();
          out.add(MdHtmlInline(n.text));
      }
    }
    flush();
    return out;
  }

  String _plainText(_N parent) {
    final b = StringBuffer();
    for (var n = parent.first; n != null; n = n.next) {
      switch (n.kind) {
        case _K.text:
        case _K.code:
          b.write(n.text);
        case _K.softbreak:
        case _K.hardbreak:
          b.write(' ');
        case _K.ready:
        case _K.html:
        case _K.root:
          break;
        default:
          b.write(_plainText(n));
      }
    }
    return b.toString();
  }
}

// ── Bare URL linking (app extension) ─────────────────────────────────────

final RegExp _autoLinkPattern = RegExp(r'https?://[^\s<>()\[\]]+');

List<MdInline> _autoLinkify(List<MdInline> nodes) {
  final result = <MdInline>[];
  for (final node in nodes) {
    if (node is MdText) {
      result.addAll(_autoLinkifyText(node.text));
    } else if (node is MdBold) {
      result.add(MdBold(_autoLinkify(node.children)));
    } else if (node is MdItalic) {
      result.add(MdItalic(_autoLinkify(node.children)));
    } else if (node is MdUnderline) {
      result.add(MdUnderline(_autoLinkify(node.children)));
    } else if (node is MdHighlight) {
      result.add(MdHighlight(_autoLinkify(node.children)));
    } else if (node is MdStrikethrough) {
      result.add(MdStrikethrough(_autoLinkify(node.children)));
    } else {
      result.add(node);
    }
  }
  return result;
}

List<MdInline> _autoLinkifyText(String text) {
  final matches = _autoLinkPattern.allMatches(text).toList();
  if (matches.isEmpty) return [MdText(text)];

  final out = <MdInline>[];
  int last = 0;
  for (final m in matches) {
    if (m.start < last) continue;
    if (m.start > last) out.add(MdText(text.substring(last, m.start)));

    var url = m.group(0)!;
    var end = m.end;
    while (url.isNotEmpty && '.,;:!?\'"'.contains(url[url.length - 1])) {
      url = url.substring(0, url.length - 1);
      end -= 1;
    }
    out.add(MdLink([MdText(url)], url));
    last = end;
  }
  if (last < text.length) out.add(MdText(text.substring(last)));
  return out;
}
