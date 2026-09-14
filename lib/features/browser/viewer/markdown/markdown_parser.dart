import 'markdown_ast.dart';
import 'markdown_inline_parser.dart';

List<MdBlock> parseMarkdownDocument(String source) {
  final lines = source
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n');
  final blocks = <MdBlock>[];
  int i = 0;
  while (i < lines.length) {
    if (lines[i].trim().isEmpty) {
      i++;
      continue;
    }
    final (block, next) = _parseOneBlock(lines, i);
    blocks.add(block);
    i = next;
  }
  return blocks;
}

(MdBlock, int) _parseOneBlock(List<String> lines, int start) {
  final line = lines[start];

  // 1. Fenced code block (``` or ~~~)
  final fence = _matchFence(line);
  if (fence != null) {
    return _parseFencedCodeBlock(lines, start, fence);
  }

  // 2. Indented code block (4 spaces or 1 tab)
  if (_isIndentedCodeLine(line)) {
    return _parseIndentedCodeBlock(lines, start);
  }

  // 3. ATX heading (# Title)
  final heading = _matchAtxHeading(line);
  if (heading != null) {
    return (
      MdHeading(heading.level, parseInline(heading.text), sourceLine: start),
      start + 1,
    );
  }

  // 4. Horizontal rule (---, ***, ___)
  if (_isHorizontalRule(line)) {
    return (MdHorizontalRule(sourceLine: start), start + 1);
  }

  // 5. Blockquote (>)
  if (_isBlockquoteStart(line)) {
    return _parseBlockquote(lines, start);
  }

  // 6. GFM Pipe Table
  if (_isTableStart(lines, start)) {
    return _parseTable(lines, start);
  }

  // 7. Ordered / Unordered List
  final listMarker = _matchListMarker(line);
  if (listMarker != null) {
    return _parseList(lines, start, listMarker.indent);
  }

  // 8. Standalone image
  final image = _matchStandaloneImage(line);
  if (image != null) {
    return (MdImageBlock(image.alt, image.url, sourceLine: start), start + 1);
  }

  // 9. Paragraph
  return _parseParagraph(lines, start);
}

bool _looksLikeNewBlockStart(List<String> lines, int i) {
  final line = lines[i];
  return _matchFence(line) != null ||
      _isIndentedCodeLine(line) ||
      _matchAtxHeading(line) != null ||
      _isHorizontalRule(line) ||
      _isBlockquoteStart(line) ||
      _matchListMarker(line) != null ||
      _isTableStart(lines, i);
}

// ── Indented Code Blocks (4 spaces or 1 tab) ─────────────────────────────

bool _isIndentedCodeLine(String line) {
  return line.startsWith('    ') || line.startsWith('\t');
}

(MdBlock, int) _parseIndentedCodeBlock(List<String> lines, int start) {
  final buffer = <String>[];
  int i = start;

  while (i < lines.length) {
    final line = lines[i];

    if (_isIndentedCodeLine(line)) {
      if (line.startsWith('    ')) {
        buffer.add(line.substring(4));
      } else if (line.startsWith('\t')) {
        buffer.add(line.substring(1));
      }
      i++;
    } else if (line.trim().isEmpty) {
      // Look ahead to see if the code block continues after blank lines
      int lookahead = i + 1;
      while (lookahead < lines.length && lines[lookahead].trim().isEmpty) {
        lookahead++;
      }
      if (lookahead < lines.length && _isIndentedCodeLine(lines[lookahead])) {
        while (i < lookahead) {
          buffer.add('');
          i++;
        }
      } else {
        break;
      }
    } else {
      break;
    }
  }

  // Trim trailing empty lines inside code block
  while (buffer.isNotEmpty && buffer.last.isEmpty) {
    buffer.removeLast();
  }

  return (
    MdCodeBlock(buffer.join('\n'), null, sourceLine: start),
    i,
  );
}

// ── Fenced Code Blocks ───────────────────────────────────────────────────

class _FenceInfo {
  final String char;
  final int length;
  final String? language;
  const _FenceInfo(this.char, this.length, this.language);
}

