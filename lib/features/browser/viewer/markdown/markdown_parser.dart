import 'markdown_ast.dart';
import 'markdown_entities.dart';
import 'markdown_inline_parser.dart';

// CommonMark 0.31.2 block parsing (spec chapters 3-5), in the shape of the
// reference implementation: every input line is matched against the open
// containers (block quotes, list items), then tested for new block starts,
// and what remains is added to the innermost open leaf. Inlines are parsed
// afterwards, once every link reference definition is known.
//
// App extensions on top of the spec: GFM pipe tables, `> [!note]` callouts,
// `- [x]` task items, and a viewer-friendly treatment of raw HTML blocks
// (comments are hidden, `<hr>` is a rule, everything else renders as text).

List<MdBlock> parseMarkdownDocument(
  String source, {
  MdParseOptions options = MdParseOptions.app,
}) {
  final parser = _BlockParser();
  final doc = parser.parse(source);
  return _Converter(parser.refs, options).blocks(doc);
}

// ── Tree ─────────────────────────────────────────────────────────────────

class _ListData {
  final bool ordered;
  bool tight = true;
  final String bulletChar;
  final int start;
  final String delimiter;
  int padding = 0;
  final int markerOffset;
  _ListData(this.ordered, this.bulletChar, this.start, this.delimiter, this.markerOffset);
}

class _B {
  _B(this.type, this.startLine);

  final String type;
  int startLine;
  _B? parent, first, last, prev, next;
  bool open = true;
  bool lastLineBlank = false;
  bool lastLineChecked = false;

  final StringBuffer _sb = StringBuffer();
  String get content => _sb.toString();
  set content(String v) {
    _sb.clear();
    _sb.write(v);
  }

  void addContent(String v) => _sb.write(v);

  int level = 0;
  bool isFenced = false;
  String fenceChar = '';
  int fenceLength = 0;
  int fenceOffset = 0;
  String info = '';
  String literal = '';
  int htmlType = 0;
  _ListData? list;
  String tableHeader = '';
  List<MdTableAlign> aligns = const [];

  void append(_B child) {
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

  void insertAfter(_B sibling) {
    sibling.unlink();
    sibling.next = next;
    if (sibling.next != null) sibling.next!.prev = sibling;
    sibling.prev = this;
    next = sibling;
    sibling.parent = parent;
    if (sibling.next == null) parent?.last = sibling;
  }
}

// ── Patterns ─────────────────────────────────────────────────────────────

final RegExp _reMaybeSpecial = RegExp(r'^[#`~*+_=<>0-9:|-]');
final RegExp _reAtx = RegExp(r'^#{1,6}(?:[ \t]+|$)');
final RegExp _reCodeFence = RegExp(r'^`{3,}(?!.*`)|^~{3,}');
final RegExp _reClosingFence = RegExp(r'^(?:`{3,}|~{3,})(?=[ \t]*$)');
final RegExp _reThematic = RegExp(r'^(?:\*[ \t]*){3,}$|^(?:_[ \t]*){3,}$|^(?:-[ \t]*){3,}$');
final RegExp _reSetext = RegExp(r'^(?:=+|-+)[ \t]*$');
final RegExp _reOrdered = RegExp(r'^(\d{1,9})([.)])');
final RegExp _reNonSpace = RegExp(r'[^ \t\f\v\r\n]');

final List<RegExp> _htmlOpen = [
  RegExp('.'),
  RegExp(r'^<(?:script|pre|textarea|style)(?:\s|>|$)', caseSensitive: false),
  RegExp(r'^<!--'),
  RegExp(r'^<[?]'),
  RegExp(r'^<![A-Za-z]'),
  RegExp(r'^<!\[CDATA\['),
  RegExp(
    r'^<[/]?(?:address|article|aside|base|basefont|blockquote|body|caption|center|col|colgroup|dd|details|dialog|dir|div|dl|dt|fieldset|figcaption|figure|footer|form|frame|frameset|h[123456]|head|header|hr|html|iframe|legend|li|link|main|menu|menuitem|nav|noframes|ol|optgroup|option|p|param|search|section|summary|table|tbody|td|tfoot|th|thead|title|tr|track|ul)(?:\s|[/]?[>]|$)',
    caseSensitive: false,
  ),
  RegExp('^(?:$mdHtmlOpenTag|$mdHtmlCloseTag)\\s*\$', caseSensitive: false),
];

final List<RegExp> _htmlClose = [
  RegExp('.'),
  RegExp(r'</(?:script|pre|textarea|style)>', caseSensitive: false),
  RegExp(r'-->'),
  RegExp(r'\?>'),
  RegExp(r'>'),
  RegExp(r'\]\]>'),
];

int _peek(String s, int i) => i >= 0 && i < s.length ? s.codeUnitAt(i) : -1;
bool _isSpaceOrTab(int c) => c == 0x20 || c == 0x09;

// ── Block structure ──────────────────────────────────────────────────────

class _BlockParser {
  final MdReferenceMap refs = {};

