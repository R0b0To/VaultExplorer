// Renders the viewer's AST as HTML-ish text so it can be compared with the
// CommonMark spec's expected HTML (whitespace and tight/loose differences are
// normalised away; the AST intentionally has neither).
import 'package:vaultexplorer/features/browser/viewer/markdown/markdown_ast.dart';
import 'package:vaultexplorer/features/browser/viewer/markdown/markdown_link_syntax.dart';

String esc(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

String inl(List<MdInline> ns) {
  final b = StringBuffer();
  for (final n in ns) {
    switch (n) {
      case MdText t: b.write(esc(t.text));
      case MdLineBreak _: b.write('<br />\n');
      case MdBold x: b.write('<strong>${inl(x.children)}</strong>');
      case MdItalic x: b.write('<em>${inl(x.children)}</em>');
      case MdUnderline x: b.write('<u>${inl(x.children)}</u>');
      case MdStrikethrough x: b.write('<del>${inl(x.children)}</del>');
      case MdHighlight x: b.write('<mark>${inl(x.children)}</mark>');
      case MdSubscript x: b.write('<sub>${inl(x.children)}</sub>');
      case MdSuperscript x: b.write('<sup>${inl(x.children)}</sup>');
      case MdInlineCode c: b.write('<code>${esc(c.code)}</code>');
      case MdLink l: b.write('<a href="${esc(normalizeLinkUri(l.url))}">${inl(l.children)}</a>');
      case MdInlineImage i: b.write('<img src="${esc(normalizeLinkUri(i.path))}" alt="${esc(i.alt)}" />');
    }
  }
  return b.toString();
}

String blk(List<MdBlock> bs) {
  final b = StringBuffer();
  for (final n in bs) {
    switch (n) {
      case MdHeading h: b.write('<h${h.level}>${inl(h.content)}</h${h.level}>\n');
      case MdParagraph p: b.write('<p>${inl(p.content)}</p>\n');
      case MdBlockquote q: b.write('<blockquote>\n${blk(q.children)}</blockquote>\n');
      case MdCallout c: b.write('<blockquote>\n${blk(c.children)}</blockquote>\n');
      case MdCodeBlock c:
        final cls = c.language == null ? '' : ' class="language-${esc(c.language!)}"';
        b.write('<pre><code$cls>${esc(c.code)}${c.code.isEmpty ? '' : '\n'}</code></pre>\n');
      case MdHorizontalRule _: b.write('<hr />\n');
      case MdImageBlock i: b.write('<p><img src="${esc(normalizeLinkUri(i.path))}" alt="${esc(i.alt)}" /></p>\n');
      case MdList l:
        final tag = l.ordered ? 'ol' : 'ul';
        final st = l.ordered && l.startNumber != 1 ? ' start="${l.startNumber}"' : '';
        b.write('<$tag$st>\n');
        for (final it in l.items) { b.write('<li>${blk(it.children)}</li>\n'); }
        b.write('</$tag>\n');
      case MdTable _: b.write('<table></table>\n');
    }
  }
  return b.toString();
}

String norm(String s) {
  var t = s.replaceAll(RegExp(r' title="[^"]*"'), '');
  if (t.contains('<li>')) t = t.replaceAll('<p>', '').replaceAll('</p>', '');
  t = t.replaceAll('\n', ' ').replaceAll(RegExp(r'\s+'), ' ').replaceAll(RegExp(r'>\s+<'), '><').trim();
  t = t.replaceAll(RegExp(r'\s+/>'), ' />').replaceAll('<br /> ', '<br />').replaceAll(' <br />', '<br />');
  t = t.replaceAllMapped(RegExp(r'<(ul|ol|blockquote|li)([^>]*)>\s+'), (m) => '<${m[1]}${m[2]}>').replaceAllMapped(RegExp(r'\s+</(ul|ol|blockquote|li)>'), (m) => '</${m[1]}>');
  return t;
}