_FenceInfo? _matchFence(String line) {
  final trimmed = line.trimLeft();
  if (trimmed.isEmpty) return null;

  final fenceChar = trimmed[0];
  if (fenceChar != '`' && fenceChar != '~') return null;

  final runLen = _leadingRunLength(trimmed, fenceChar);
  if (runLen < 3) return null;

  final rest = trimmed.substring(runLen).trim();
  final language = rest.isEmpty ? null : rest.split(RegExp(r'\s+')).first;
  return _FenceInfo(fenceChar, runLen, language);
}

(MdBlock, int) _parseFencedCodeBlock(
  List<String> lines,
  int start,
  _FenceInfo fence,
) {
  final buffer = <String>[];
  int i = start + 1;
  while (i < lines.length) {
    final trimmed = lines[i].trimLeft();
    final runLen = _leadingRunLength(trimmed, fence.char);
    if (runLen >= fence.length && trimmed.substring(runLen).trim().isEmpty) {
      i++;
      break;
    }
    buffer.add(lines[i]);
    i++;
  }
  return (MdCodeBlock(buffer.join('\n'), fence.language, sourceLine: start), i);
}

int _leadingRunLength(String s, String ch) {
  int n = 0;
  while (n < s.length && s[n] == ch) {
    n++;
  }
  return n;
}

class _HeadingMatch {
  final int level;
  final String text;
  const _HeadingMatch(this.level, this.text);
}

_HeadingMatch? _matchAtxHeading(String line) {
  final trimmed = line.trimLeft();
  final indent = line.length - trimmed.length;
  if (indent > 3) return null;

  int level = 0;
  while (level < trimmed.length && level < 7 && trimmed[level] == '#') {
    level++;
  }
  if (level == 0 || level > 6) return null;

  final rest = trimmed.substring(level);
  if (rest.isNotEmpty && rest[0] != ' ' && rest[0] != '\t') {
    return null;
  }

  var text = rest.trim();
  text = text.replaceFirst(RegExp(r'[ \t]+#+$'), '');
  return _HeadingMatch(level, text);
}

bool _isHorizontalRule(String line) {
  final trimmed = line.trim();
  if (trimmed.length < 3) return false;

  final lower = trimmed.toLowerCase();
  if (lower == '<hr>' || lower == '<hr/>' || lower == '<hr />') {
    return true;
  }

  final compact = trimmed.replaceAll(' ', '').replaceAll('\t', '');
  if (compact.length < 3) return false;
  final first = compact[0];
  if (first != '-' && first != '*' && first != '_') return false;
  for (int i = 1; i < compact.length; i++) {
    if (compact[i] != first) return false;
  }
  return true;
}

bool _isBlockquoteStart(String line) {
  final trimmed = line.trimLeft();
  return trimmed.startsWith('>');
}

(MdBlock, int) _parseBlockquote(List<String> lines, int start) {
  final content = <String>[];
  int i = start;
  bool inFence = false;

  while (i < lines.length) {
    final line = lines[i];

    if (_isBlockquoteStart(line)) {
      final trimmed = line.trimLeft();
      var rest = trimmed.substring(1);
      if (rest.startsWith(' ')) rest = rest.substring(1);

      if (_matchFence(rest) != null) {
        inFence = !inFence;
      }
      content.add(rest);
      i++;
    } else if (inFence) {
      content.add(line);
      if (_matchFence(line) != null) {
        inFence = false;
      }
      i++;
    } else if (line.trim().isEmpty) {
      if (i + 1 < lines.length && _isBlockquoteStart(lines[i + 1])) {
        content.add('');
        i++;
      } else {
        break;
      }
    } else {
      break;
    }
  }

  final joined = content.join('\n');

  final calloutMatch = RegExp(
    r'^\[!([a-zA-Z0-9_-]+)\]([+-]?)(?:[ \t]+([^\n]*))?(?:\n([\s\S]*))?$',
  ).firstMatch(joined.trim());

  if (calloutMatch != null) {
    final type = calloutMatch.group(1)!.toLowerCase();
    final collapseSign = calloutMatch.group(2);
    final title = calloutMatch.group(3)?.trim() ?? '';
    final body = calloutMatch.group(4) ?? '';
    final innerBlocks = body.trim().isEmpty ? <MdBlock>[] : parseMarkdownDocument(body);

    return (
      MdCallout(
        type: type,
        title: title,
        children: innerBlocks,
        collapsible: collapseSign != null && collapseSign.isNotEmpty,
        defaultCollapsed: collapseSign == '-',
        sourceLine: start,
      ),
      i,
    );
  }

  final innerBlocks = parseMarkdownDocument(joined);
  return (MdBlockquote(innerBlocks, sourceLine: start), i);
}