  late _B doc;
  late _B tip;
  late _B oldtip;
  late _B lastMatched;

  String line = '';
  int lineNumber = 0;
  int offset = 0;
  int column = 0;
  int nextNonspace = 0;
  int nextNonspaceColumn = 0;
  int indent = 0;
  bool indented = false;
  bool blank = false;
  bool partiallyConsumedTab = false;
  bool allClosed = true;

  _B parse(String source) {
    final text = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    doc = _B('document', 0);
    tip = doc;
    oldtip = doc;
    lastMatched = doc;

    final lines = text.split('\n');
    var len = lines.length;
    if (text.endsWith('\n')) len -= 1;
    for (var i = 0; i < len; i++) {
      _incorporateLine(lines[i]);
    }
    _B? b = tip;
    while (b != null) {
      final above = b.parent;
      _finalize(b);
      b = above;
    }
    return doc;
  }

  bool _canContain(String container, String child) {
    switch (container) {
      case 'document':
      case 'block_quote':
      case 'item':
        return child != 'item';
      case 'list':
        return child == 'item';
      default:
        return false;
    }
  }

  bool _acceptsLines(String type) =>
      type == 'paragraph' || type == 'code_block' || type == 'html_block' || type == 'table';

  void _findNextNonspace() {
    var i = offset;
    var cols = column;
    while (i < line.length) {
      final c = line.codeUnitAt(i);
      if (c == 0x20) {
        i++;
        cols++;
      } else if (c == 0x09) {
        i++;
        cols += 4 - (cols % 4);
      } else {
        break;
      }
    }
    blank = i >= line.length || line.codeUnitAt(i) == 0x0A || line.codeUnitAt(i) == 0x0D;
    nextNonspace = i;
    nextNonspaceColumn = cols;
    indent = nextNonspaceColumn - column;
    indented = indent >= 4;
  }

  void _advanceNextNonspace() {
    offset = nextNonspace;
    column = nextNonspaceColumn;
    partiallyConsumedTab = false;
  }

  void _advanceOffset(int count, bool columns) {
    while (count > 0 && offset < line.length) {
      final c = line.codeUnitAt(offset);
      if (c == 0x09) {
        final charsToTab = 4 - (column % 4);
        if (columns) {
          partiallyConsumedTab = charsToTab > count;
          final advance = charsToTab > count ? count : charsToTab;
          column += advance;
          offset += partiallyConsumedTab ? 0 : 1;
          count -= advance;
        } else {
          partiallyConsumedTab = false;
          column += charsToTab;
          offset += 1;
          count -= 1;
        }
      } else {
        partiallyConsumedTab = false;
        offset += 1;
        column += 1;
        count -= 1;
      }
    }
  }

  void _addLine() {
    if (partiallyConsumedTab) {
      offset += 1;
      final charsToTab = 4 - (column % 4);
      tip.addContent(' ' * charsToTab);
    }
    tip.addContent('${offset >= line.length ? '' : line.substring(offset)}\n');
  }

  _B _addChild(String type) {
    while (!_canContain(tip.type, type)) {
      _finalize(tip);
    }
    final child = _B(type, lineNumber - 1);
    tip.append(child);
    tip = child;
    return child;
  }

  void _closeUnmatched() {
    if (!allClosed) {
      while (oldtip != lastMatched) {
        final parent = oldtip.parent!;
        _finalize(oldtip);
        oldtip = parent;
      }
      allClosed = true;
    }
  }

