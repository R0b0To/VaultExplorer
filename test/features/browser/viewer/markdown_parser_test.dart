import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/browser/viewer/markdown/markdown_ast.dart';
import 'package:vaultexplorer/features/browser/viewer/markdown/markdown_parser.dart';

// Small serializer so the assertions read as "markdown in, HTML-ish out".

String _esc(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

String _inl(List<MdInline> nodes) {
  final b = StringBuffer();
  for (final n in nodes) {
    switch (n) {
      case MdText t:
        b.write(_esc(t.text));
      case MdLineBreak _:
        b.write('<br>');
      case MdBold x:
        b.write('<b>${_inl(x.children)}</b>');
      case MdItalic x:
        b.write('<i>${_inl(x.children)}</i>');
      case MdUnderline x:
        b.write('<u>${_inl(x.children)}</u>');
      case MdStrikethrough x:
        b.write('<s>${_inl(x.children)}</s>');
      case MdHighlight x:
        b.write('<mark>${_inl(x.children)}</mark>');
      case MdSubscript x:
        b.write('<sub>${_inl(x.children)}</sub>');
      case MdSuperscript x:
        b.write('<sup>${_inl(x.children)}</sup>');
      case MdInlineCode c:
        b.write('<code>${_esc(c.code)}</code>');
      case MdLink l:
        b.write('<a ${l.url}${l.title == null ? '' : ' "${l.title}"'}>${_inl(l.children)}</a>');
      case MdInlineImage i:
        b.write('<img ${i.path} "${i.alt}"${i.title == null ? '' : ' "${i.title}"'}>');
      case MdHtmlInline h:
        b.write('{${h.html}}');
    }
  }
  return b.toString();
}

String _blk(List<MdBlock> blocks) {
  final b = StringBuffer();
  for (final n in blocks) {
    switch (n) {
      case MdHeading h:
        b.write('<h${h.level}>${_inl(h.content)}</h${h.level}>');
      case MdParagraph p:
        b.write('<p>${_inl(p.content)}</p>');
      case MdBlockquote q:
        b.write('<quote>${_blk(q.children)}</quote>');
      case MdCallout c:
        b.write(
          '<callout ${c.type} "${c.title}"${c.collapsible ? (c.defaultCollapsed ? ' closed' : ' open') : ''}>'
          '${_blk(c.children)}</callout>',
        );
      case MdCodeBlock c:
        b.write('<pre${c.language == null ? '' : ' ${c.language}'}>${_esc(c.code)}</pre>');
      case MdHorizontalRule _:
        b.write('<hr>');
      case MdImageBlock i:
        b.write('<imgblock ${i.path} "${i.alt}"${i.title == null ? '' : ' "${i.title}"'}>');
      case MdHtmlBlock h:
        b.write('<html>${h.html}</html>');
      case MdList l:
        final tag = l.ordered ? 'ol${l.startNumber == 1 ? '' : ' ${l.startNumber}'}' : 'ul';
        b.write('<$tag${l.tight ? '' : ' loose'}>');
        for (final it in l.items) {
          final box = it.checked == null ? '' : (it.checked! ? '[x]' : '[ ]');
          b.write('<li>$box${_blk(it.children)}</li>');
        }
        b.write('</${l.ordered ? 'ol' : 'ul'}>');
      case MdTable t:
        b.write('<table ${t.alignments.map((a) => a.name).join(',')}>');
        b.write('<head ${t.headerCells.map(_inl).join('|')}>');
        for (final r in t.rows) {
          b.write('<row ${r.map(_inl).join('|')}>');
        }
        b.write('</table>');
    }
  }
  return b.toString();
}

String md(String source) => _blk(parseMarkdownDocument(source));

/// The strict CommonMark profile (what the spec conformance run uses).
String mdStrict(String source) =>
    _blk(parseMarkdownDocument(source, options: MdParseOptions.commonMark));

void main() {
  group('emphasis follows the flanking rules', () {
    test('snake_case and SCREAMING_SNAKE identifiers are plain text', () {
      expect(md('snake_case_identifier'), '<p>snake_case_identifier</p>');
      expect(md('UNLOCK_VAULT then LOCK_VAULT'), '<p>UNLOCK_VAULT then LOCK_VAULT</p>');
      expect(md('5_6_78'), '<p>5_6_78</p>');
      expect(md('REPORT_2024_*.xlsx'), '<p>REPORT_2024_*.xlsx</p>');
    });

    test('globs and stray asterisks stay literal', () {
      expect(md('match **/*.pdf here'), '<p>match **/*.pdf here</p>');
      expect(md('a * b * c'), '<p>a * b * c</p>');
      expect(md('2 * 3 = 6'), '<p>2 * 3 = 6</p>');
    });

    test('real emphasis still works, including intraword asterisks', () {
      expect(md('*a* and _b_'), '<p><i>a</i> and <i>b</i></p>');
      expect(md('**a** and __b__'), '<p><b>a</b> and <b>b</b></p>');
      expect(md('un*frigging*believable'), '<p>un<i>frigging</i>believable</p>');
      expect(md('***both***'), '<p><i><b>both</b></i></p>');
      expect(md('__init__'), '<p><b>init</b></p>');
    });

    test('extensions: highlight and strikethrough', () {
      expect(md('==hi== and ~~gone~~'), '<p><mark>hi</mark> and <s>gone</s></p>');
      expect(md('a == b'), '<p>a == b</p>');
    });
  });

  group('headings', () {
    test('setext headings', () {
      expect(md('Title\n====='), '<h1>Title</h1>');
      expect(md('Sub\n---'), '<h2>Sub</h2>');
      expect(md('Multi\nline\n---'), '<h2>Multi line</h2>');
    });

    test('ATX headings with closing hashes', () {
      expect(md('## Hi ##'), '<h2>Hi</h2>');
      expect(md('#NoSpace'), '<p>#NoSpace</p>');
    });
  });

  group('lists', () {
    test('nesting, tight and loose', () {
      expect(md('- a\n  - b\n    - c\n- d'), '<ul><li><p>a</p><ul><li><p>b</p><ul><li><p>c</p></li></ul></li></ul></li><li><p>d</p></li></ul>');
      expect(md('- a\n\n- b'), '<ul loose><li><p>a</p></li><li><p>b</p></li></ul>');
    });

    test('ordered start numbers; a bullet list reports 1', () {
      expect(md('3. a\n4. b'), '<ol 3><li><p>a</p></li><li><p>b</p></li></ol>');
      expect(parseMarkdownDocument('- a').single, isA<MdList>());
      expect((parseMarkdownDocument('- a').single as MdList).startNumber, 1);
    });

    test('an unindented line continues the item paragraph (lazy continuation)', () {
      expect(md('- one\ntwo'), '<ul><li><p>one two</p></li></ul>');
      expect(md('- one\n  two'), '<ul><li><p>one two</p></li></ul>');
    });

    test('switching bullet type starts a new list', () {
      expect(md('- a\n+ b'), '<ul><li><p>a</p></li></ul><ul><li><p>b</p></li></ul>');
      expect(md('- a\n1. b'), '<ul><li><p>a</p></li></ul><ol><li><p>b</p></li></ol>');
    });

    test('code and quotes inside an item', () {
      expect(
        md('1. step\n\n   ```sh\n   run\n   ```\n\n   > note'),
        '<ol loose><li><p>step</p><pre sh>run</pre><quote><p>note</p></quote></li></ol>',
      );
    });

    test('task items', () {
      expect(md('- [ ] open\n- [x] done\n- [X] caps\n- plain'),
          '<ul><li>[ ]<p>open</p></li><li>[x]<p>done</p></li><li>[x]<p>caps</p></li><li><p>plain</p></li></ul>');
      expect(md('- [x]nospace'), '<ul><li><p>[x]nospace</p></li></ul>');
    });
  });

  group('block quotes and callouts', () {
    test('a blank line ends a quote', () {
      expect(md('> a\n\n> b'), '<quote><p>a</p></quote><quote><p>b</p></quote>');
      expect(md('> a\n> b'), '<quote><p>a b</p></quote>');
    });

    test('lazy continuation inside a quote', () {
      expect(md('> a\nb'), '<quote><p>a b</p></quote>');
    });

    test('callouts: type, title, fold state, body blocks', () {
      expect(md('> [!note] Heads up\n> body'), '<callout note "Heads up"><p>body</p></callout>');
      expect(md('> [!warning]-\n> hidden'), '<callout warning "" closed><p>hidden</p></callout>');
      expect(md('> [!tip]+ Open\n> - a'), '<callout tip "Open" open><ul><li><p>a</p></li></ul></callout>');
    });

    test('adjacent callouts stay separate', () {
      expect(md('> [!note] A\n> a\n\n> [!note] B\n> b'),
          '<callout note "A"><p>a</p></callout><callout note "B"><p>b</p></callout>');
    });

    test('a plain quote that merely mentions [!x] is still a quote', () {
      expect(md('> [!note]text'), '<quote><p>[!note]text</p></quote>');
    });
  });

  group('code', () {
    test('fenced, with language and tilde fences', () {
      expect(md('```dart\nvoid main() {}\n```'), '<pre dart>void main() {}</pre>');
      expect(md('~~~\nx\n~~~'), '<pre>x</pre>');
      expect(md('````\n```\n````'), '<pre>```</pre>');
    });

    test('an unclosed fence runs to the end of the document', () {
      expect(md('```\na\n\nb'), '<pre>a\n\nb</pre>');
    });

    test('indented code, including tabs', () {
      expect(md('    a\n    b'), '<pre>a\nb</pre>');
      expect(md('\ta'), '<pre>a</pre>');
      // Two tabs = 8 columns; the item's content starts at column 2, so the
      // code block starts at column 6 and keeps the 2 columns beyond it.
      expect(md('- a\n\n\t\tcode'), '<ul loose><li><p>a</p><pre>  code</pre></li></ul>');
    });

    test('info string resolves escapes and entities', () {
      expect(md('``` f&ouml;&ouml;\nx\n```'), '<pre föö>x</pre>');
    });

    test('code spans', () {
      expect(md('`` a`b ``'), '<p><code>a`b</code></p>');
      expect(md('`a  b`'), '<p><code>a  b</code></p>');
      expect(md('`unclosed'), '<p>`unclosed</p>');
    });
  });

  group('links', () {
    test('reference links, images, collapsed and shortcut forms', () {
      expect(md('[a][x] [x][] [x]\n\n[x]: /u "T"'), '<p><a /u "T">a</a> <a /u "T">x</a> <a /u "T">x</a></p>');
      expect(md('![alt][x]\n\n[x]: /p.png'), '<imgblock /p.png "alt">');
    });

    test('labels are case-insensitive and whitespace-collapsed', () {
      expect(md('[Foo   Bar]\n\n[foo bar]: /u'), '<p><a /u>Foo   Bar</a></p>');
    });

    test('definitions are not rendered; a later duplicate loses', () {
      expect(md('[a]: /1\n[a]: /2\n\n[a]'), '<p><a /1>a</a></p>');
    });

    test('an undefined reference stays as text', () {
      expect(md('[nope] and [nope][none]'), '<p>[nope] and [nope][none]</p>');
    });

    test('links cannot nest; images can sit inside links', () {
      expect(md('[a [b](/b) c](/a)'), '<p>[a <a /b>b</a> c](/a)</p>');
      expect(md('[![i](/i.png)](/l)'), '<p><a /l><img /i.png "i"></a></p>');
    });

    test('autolinks and bare URLs', () {
      expect(md('<https://a.b/c>'), '<p><a https://a.b/c>https://a.b/c</a></p>');
      expect(md('<me@x.org>'), '<p><a mailto:me@x.org>me@x.org</a></p>');
      expect(md('see https://a.b/c_d, ok'), '<p>see <a https://a.b/c_d>https://a.b/c_d</a>, ok</p>');
    });
  });

  group('images', () {
    test('an image on its own line is an image block', () {
      expect(md('![a](<my image.png>)'), '<imgblock my image.png "a">');
    });

    test('consecutive image lines become one block each', () {
      expect(md('![a](a.png)\n![b](b.png)'), '<imgblock a.png "a"><imgblock b.png "b">');
    });

    test('an image mixed with text stays inline', () {
      expect(md('see ![a](a.png) here'), '<p>see <img a.png "a"> here</p>');
    });
  });

  group('tables', () {
    test('alignment, escaped pipes, short rows padded, inline markup in cells', () {
      expect(
        md('| A | B | C |\n|:--|:-:|--:|\n| a_b_c | **x** | 1 \\| 2 |\n| short |'),
        '<table left,center,right><head A|B|C><row a_b_c|<b>x</b>|1 | 2><row short||></table>',
      );
    });

    test('a pipe in plain text is not a table', () {
      expect(md('a | b\nc'), '<p>a | b c</p>');
    });

    test('a paragraph before the header row is kept', () {
      expect(md('intro\n| A |\n|---|\n| 1 |'), '<p>intro</p><table none><head A><row 1></table>');
    });
  });

  group('raw HTML in a native viewer', () {
    test('comments are invisible; text sharing their line is not', () {
      expect(md('<!-- hidden -->'), '');
      expect(md('a\n\n<!-- x -->\n\nb'), '<p>a</p><p>b</p>');
      expect(md('<!-- x --> text'), '<p>text</p>');
    });

    test('<hr> is a rule', () {
      expect(md('<hr>'), '<hr>');
      expect(md('<hr />'), '<hr>');
    });

    test('tags are kept as written and never parsed as markdown', () {
      expect(md('<img src="my_img_v2.png" alt="*x*">'), '<p>&lt;img src="my_img_v2.png" alt="*x*"&gt;</p>');
    });

    test('formatting tags still format', () {
      expect(md('<b>x</b> <u>y</u> H<sub>2</sub>O x<sup>2</sup> <a href="/u">l</a>'),
          '<p><b>x</b> <u>y</u> H<sub>2</sub>O x<sup>2</sup> <a /u>l</a></p>');
      expect(md('a<br>b'), '<p>a<br>b</p>');
    });

    test('a comment between two lists keeps them separate', () {
      expect(md('- a\n\n<!-- -->\n\n- b'), '<ul><li><p>a</p></li></ul><ul><li><p>b</p></li></ul>');
    });
  });

  group('inline details', () {
    test('hard and soft line breaks', () {
      expect(md('a  \nb'), '<p>a<br>b</p>');
      expect(md('a\\\nb'), '<p>a<br>b</p>');
      expect(md('a\nb'), '<p>a b</p>');
      expect(md('a \nb'), '<p>a b</p>');
    });

    test('backslash escapes and character references', () {
      expect(md(r'\*not\* \[x\] \& \<'), '<p>*not* [x] &amp; &lt;</p>');
      expect(md('&copy; &#35; &#x41; &nope;'), '<p>© # A &amp;nope;</p>');
    });

    test('thematic breaks', () {
      expect(md('---'), '<hr>');
      expect(md('* * *'), '<hr>');
      expect(md('a\n---'), '<h2>a</h2>');
    });
  });

  group('source lines', () {
    test('blocks report the zero-based line they start on', () {
      final blocks = parseMarkdownDocument('# h\n\npara\n\n- item\n- item2\n\n```\ncode\n```');
      expect(blocks.map((b) => b.sourceLine).toList(), [0, 2, 4, 7]);
      final list = blocks[2] as MdList;
      expect(list.items.map((i) => i.sourceLine).toList(), [4, 5]);
    });
  });

  group('titles', () {
    test('inline links and images keep their title', () {
      expect(md('[a](/u "T") ![i](/p.png \'P\')'), '<p><a /u "T">a</a> <img /p.png "i" "P"></p>');
    });

    test('a reference definition supplies the title', () {
      expect(md('[a]\n\n[a]: /u (T)'), '<p><a /u "T">a</a></p>');
      expect(md('![a]\n\n[a]: /p.png "P"'), '<imgblock /p.png "a" "P">');
    });

    test('a title not alone on its line is dropped, the definition survives', () {
      expect(md('[a]\n\n[a]: /u "T" junk'), '<p>[a]</p><p>[a]: /u "T" junk</p>');
      expect(md('[a]\n\n[a]: /u\n"T" junk'), '<p><a /u>a</a></p><p>"T" junk</p>');
    });
  });

  group('the strict CommonMark profile', () {
    test('raw HTML is kept as written, not interpreted', () {
      expect(mdStrict('<div>\n*x*\n</div>'), '<html><div>\n*x*\n</div></html>');
      expect(mdStrict('a <b>x</b> <!-- c -->'), '<p>a {<b>}x{</b>} {<!-- c -->}</p>');
      expect(mdStrict('<img src="my_img_v2.png">'), '<html><img src="my_img_v2.png"></html>');
    });

    test('the app profile interprets the same input', () {
      expect(md('a <b>x</b> <!-- c -->'), '<p>a <b>x</b> </p>');
    });

    test('plain URLs are not linked', () {
      expect(mdStrict('see https://a.b/c'), '<p>see https://a.b/c</p>');
      expect(md('see https://a.b/c'), '<p>see <a https://a.b/c>https://a.b/c</a></p>');
    });

    test('soft breaks are newlines, not spaces', () {
      expect(mdStrict('a\nb'), '<p>a\nb</p>');
      expect(md('a\nb'), '<p>a b</p>');
    });

    test('spaces in an image destination are not accepted', () {
      expect(mdStrict('![a](my file.png)'), '<p>![a](my file.png)</p>');
      expect(md('![a](my file.png)'), '<imgblock my file.png "a">');
    });
  });

  group('character references', () {
    test('the full HTML5 table, including two-code-point names', () {
      expect(md('&ngE; &HilbertSpace; &ClockwiseContourIntegral; &AElig;'), '<p>\u2267\u0338 \u210B \u2232 \u00C6</p>');
      expect(md('&#35; &#x1F600; &#0; &nope; &amp;'), '<p># \u{1F600} \uFFFD &amp;nope; &amp;</p>');
    });
  });

  group('reference label matching uses Unicode case folding', () {
    test('sharp s, final sigma, and newer Unicode', () {
      expect(md('[\u1E9E]\n\n[SS]: /u'), '<p><a /u>\u1E9E</a></p>');
      expect(md('[\u00DF]\n\n[ss]: /u'), '<p><a /u>\u00DF</a></p>');
      expect(md('[\u03A3\u0391\u03A3]\n\n[\u03C3\u03B1\u03C2]: /u'), '<p><a /u>\u03A3\u0391\u03A3</a></p>');
      expect(md('[\u10D0]\n\n[\u1C90]: /u'), '<p><a /u>\u10D0</a></p>'); // Georgian
    });

    test('distinct letters stay distinct (Turkish dotless i)', () {
      expect(md('[\u0131]\n\n[I]: /u'), '<p>[\u0131]</p>');
    });
  });

  group('robustness', () {
    test('degenerate input does not throw or hang', () {
      for (final s in ['', '\n\n', '>', '- ', '1.', '[', ']', '![', '`', '<', '&', '|', '|-|', '\u0000', '> > > > >', '- - - - -', '*' * 500, '[' * 300 + ']' * 300, '_' * 301 + 'a']) {
        expect(() => parseMarkdownDocument(s), returnsNormally, reason: s.length > 20 ? 'len ${s.length}' : s);
      }
    });

    test('CRLF and CR line endings', () {
      expect(md('a\r\nb\r\n\r\nc'), '<p>a b</p><p>c</p>');
      expect(md('a\rb'), '<p>a b</p>');
    });
  });
}