final RegExp _ulMarkerPattern = RegExp(r'^( {0,3})([-*+])( +)(.*)$');
final RegExp _olMarkerPattern = RegExp(r'^( {0,3})(\d{1,9})([.)])( +)(.*)$');
final RegExp _taskCheckboxPattern = RegExp(r'^\[([ xX])\](?: |$)');

class _ListMarkerMatch {
  final int indent;
  final bool ordered;
  final int start;
  final int markerWidth;
  final String content;
  const _ListMarkerMatch({
    required this.indent,
    required this.ordered,
    required this.start,
    required this.markerWidth,
    required this.content,
  });
}

_ListMarkerMatch? _matchListMarker(String line) {
  final ul = _ulMarkerPattern.firstMatch(line);
  if (ul != null) {
    final indent = ul.group(1)!.length;
    final gap = ul.group(3)!.length;
    return _ListMarkerMatch(
      indent: indent,
      ordered: false,
      start: 1,
      markerWidth: indent + 1 + gap,
      content: ul.group(4)!,
    );
  }
  final ol = _olMarkerPattern.firstMatch(line);
  if (ol != null) {
    final indent = ol.group(1)!.length;
    final number = int.tryParse(ol.group(2)!) ?? 1;
    final gap = ol.group(4)!.length;
    return _ListMarkerMatch(
      indent: indent,
      ordered: true,
      start: number,
      markerWidth: indent + ol.group(2)!.length + 1 + gap,
      content: ol.group(5)!,
    );
  }
  return null;
}

(MdBlock, int) _parseList(List<String> lines, int start, int indent) {
  final firstMarker = _matchListMarker(lines[start])!;
  final ordered = firstMarker.ordered;
  final startNumber = firstMarker.start;
  final items = <MdListItem>[];
  int i = start;

  while (i < lines.length) {
    final marker = _matchListMarker(lines[i]);
    if (marker == null || marker.indent != indent || marker.ordered != ordered) {
      break;
    }
    final itemLines = <String>[marker.content];
    final itemStartLine = i;
    final contentIndent = marker.markerWidth;
    i++;
    bool inFence = false;

    while (i < lines.length) {
      final line = lines[i];

      if (inFence) {
        final leading = line.length - line.trimLeft().length;
        final trimAmt = leading >= contentIndent ? contentIndent : (leading >= 2 ? leading : 0);
        itemLines.add(line.substring(trimAmt));
        if (_matchFence(line.trimLeft()) != null) {
          inFence = false;
        }
        i++;
        continue;
      }

      if (line.trim().isEmpty) {
        if (i + 1 < lines.length) {
          final nextLine = lines[i + 1];
          final nextIndent = nextLine.length - nextLine.trimLeft().length;
          final nextMarker = _matchListMarker(nextLine);
          final nextIsSibling = nextMarker != null && nextMarker.indent == indent;
          if (nextIndent >= 2 || nextIsSibling) {
            itemLines.add('');
            i++;
            continue;
          }
        }
        break;
      }

      final leading = line.length - line.trimLeft().length;
      final nextMarker = _matchListMarker(line);
      final isSibling = nextMarker != null && nextMarker.indent == indent;

      if (isSibling) {
        break;
      }

      if (leading >= 2 || leading >= contentIndent) {
        final trimmed = line.trimLeft();
        if (_matchFence(trimmed) != null) {
          inFence = true;
        }
        final trimAmt = leading >= contentIndent ? contentIndent : 2;
        itemLines.add(line.substring(trimAmt));
        i++;
      } else {
        break;
      }
    }

    final itemSource = itemLines.join('\n');
    final checked = _matchTaskCheckbox(itemSource);
    final bodySource = checked == null
        ? itemSource
        : itemSource.replaceFirst(_taskCheckboxPattern, '');
    final children = parseMarkdownDocument(bodySource);
    items.add(MdListItem(
      children: children,
      checked: checked,
      sourceLine: itemStartLine,
    ));
  }

  return (
    MdList(
      ordered: ordered,
      startNumber: startNumber,
      items: items,
      sourceLine: start,
    ),
    i,
  );
}