  // Strips link reference definitions from the front of [content]; returns the
  // remaining text and how many lines were consumed.
  (String, int) _stripReferenceDefinitions(String content) {
    var c = content;
    var lines = 0;
    while (c.startsWith('[')) {
      final n = parseLinkReferenceDefinition(c, refs);
      if (n == 0) break;
      lines += '\n'.allMatches(c.substring(0, n)).length;
      c = c.substring(n);
    }
    return (c, lines);
  }

  void _finalize(_B block) {
    final above = block.parent;
    block.open = false;
    switch (block.type) {
      case 'list':
        _finalizeList(block);
      case 'code_block':
        final content = block.content;
        if (block.isFenced) {
          final nl = content.indexOf('\n');
          final firstLine = nl < 0 ? content : content.substring(0, nl);
          block.info = resolveEscapesAndEntities(firstLine.trim());
          block.literal = nl < 0 ? '' : content.substring(nl + 1);
        } else {
          block.literal = content.replaceFirst(RegExp(r'(\n *)+$'), '\n');
        }
      case 'html_block':
        block.literal = block.content.replaceFirst(RegExp(r'(\n *)+$'), '');
      case 'paragraph':
        final (rest, consumed) = _stripReferenceDefinitions(block.content);
        if (consumed > 0 || rest != block.content) {
          block.content = rest;
          block.startLine += consumed;
          if (rest.trim().isEmpty) block.unlink();
        }
    }
    if (above != null) tip = above;
  }

  bool _endsWithBlankLine(_B? block) {
    while (block != null) {
      if (block.lastLineBlank) return true;
      if (!block.lastLineChecked && (block.type == 'list' || block.type == 'item')) {
        block.lastLineChecked = true;
        block = block.last;
      } else {
        block.lastLineChecked = true;
        break;
      }
    }
    return false;
  }

  void _finalizeList(_B block) {
    var item = block.first;
    while (item != null) {
      if (_endsWithBlankLine(item) && item.next != null) {
        block.list!.tight = false;
        break;
      }
      var sub = item.first;
      while (sub != null) {
        if (_endsWithBlankLine(sub) && (item.next != null || sub.next != null)) {
          block.list!.tight = false;
          break;
        }
        sub = sub.next;
      }
      item = item.next;
    }
  }

  // 0 = matched, 1 = not matched, 2 = line fully consumed.
  int _continue(_B c) {
    switch (c.type) {
      case 'document':
        return 0;
      case 'list':
        return 0;
      case 'block_quote':
        if (!indented && _peek(line, nextNonspace) == 0x3E) {
          _advanceNextNonspace();
          _advanceOffset(1, false);
          if (_isSpaceOrTab(_peek(line, offset))) _advanceOffset(1, true);
          return 0;
        }
        return 1;
      case 'item':
        if (blank) {
          if (c.first == null) return 1;
          _advanceNextNonspace();
        } else if (indent >= c.list!.markerOffset + c.list!.padding) {
          _advanceOffset(c.list!.markerOffset + c.list!.padding, true);
        } else {
          return 1;
        }
        return 0;
      case 'code_block':
        if (c.isFenced) {
          final close = indent <= 3 && nextNonspace < line.length && line[nextNonspace] == c.fenceChar
              ? _reClosingFence.firstMatch(line.substring(nextNonspace))
              : null;
          if (close != null && close.group(0)!.length >= c.fenceLength) {
            _finalize(c);
            return 2;
          }
          var i = c.fenceOffset;
          while (i > 0 && _isSpaceOrTab(_peek(line, offset))) {
            _advanceOffset(1, true);
            i--;
          }
        } else if (indent >= 4) {
          _advanceOffset(4, true);
        } else if (blank) {
          _advanceNextNonspace();
        } else {
          return 1;
        }
        return 0;
      case 'html_block':
        return blank && (c.htmlType == 6 || c.htmlType == 7) ? 1 : 0;
      case 'paragraph':
        return blank ? 1 : 0;
      case 'table':
        return blank || !line.contains('|', offset) ? 1 : 0;
      default:
        return 1; // headings, thematic breaks: single line
    }
  }

