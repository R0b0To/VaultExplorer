import 'markdown_ast.dart';

List<MdInline> parseInline(String text) {
  return _autoLinkify(_parseInlineRaw(text));
}

List<MdInline> _parseInlineRaw(String text) {
  final result = <MdInline>[];
  final buffer = StringBuffer();

  void flush() {
    if (buffer.isNotEmpty) {
      result.add(MdText(_decodeHtmlEntities(buffer.toString())));
      buffer.clear();
    }
  }

  int i = 0;
  while (i < text.length) {
    final ch = text[i];

    if (ch == '\n') {
      flush();
      result.add(const MdLineBreak());
      i += 1;
      continue;
    }

    if (ch == '\\' && i + 1 < text.length && _isEscapable(text[i + 1])) {
      buffer.write(text[i + 1]);
      i += 2;
      continue;
    }

    if (ch == '<') {
      final autolink = _matchAngleAutolink(text, i);
      if (autolink != null) {
        flush();
        result.add(MdLink([MdText(autolink.label)], autolink.url));
        i = autolink.end;
        continue;
      }

      final br = _matchBrTag(text, i);
      if (br != null) {
        flush();
        result.add(const MdLineBreak());
        i = br.end;
        continue;
      }

      final html = _matchHtmlFormattingTag(text, i);
      if (html != null) {
        flush();
        result.add(html.node);
        i = html.end;
        continue;
      }
    }

    if (ch == '`') {
      final match = _matchCodeSpan(text, i);
      if (match != null) {
        flush();
        result.add(MdInlineCode(match.content));
        i = match.end;
        continue;
      }
    }

    if (ch == '!' && i + 1 < text.length && text[i + 1] == '[') {
      final match = _matchLinkLike(text, i + 1);
      if (match != null) {
        flush();
        result.add(MdInlineImage(match.label, match.url));
        i = match.end;
        continue;
      }
    }

    if (ch == '[') {
      final match = _matchLinkLike(text, i);
      if (match != null) {
        flush();
        result.add(MdLink(_parseInlineRaw(match.label), match.url));
        i = match.end;
        continue;
      }
    }

    if (ch == '=' && i + 1 < text.length && text[i + 1] == '=') {
      final closeIdx = _findClosingDelim(text, i + 2, '==');
      if (closeIdx != null && closeIdx > i + 2) {
        flush();
        result.add(MdHighlight(_parseInlineRaw(text.substring(i + 2, closeIdx))));
        i = closeIdx + 2;
        continue;
      }
    }

    if ((ch == '*' || ch == '_') && i + 1 < text.length && text[i + 1] == ch) {
      final delim = ch + ch;
      final closeIdx = _findClosingDelim(text, i + 2, delim);
      if (closeIdx != null && closeIdx > i + 2) {
        flush();
        result.add(MdBold(_parseInlineRaw(text.substring(i + 2, closeIdx))));
        i = closeIdx + 2;
        continue;
      }
    }

    if (ch == '~' && i + 1 < text.length && text[i + 1] == '~') {
      final closeIdx = _findClosingDelim(text, i + 2, '~~');
      if (closeIdx != null && closeIdx > i + 2) {
        flush();
        result.add(MdStrikethrough(_parseInlineRaw(text.substring(i + 2, closeIdx))));
        i = closeIdx + 2;
        continue;
      }
    }

    if (ch == '*' || ch == '_') {
      final closeIdx = _findClosingDelim(text, i + 1, ch);
      if (closeIdx != null && closeIdx > i + 1) {
        flush();
        result.add(MdItalic(_parseInlineRaw(text.substring(i + 1, closeIdx))));
        i = closeIdx + 1;
        continue;
      }
    }

    buffer.write(ch);
    i += 1;
  }
  flush();
  return result;
}

bool _isEscapable(String ch) => r'\`*_{}[]()#+-.!~>|='.contains(ch);

String _decodeHtmlEntities(String text) {
  if (!text.contains('&')) return text;
  var out = text
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&#39;', "'")
      .replaceAll('&nbsp;', '\u00A0');

  out = out.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
    final code = int.tryParse(m.group(1)!);
    return code != null ? String.fromCharCode(code) : m.group(0)!;
  });

  out = out.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) {
    final code = int.tryParse(m.group(1)!, radix: 16);
    return code != null ? String.fromCharCode(code) : m.group(0)!;
  });

  return out;
}

class _AngleAutolinkMatch {
  final String label;
  final String url;
  final int end;
  const _AngleAutolinkMatch(this.label, this.url, this.end);
}

final RegExp _angleUriPattern = RegExp(r'^<([a-zA-Z][a-zA-Z0-9+.-]*:[^\s>]+)>');
final RegExp _angleEmailPattern = RegExp(r'^<([a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\.[a-zA-Z0-9-.]+)>');

_AngleAutolinkMatch? _matchAngleAutolink(String text, int start) {
  final sub = text.substring(start);
  final uriMatch = _angleUriPattern.firstMatch(sub);
  if (uriMatch != null) {
    final url = uriMatch.group(1)!;
    return _AngleAutolinkMatch(url, url, start + uriMatch.group(0)!.length);
  }
  final emailMatch = _angleEmailPattern.firstMatch(sub);
  if (emailMatch != null) {
    final email = emailMatch.group(1)!;
    return _AngleAutolinkMatch(email, 'mailto:$email', start + emailMatch.group(0)!.length);
  }
  return null;
}