bool? _matchTaskCheckbox(String itemSource) {
  final m = _taskCheckboxPattern.firstMatch(itemSource);
  if (m == null) return null;
  return m.group(1)!.toLowerCase() == 'x';
}

bool _isTableStart(List<String> lines, int i) {
  if (!lines[i].contains('|')) return false;
  if (i + 1 >= lines.length) return false;
  return _isTableDelimiterRow(lines[i + 1]);
}

final RegExp _delimCellPattern = RegExp(r'^:?-+:?$');

bool _isTableDelimiterRow(String line) {
  final trimmed = line.trim();
  if (trimmed.isEmpty || !trimmed.contains('-')) return false;
  final cells = _splitTableRow(trimmed);
  if (cells.isEmpty) return false;
  return cells.every((c) => _delimCellPattern.hasMatch(c.trim()));
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

(MdBlock, int) _parseTable(List<String> lines, int start) {
  final headerCellsRaw = _splitTableRow(lines[start]);
  final delimCellsRaw = _splitTableRow(lines[start + 1]);

  final alignments = delimCellsRaw.map((c) {
    final t = c.trim();
    final left = t.startsWith(':');
    final right = t.endsWith(':');
    if (left && right) return MdTableAlign.center;
    if (right) return MdTableAlign.right;
    if (left) return MdTableAlign.left;
    return MdTableAlign.none;
  }).toList();

  final headerCells = headerCellsRaw.map(parseInline).toList();

  final rows = <List<List<MdInline>>>[];
  int i = start + 2;
  while (i < lines.length && lines[i].trim().isNotEmpty && lines[i].contains('|')) {
    final rawCells = _splitTableRow(lines[i]);
    rows.add(rawCells.map(parseInline).toList());
    i++;
  }

  return (
    MdTable(
      headerCells: headerCells,
      alignments: alignments,
      rows: rows,
      sourceLine: start,
    ),
    i,
  );
}

final RegExp _standaloneImagePattern = RegExp(r'^!\[([^\]]*)\]\(([^)]*)\)$');

class _ImageMatch {
  final String alt;
  final String url;
  const _ImageMatch(this.alt, this.url);
}

_ImageMatch? _matchStandaloneImage(String line) {
  final m = _standaloneImagePattern.firstMatch(line.trim());
  if (m == null) return null;
  return _ImageMatch(m.group(1) ?? '', (m.group(2) ?? '').trim());
}

(MdBlock, int) _parseParagraph(List<String> lines, int start) {
  final buffer = <String>[lines[start]];
  int i = start + 1;
  while (i < lines.length) {
    final line = lines[i];
    if (line.trim().isEmpty) break;
    if (_looksLikeNewBlockStart(lines, i)) break;
    buffer.add(line);
    i++;
  }
  return (
    MdParagraph(parseInline(_joinParagraphLines(buffer)), sourceLine: start),
    i,
  );
}

String _joinParagraphLines(List<String> rawLines) {
  final buffer = StringBuffer();
  for (int i = 0; i < rawLines.length; i++) {
    final line = rawLines[i];
    final isLast = i == rawLines.length - 1;
    if (isLast) {
      buffer.write(line.trimRight());
      continue;
    }
    final hardBreak = line.endsWith('  ') || line.endsWith('\\');
    final content = line.endsWith('\\')
        ? line.substring(0, line.length - 1)
        : line.trimRight();
    buffer.write(content);
    buffer.write(hardBreak ? '\n' : ' ');
  }
  return buffer.toString();
}