  void _incorporateLine(String ln) {
    var allMatched = true;
    var container = doc;
    oldtip = tip;
    offset = 0;
    column = 0;
    blank = false;
    partiallyConsumedTab = false;
    lineNumber += 1;
    line = ln.contains('\u0000') ? ln.replaceAll('\u0000', '\uFFFD') : ln;

    while (container.last != null && container.last!.open) {
      container = container.last!;
      _findNextNonspace();
      final result = _continue(container);
      if (result == 1) {
        allMatched = false;
      } else if (result == 2) {
        return;
      }
      if (!allMatched) {
        container = container.parent!;
        break;
      }
    }

    allClosed = identical(container, oldtip);
    lastMatched = container;

    var matchedLeaf = container.type != 'paragraph' && _acceptsLines(container.type);

    while (!matchedLeaf) {
      _findNextNonspace();
      if (!indented && !_reMaybeSpecial.hasMatch(line.substring(nextNonspace))) {
        _advanceNextNonspace();
        break;
      }
      var matched = false;
      for (var i = 0; i < 9; i++) {
        final res = _blockStart(i, container);
        if (res == 1) {
          container = tip;
          matched = true;
          break;
        } else if (res == 2) {
          container = tip;
          matchedLeaf = true;
          matched = true;
          break;
        }
      }
      if (!matched) {
        _advanceNextNonspace();
        break;
      }
    }

    if (!allClosed && !blank && tip.type == 'paragraph') {
      _addLine(); // lazy paragraph continuation
    } else {
      _closeUnmatched();
      if (blank && container.last != null) container.last!.lastLineBlank = true;

      final t = container.type;
      final lastLineBlank = blank &&
          !(t == 'block_quote' ||
              (t == 'code_block' && container.isFenced) ||
              (t == 'item' && container.first == null && container.startLine == lineNumber - 1));
      _B? cont = container;
      while (cont != null) {
        cont.lastLineBlank = lastLineBlank;
        cont = cont.parent;
      }

      if (_acceptsLines(t)) {
        _addLine();
        if (t == 'html_block' &&
            container.htmlType >= 1 &&
            container.htmlType <= 5 &&
            _htmlClose[container.htmlType].hasMatch(line.substring(offset > line.length ? line.length : offset))) {
          _finalize(container);
        }
      } else if (offset < line.length && !blank) {
        container = _addChild('paragraph');
        _advanceNextNonspace();
        _addLine();
      }
    }
  }

  int _blockStart(int index, _B container) {
    switch (index) {
      case 0:
        return _startBlockQuote();
      case 1:
        return _startAtxHeading();
      case 2:
        return _startFencedCode();
      case 3:
        return _startTable(container);
      case 4:
        return _startHtmlBlock(container);
      case 5:
        return _startSetextHeading(container);
      case 6:
        return _startThematicBreak();
      case 7:
        return _startListItem(container);
      default:
        return _startIndentedCode();
    }
  }

  int _startBlockQuote() {
    if (!indented && _peek(line, nextNonspace) == 0x3E) {
      _advanceNextNonspace();
      _advanceOffset(1, false);
      if (_isSpaceOrTab(_peek(line, offset))) _advanceOffset(1, true);
      _closeUnmatched();
      _addChild('block_quote');
      return 1;
    }
    return 0;
  }

  int _startAtxHeading() {
    if (indented) return 0;
    final m = _reAtx.firstMatch(line.substring(nextNonspace));
    if (m == null) return 0;
    _advanceNextNonspace();
    _advanceOffset(m.group(0)!.length, false);
    _closeUnmatched();
    final h = _addChild('heading');
    h.level = m.group(0)!.trim().length;
    h.content = line
        .substring(offset)
        .replaceFirst(RegExp(r'^[ \t]*#+[ \t]*$'), '')
        .replaceFirst(RegExp(r'[ \t]+#+[ \t]*$'), '');
    _advanceOffset(line.length - offset, false);
    return 2;
  }

  int _startFencedCode() {
    if (indented) return 0;
    final m = _reCodeFence.firstMatch(line.substring(nextNonspace));
    if (m == null) return 0;
    final fenceLength = m.group(0)!.length;
    _closeUnmatched();
    final c = _addChild('code_block');
    c.isFenced = true;
    c.fenceLength = fenceLength;
    c.fenceChar = m.group(0)![0];
    c.fenceOffset = indent;
    _advanceNextNonspace();
    _advanceOffset(fenceLength, false);
    return 2;
  }