class _BrTagMatch {
  final int end;
  const _BrTagMatch(this.end);
}

final RegExp _brPattern = RegExp(r'^<br\s*/?>', caseSensitive: false);

_BrTagMatch? _matchBrTag(String text, int start) {
  final sub = text.substring(start);
  final m = _brPattern.firstMatch(sub);
  if (m != null) {
    return _BrTagMatch(start + m.group(0)!.length);
  }
  return null;
}

class _HtmlTagMatch {
  final MdInline node;
  final int end;
  const _HtmlTagMatch(this.node, this.end);
}

final RegExp _openTagPattern = RegExp(r'^<([a-zA-Z]+)(?:\s+([^>]*))?>', caseSensitive: false);

_HtmlTagMatch? _matchHtmlFormattingTag(String text, int start) {
  final sub = text.substring(start);
  final openMatch = _openTagPattern.firstMatch(sub);
  if (openMatch == null) return null;

  final tagName = openMatch.group(1)!.toLowerCase();
  final attrs = openMatch.group(2) ?? '';
  final openLen = openMatch.group(0)!.length;

  const supported = {
    'b', 'strong', 'i', 'em', 'u', 'ins', 's', 'del', 'strike',
    'mark', 'sub', 'sup', 'code', 'a',
  };

  if (!supported.contains(tagName)) return null;

  final closeTag = '</$tagName>';
  final closeIdx = text.toLowerCase().indexOf(closeTag, start + openLen);
  if (closeIdx == -1) return null;

  final inner = text.substring(start + openLen, closeIdx);
  final totalEnd = closeIdx + closeTag.length;

  if (tagName == 'a') {
    final hrefMatch = RegExp(r'''href=["']([^"']*)["']''', caseSensitive: false).firstMatch(attrs);
    final url = hrefMatch?.group(1) ?? '';
    return _HtmlTagMatch(MdLink(_parseInlineRaw(inner), url), totalEnd);
  }

  if (tagName == 'code') {
    return _HtmlTagMatch(MdInlineCode(inner), totalEnd);
  }

  final children = _parseInlineRaw(inner);
  final MdInline node = switch (tagName) {
    'b' || 'strong' => MdBold(children),
    'i' || 'em' => MdItalic(children),
    'u' || 'ins' => MdUnderline(children),
    's' || 'del' || 'strike' => MdStrikethrough(children),
    'mark' => MdHighlight(children),
    'sub' => MdSubscript(children),
    'sup' => MdSuperscript(children),
    _ => MdText(inner),
  };

  return _HtmlTagMatch(node, totalEnd);
}

class _CodeSpanMatch {
  final String content;
  final int end;
  const _CodeSpanMatch(this.content, this.end);
}

_CodeSpanMatch? _matchCodeSpan(String text, int start) {
  int i = start;
  int runLen = 0;
  while (i < text.length && text[i] == '`') {
    runLen++;
    i++;
  }
  final openEnd = i;
  final delim = '`' * runLen;
  int searchFrom = openEnd;
  while (true) {
    final idx = text.indexOf(delim, searchFrom);
    if (idx == -1) return null;
    final afterIdx = idx + runLen;
    final precededByBacktick = idx > 0 && text[idx - 1] == '`';
    final followedByBacktick = afterIdx < text.length && text[afterIdx] == '`';
    if (!precededByBacktick && !followedByBacktick) {
      var content = text.substring(openEnd, idx);
      if (content.length >= 2 &&
          content.startsWith(' ') &&
          content.endsWith(' ') &&
          content.trim().isNotEmpty) {
        content = content.substring(1, content.length - 1);
      }
      return _CodeSpanMatch(content, afterIdx);
    }
    searchFrom = idx + 1;
  }
}

int? _findClosingDelim(String text, int start, String delim) {
  int i = start;
  while (i < text.length) {
    if (text[i] == '\\' && i + 1 < text.length) {
      i += 2;
      continue;
    }
    if (text[i] == '`') {
      final codeMatch = _matchCodeSpan(text, i);
      if (codeMatch != null) {
        i = codeMatch.end;
        continue;
      }
    }
    if (text.startsWith(delim, i)) {
      return i;
    }
    i += 1;
  }
  return null;
}

class _LinkLikeMatch {
  final String label;
  final String url;
  final int end;
  const _LinkLikeMatch(this.label, this.url, this.end);
}

_LinkLikeMatch? _matchLinkLike(String text, int start) {
  if (start >= text.length || text[start] != '[') return null;

  int depth = 1;
  int i = start + 1;
  while (i < text.length) {
    if (text[i] == '\\' && i + 1 < text.length) {
      i += 2;
      continue;
    }
    if (text[i] == '[') {
      depth++;
    } else if (text[i] == ']') {
      depth--;
      if (depth == 0) break;
    }
    i++;
  }
  if (depth != 0) return null;
  final labelEnd = i;
  if (labelEnd + 1 >= text.length || text[labelEnd + 1] != '(') return null;

  int j = labelEnd + 2;
  int parenDepth = 1;
  final urlStart = j;
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

  final label = text.substring(start + 1, labelEnd);
  final url = text.substring(urlStart, j).trim();
  return _LinkLikeMatch(label, url, j + 1);
}

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