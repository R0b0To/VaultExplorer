// Command-line adapter: reads Markdown on stdin, writes HTML on stdout, using the
// VaultExplorer viewer parser in its strict CommonMark profile. Exists only so
// the official CommonMark runner (spec_tests.py) can drive it.
import 'dart:convert';
import 'dart:io';

import 'package:vaultexplorer/features/browser/viewer/markdown/markdown_ast.dart';
import 'package:vaultexplorer/features/browser/viewer/markdown/markdown_link_syntax.dart';
import 'package:vaultexplorer/features/browser/viewer/markdown/markdown_parser.dart';

String esc(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

String titleAttr(String? title) => title == null ? '' : ' title="${esc(title)}"';

String inl(List<MdInline> ns) {
  final b = StringBuffer();
  for (final n in ns) {
    switch (n) {
      case MdText t:
        b.write(esc(t.text));
      case MdLineBreak _:
        b.write('<br />\n');
      case MdBold x:
        b.write('<strong>${inl(x.children)}</strong>');
      case MdItalic x:
        b.write('<em>${inl(x.children)}</em>');
      case MdUnderline x:
        b.write('<u>${inl(x.children)}</u>');
      case MdStrikethrough x:
        b.write('<del>${inl(x.children)}</del>');
      case MdHighlight x:
        b.write('<mark>${inl(x.children)}</mark>');
      case MdSubscript x:
        b.write('<sub>${inl(x.children)}</sub>');
      case MdSuperscript x:
        b.write('<sup>${inl(x.children)}</sup>');
      case MdInlineCode c:
        b.write('<code>${esc(c.code)}</code>');
      case MdLink l:
        b.write('<a href="${esc(normalizeLinkUri(l.url))}"${titleAttr(l.title)}>${inl(l.children)}</a>');
      case MdInlineImage i:
        b.write('<img src="${esc(normalizeLinkUri(i.path))}" alt="${esc(i.alt)}"${titleAttr(i.title)} />');
      case MdHtmlInline h:
        b.write(h.html);
    }
  }
  return b.toString();
}

String blk(List<MdBlock> bs, {bool tight = false}) {
  final b = StringBuffer();
  for (final n in bs) {
    switch (n) {
      case MdHeading h:
        b.write('<h${h.level}>${inl(h.content)}</h${h.level}>\n');
      case MdParagraph p:
        b.write(tight ? '${inl(p.content)}\n' : '<p>${inl(p.content)}</p>\n');
      case MdBlockquote q:
        b.write('<blockquote>\n${blk(q.children)}</blockquote>\n');
      case MdCallout c:
        b.write('<blockquote>\n${blk(c.children)}</blockquote>\n');
      case MdCodeBlock c:
        final cls = c.language == null ? '' : ' class="language-${esc(c.language!)}"';
        b.write('<pre><code$cls>${esc(c.code)}${c.code.isEmpty ? '' : '\n'}</code></pre>\n');
      case MdHorizontalRule _:
        b.write('<hr />\n');
      case MdImageBlock i:
        final img = '<img src="${esc(normalizeLinkUri(i.path))}" alt="${esc(i.alt)}"${titleAttr(i.title)} />';
        b.write(tight ? '$img\n' : '<p>$img</p>\n');
      case MdList l:
        final tag = l.ordered ? 'ol' : 'ul';
        final start = l.ordered && l.startNumber != 1 ? ' start="${l.startNumber}"' : '';
        b.write('<$tag$start>\n');
        for (final it in l.items) {
          b.write('<li>${blk(it.children, tight: l.tight)}</li>\n');
        }
        b.write('</$tag>\n');
      case MdHtmlBlock h:
        b.write('${h.html}\n');
      case MdTable _:
        break;
    }
  }
  return b.toString();
}

Future<void> main() async {
  final input = await utf8.decodeStream(stdin);
  stdout.write(blk(parseMarkdownDocument(input, options: MdParseOptions.commonMark)));
}