  int _startHtmlBlock(_B container) {
    if (indented || _peek(line, nextNonspace) != 0x3C) return 0;
    final rest = line.substring(nextNonspace);
    for (var t = 1; t <= 7; t++) {
      if (_htmlOpen[t].hasMatch(rest) &&
          (t < 7 ||
              (container.type != 'paragraph' &&
                  !(!allClosed && !blank && tip.type == 'paragraph')))) {
        _closeUnmatched();
        final b = _addChild('html_block');
        b.htmlType = t;
        return 2;
      }
    }
    return 0;
  }

  int _startSetextHeading(_B container) {
    if (indented || container.type != 'paragraph') return 0;
    final m = _reSetext.firstMatch(line.substring(nextNonspace));
    if (m == null) return 0;
    _closeUnmatched();
    final (rest, consumed) = _stripReferenceDefinitions(container.content);
    container.content = rest;
    if (rest.isEmpty) return 0;
    final heading = _B('heading', container.startLine + consumed);
    heading.level = m.group(0)![0] == '=' ? 1 : 2;
    heading.content = rest;
    container.insertAfter(heading);
    container.unlink();
    tip = heading;
    _advanceOffset(line.length - offset, false);
    return 2;
  }

  int _startThematicBreak() {
    if (!indented && _reThematic.hasMatch(line.substring(nextNonspace))) {
      _closeUnmatched();
      _addChild('thematic_break');
      _advanceOffset(line.length - offset, false);
      return 2;
    }
    return 0;
  }

  // GFM pipe table: the last line of the open paragraph is the header row and
  // the current line is the delimiter row.
  int _startTable(_B container) {
    if (indented || container.type != 'paragraph') return 0;
    final rest = line.substring(nextNonspace);
    if (!rest.contains('|') || !_isTableDelimiterRow(rest)) return 0;
    final content = container.content;
    final body = content.endsWith('\n') ? content.substring(0, content.length - 1) : content;
    final nl = body.lastIndexOf('\n');
    final header = nl < 0 ? body : body.substring(nl + 1);
    if (!header.contains('|')) return 0;
    final headCells = _splitTableRow(header);
    final delimCells = _splitTableRow(rest);
    if (headCells.length != delimCells.length) return 0;

    _closeUnmatched();
    final before = nl < 0 ? '' : body.substring(0, nl + 1);
    final table = _B('table', container.startLine + '\n'.allMatches(before).length);
    table.tableHeader = header;
    table.aligns = delimCells.map(_alignOf).toList();
    container.insertAfter(table);
    if (before.isEmpty) {
      container.unlink();
    } else {
      container.content = before;
      _finalize(container);
    }
    tip = table;
    _advanceOffset(line.length - offset, false);
    return 2;
  }

  int _startListItem(_B container) {
    if (!indented || container.type == 'list') {
      final data = _parseListMarker(container);
      if (data != null) {
        _closeUnmatched();
        if (tip.type != 'list' || !_listsMatch(container.list, data)) {
          final list = _addChild('list');
          list.list = data;
        }
        final item = _addChild('item');
        item.list = data;
        return 1;
      }
    }
    return 0;
  }

  int _startIndentedCode() {
    if (indented && tip.type != 'paragraph' && !blank) {
      _advanceOffset(4, true);
      _closeUnmatched();
      _addChild('code_block');
      return 2;
    }
    return 0;
  }

  bool _listsMatch(_ListData? a, _ListData b) =>
      a != null && a.ordered == b.ordered && a.delimiter == b.delimiter && a.bulletChar == b.bulletChar;

