import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/browser/viewer/markdown/markdown_ast.dart';
import 'package:vaultexplorer/features/browser/viewer/markdown/markdown_inline_parser.dart';
import 'package:vaultexplorer/features/browser/viewer/markdown/markdown_link_syntax.dart';
import 'package:vaultexplorer/features/browser/viewer/markdown/markdown_parser.dart';

/// Destination of the first link in [source], or null when there is none.
String? _dest(String source) {
  for (final node in parseInline(source)) {
    if (node is MdLink) return node.url;
  }
  return null;
}

void main() {
  group('inline link destinations - CommonMark 0.31.2 examples 482-500', () {
    final cases = <String, String?>{
      // 482-487: title / text / destination may be omitted
      '[link](/uri "title")': '/uri',
      '[link](/uri)': '/uri',
      '[](./target.md)': './target.md',
      '[link]()': '',
      '[link](<>)': '',
      '[]()': '',
      // 489: spaces only inside <...>
      '[link](</my uri>)': '/my uri',
      // 490-491: no line endings in a destination
      '[link](foo\nbar)': null,
      '[link](<foo\nbar>)': null,
      // 492-494: ) inside <...>, escaped >, unmatched <
      '[a](<b)c>)': 'b)c',
      r'[link](<foo\>)': null,
      '[a](<b)c': null,
      '[a](<b)c>': null,
      '[a](<b>c)': null,
      // 495-500: parentheses and escapes
      r'[link](\(foo\))': '(foo)',
      '[link](foo(and(bar)))': 'foo(and(bar))',
      '[link](foo(and(bar))': null,
      r'[link](foo\(and\(bar\))': 'foo(and(bar)',
      '[link](<foo(and(bar)>)': 'foo(and(bar)',
      r'[link](foo\)\:)': 'foo):',
      // titles
      "[a](b 't')": 'b',
      '[a](b (t))': 'b',
      '[a](b"t")': 'b"t"',
      // whitespace around the destination
      '[a](  b  )': 'b',
      '[a](\n  b\n)': 'b',
    };

    cases.forEach((source, expected) {
      test(source.replaceAll('\n', r'\n'), () {
        expect(_dest(source), expected);
      });
    });

    test('example 488: a bare destination with a space is not a link', () {
      // Only true while the legacy fallback (kAcceptLegacySpacedDestinations)
      // is switched off; with it on, old notes keep rendering.
      if (kAcceptLegacySpacedDestinations) {
        expect(_dest('[link](/my uri)'), '/my uri');
      } else {
        expect(_dest('[link](/my uri)'), isNull);
      }
    });

    test('a title with an unescaped ( is not a title', () {
      // Strictly this is not a link; the legacy fallback reads it the way the
      // old parser did (the whole text up to the last ")" is the path).
      expect(
        _dest('[a](b (t(x)))'),
        kAcceptLegacySpacedDestinations ? 'b (t(x))' : isNull,
      );
    });

    test('the legacy fallback never loosens any other rule', () {
      expect(_dest('[a](<b c)'), isNull);
      expect(_dest('[a](foo(and(bar))'), isNull);
    });
  });

  group('writing destinations', () {
    test('spaces become %20, the rest stays readable', () {
      expect(
        markdownImageTemplate(alt: 'my image.png', path: 'sub dir/my image.png'),
        '![my image.png](sub%20dir/my%20image.png)',
      );
      expect(
        markdownImageTemplate(alt: 'a b.png', path: '../img/a b.png'),
        '![a b.png](../img/a%20b.png)',
      );
      expect(encodeMarkdownDestination('写真 1.png'), '写真%201.png');
    });

    test('characters that would end or change the destination', () {
      expect(encodeMarkdownDestination('a (1).png'), 'a%20%281%29.png');
      expect(encodeMarkdownDestination('100%.png'), '100%25.png');
      expect(encodeMarkdownDestination('C#?.png'), 'C%23%3F.png');
      expect(encodeMarkdownDestination(r'a\b.png'), 'a%5Cb.png');
      expect(encodeMarkdownDestination('<x>.png'), '%3Cx%3E.png');
    });

    test('alt text escapes brackets but keeps intraword underscores', () {
      expect(escapeMarkdownLinkText('a[1].png'), r'a\[1\].png');
      expect(escapeMarkdownLinkText('IMG_2024.png'), 'IMG_2024.png');
      expect(escapeMarkdownLinkText('_x.png'), r'\_x.png');
    });

    test('every written link parses back to the exact original name', () {
      const names = [
        'my image.png',
        'a (1).png',
        'a)b.png',
        'a(b.png',
        '100%.png',
        '100%20.png',
        'C#?x.png',
        r'a\b.png',
        '<x>.png',
        'tab\there.png',
        '写真 1.png',
        'é à.png',
        'a [b].png',
        'a"b\'c.png',
        'x  y.png',
        ' lead.png',
        'trail .png',
        'a%zz.png',
        '😀 smile.png',
      ];
      for (final name in names) {
        final path = 'dir x/$name';
        final written = markdownImageTemplate(alt: name, path: path);
        final nodes = parseInline(written);
        expect(nodes, hasLength(1), reason: written);
        final image = nodes.single as MdInlineImage;
        expect(decodeLinkPath(image.path), path, reason: written);
        expect(image.alt, name, reason: written);
      }
    });
  });

  group('decodeLinkPath', () {
    test('decodes percent escapes', () {
      expect(decodeLinkPath('my%20image.png'), 'my image.png');
      expect(decodeLinkPath('%E5%86%99%E7%9C%9F.png'), '写真.png');
      expect(decodeLinkPath('100%25.png'), '100%.png');
    });

    test('leaves malformed escapes as written instead of throwing', () {
      expect(decodeLinkPath('100%.png'), '100%.png');
      expect(decodeLinkPath('a%C3%28.png'), 'a%C3%28.png');
      expect(decodeLinkPath('a%zz.png'), 'a%zz.png');
    });
  });

  group('normalizeLinkUri', () {
    test('encodes what a URI cannot hold, without double-encoding', () {
      expect(normalizeLinkUri('/my uri'), '/my%20uri');
      expect(normalizeLinkUri('/my%20uri'), '/my%20uri');
      expect(normalizeLinkUri('100%'), '100%25');
      expect(normalizeLinkUri('a%4'), 'a%254');
      expect(normalizeLinkUri('/é'), '/%C3%A9');
    });

    test('keeps ordinary URLs untouched', () {
      const url = 'https://example.com/a?b=c&d=e#frag';
      expect(normalizeLinkUri(url), url);
      expect(normalizeLinkUri('mailto:a@b.co'), 'mailto:a@b.co');
    });
  });

  group('parser integration', () {
    MdImageBlock imageBlock(String source) {
      final blocks = parseMarkdownDocument(source);
      expect(blocks, hasLength(1), reason: source);
      expect(blocks.single, isA<MdImageBlock>(), reason: source);
      return blocks.single as MdImageBlock;
    }

    test('standalone image: <...> destination with spaces', () {
      final image = imageBlock('![a](<my image.png>)');
      expect(image.alt, 'a');
      expect(image.path, 'my image.png');
    });

    test('standalone image: percent-encoded destination is kept encoded', () {
      // Decoding happens when the path is resolved against the vault.
      expect(imageBlock('![a](my%20image.png)').path, 'my%20image.png');
    });

    test('standalone image: parentheses in the file name', () {
      expect(imageBlock('![a](x%20%281%29.png)').path, 'x%20%281%29.png');
      expect(imageBlock('![a](<x (1).png>)').path, 'x (1).png');
    });

    test('standalone image: title is not part of the path', () {
      expect(imageBlock('![a](x.png "Title")').path, 'x.png');
    });

    test('standalone image: escaped alt text is unescaped', () {
      expect(imageBlock(r'![a\[1\].png](a[1].png)').alt, 'a[1].png');
    });

    test('a line with text after the image is a paragraph, not an image', () {
      final blocks = parseMarkdownDocument('![a](x.png) tail');
      expect(blocks.single, isA<MdParagraph>());
    });

    test('inline links and images share the same destination rules', () {
      final nodes = parseInline('see [doc](<my notes.md>) and ![p](a%20b.png)');
      final link = nodes.whereType<MdLink>().single;
      final image = nodes.whereType<MdInlineImage>().single;
      expect(link.url, 'my notes.md');
      expect(image.path, 'a%20b.png');
    });

    test('any ASCII punctuation can be backslash-escaped', () {
      final nodes = parseInline(r'a \& b \" c \< d');
      expect(nodes.whereType<MdText>().map((n) => n.text).join(), 'a & b " c < d');
    });
  });
}