  _ListData? _parseListMarker(_B container) {
    final rest = line.substring(nextNonspace);
    if (indent >= 4) return null;

    final bool ordered;
    var bullet = '';
    var start = 1;
    var delimiter = '';
    int markerLen;
    if (rest.isNotEmpty && (rest[0] == '*' || rest[0] == '+' || rest[0] == '-')) {
      ordered = false;
      bullet = rest[0];
      markerLen = 1;
    } else {
      final m = _reOrdered.firstMatch(rest);
      if (m == null || (container.type == 'paragraph' && int.parse(m.group(1)!) != 1)) {
        return null;
      }
      ordered = true;
      start = int.parse(m.group(1)!);
      delimiter = m.group(2)!;
      markerLen = m.group(0)!.length;
    }

    final nextc = _peek(line, nextNonspace + markerLen);
    if (!(nextc == -1 || nextc == 0x09 || nextc == 0x20)) return null;
    if (container.type == 'paragraph' &&
        !_reNonSpace.hasMatch(line.substring(nextNonspace + markerLen))) {
      return null;
    }

    final data = _ListData(ordered, bullet, start, delimiter, indent);

    _advanceNextNonspace();
    _advanceOffset(markerLen, true);
    final spacesStartCol = column;
    final spacesStartOffset = offset;
    int c;
    do {
      _advanceOffset(1, true);
      c = _peek(line, offset);
    } while (column - spacesStartCol < 5 && _isSpaceOrTab(c));
    final blankItem = _peek(line, offset) == -1;
    final spacesAfterMarker = column - spacesStartCol;
    if (spacesAfterMarker >= 5 || spacesAfterMarker < 1 || blankItem) {
      data.padding = markerLen + 1;
      column = spacesStartCol;
      offset = spacesStartOffset;
      if (_isSpaceOrTab(_peek(line, offset))) _advanceOffset(1, true);
    } else {
      data.padding = markerLen + spacesAfterMarker;
    }
    return data;
  }
}

// ── Tables ───────────────────────────────────────────────────────────────

final RegExp _delimCellPattern = RegExp(r'^:?-+:?$');

bool _isTableDelimiterRow(String line) {
  final trimmed = line.trim();
  if (trimmed.isEmpty || !trimmed.contains('-')) return false;
  final cells = _splitTableRow(trimmed);
  if (cells.isEmpty) return false;
  return cells.every((c) => _delimCellPattern.hasMatch(c.trim()));
}

MdTableAlign _alignOf(String cell) {
  final t = cell.trim();
  final left = t.startsWith(':');
  final right = t.endsWith(':');
  if (left && right) return MdTableAlign.center;
  if (right) return MdTableAlign.right;
  if (left) return MdTableAlign.left;
  return MdTableAlign.none;
}

List<String> _splitTableRow(String line) {
  var trimmed = line.trim();
  if (trimmed.startsWith('|')) trimmed = trimmed.substring(1);
  if (trimmed.endsWith('|')) {
    final escaped = trimmed.length >= 2 && trimmed[trimmed.length - 2] == '\\';
    if (!escaped) trimmed = trimmed.substring(0, trimmed.length - 1);
  }

  final cells = <String>[];
  final buffer = StringBuffer();
  for (int i = 0; i < trimmed.length; i++) {
    final ch = trimmed[i];
    if (ch == '\\' && i + 1 < trimmed.length && trimmed[i + 1] == '|') {
      buffer.write('|');
      i++;
      continue;
    }
    if (ch == '|') {
      cells.add(buffer.toString().trim());
      buffer.clear();
    } else {
      buffer.write(ch);
    }
  }
  cells.add(buffer.toString().trim());
  return cells;
}

// ── Tree -> app AST ──────────────────────────────────────────────────────

final RegExp _calloutPattern = RegExp(
  r'^\[!([a-zA-Z0-9_-]+)\]([+-]?)(?:[ \t]+([^\n]*))?(?:\n([\s\S]*))?$',
);
final RegExp _taskPattern = RegExp(r'^\[([ xX])\](?:[ \t]|\n|$)');
final RegExp _hrTagPattern = RegExp(r'^<hr\s*/?>$', caseSensitive: false);

class _Converter {
  _Converter(this.refs, this.options);
  final MdReferenceMap refs;
  final MdParseOptions options;

  List<MdInline> _inline(String text) =>
      parseInline(text, references: refs, options: options);

  List<MdBlock> blocks(_B parent) {
    final out = <MdBlock>[];
    for (var c = parent.first; c != null; c = c.next) {
      out.addAll(_block(c));
    }
    return out;
  }

  /// A paragraph that holds nothing but images (one per line, as the editor's
  /// "add image" inserts them) becomes one image block each, so the viewer
  /// shows the pictures instead of inline placeholders.
  static bool _isBlankText(MdInline n) => n is MdText && n.text.trim().isEmpty;

  List<MdBlock> _paragraph(_B c) {
    final text = c.content.trim();
    if (text.isEmpty) return const [];
    final inl = _inline(text);
    final onlyImages = inl.any((n) => n is MdInlineImage) &&
        inl.every((n) => n is MdInlineImage || n is MdLineBreak || _isBlankText(n));
    if (onlyImages) {
      final images = inl.whereType<MdInlineImage>().toList();
      return [
        for (var i = 0; i < images.length; i++)
          MdImageBlock(
            images[i].alt,
            images[i].path,
            title: images[i].title,
            sourceLine: c.startLine + i,
          ),
      ];
    }
    return [MdParagraph(inl, sourceLine: c.startLine)];
  }

  List<MdBlock> _block(_B c) {
    switch (c.type) {
      case 'paragraph':
        return _paragraph(c);
      case 'heading':
        return [MdHeading(c.level, _inline(c.content.trim()), sourceLine: c.startLine)];
      case 'thematic_break':
        return [MdHorizontalRule(sourceLine: c.startLine)];
      case 'block_quote':
        return [_callout(c) ?? MdBlockquote(blocks(c), sourceLine: c.startLine)];
      case 'code_block':
        var code = c.literal;
        if (code.endsWith('\n')) code = code.substring(0, code.length - 1);
        String? language;
        if (c.isFenced && c.info.isNotEmpty) language = c.info.split(RegExp(r'\s+')).first;
        return [MdCodeBlock(code, language, sourceLine: c.startLine)];
      case 'html_block':
        final h = _htmlBlock(c);
        return h == null ? const [] : [h];
      case 'list':
        final data = c.list!;
        final items = <MdListItem>[];
        for (var it = c.first; it != null; it = it.next) {
          items.add(_item(it));
        }
        return [
          MdList(
            ordered: data.ordered,
            startNumber: data.start,
            items: items,
            tight: data.tight,
            sourceLine: c.startLine,
          ),
        ];
      case 'table':
        return [_table(c)];
    }
    return const [];
  }

  MdBlock? _htmlBlock(_B c) {
    if (!options.interpretHtml) return MdHtmlBlock(c.literal, sourceLine: c.startLine);
    var raw = c.literal.trim();
    if (c.htmlType == 2) {
      // Comments are invisible, but text sharing their line is not.
      raw = raw.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '').trim();
    }
    if (raw.isEmpty) return null;
    if (_hrTagPattern.hasMatch(raw)) return MdHorizontalRule(sourceLine: c.startLine);
    return MdParagraph(_inline(raw), sourceLine: c.startLine);
  }

  MdListItem _item(_B item) {
    bool? checked;
    final first = item.first;
    if (first != null && first.type == 'paragraph') {
      final m = _taskPattern.firstMatch(first.content);
      if (m != null) {
        checked = m.group(1)!.toLowerCase() == 'x';
        first.content = first.content.substring(m.end);
      }
    }
    return MdListItem(children: blocks(item), checked: checked, sourceLine: item.startLine);
  }

  MdCallout? _callout(_B quote) {
    final first = quote.first;
    if (first == null || first.type != 'paragraph') return null;
    final m = _calloutPattern.firstMatch(first.content.trim());
    if (m == null) return null;

    final sign = m.group(2) ?? '';
    final children = <MdBlock>[];
    final body = (m.group(4) ?? '').trim();
    if (body.isNotEmpty) {
      children.add(MdParagraph(_inline(body), sourceLine: first.startLine + 1));
    }
    for (var c = first.next; c != null; c = c.next) {
      children.addAll(_block(c));
    }
    return MdCallout(
      type: m.group(1)!.toLowerCase(),
      title: m.group(3)?.trim() ?? '',
      children: children,
      collapsible: sign.isNotEmpty,
      defaultCollapsed: sign == '-',
      sourceLine: quote.startLine,
    );
  }

  MdTable _table(_B t) {
    final header = _splitTableRow(t.tableHeader);
    final width = header.length;
    final rows = <List<List<MdInline>>>[];
    for (final raw in t.content.split('\n')) {
      if (raw.trim().isEmpty) continue;
      final cells = _splitTableRow(raw);
      // GFM: a row has exactly as many cells as the header.
      final fixed = List<String>.generate(width, (i) => i < cells.length ? cells[i] : '');
      rows.add(fixed.map(_inline).toList());
    }
    return MdTable(
      headerCells: header.map(_inline).toList(),
      alignments: t.aligns,
      rows: rows,
      sourceLine: t.startLine,
    );
  }
}
