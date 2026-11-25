import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/browser/widgets/preview_pane_content.dart';

void main() {
  group('previewPaneKindFor', () {
    test('media keeps its dedicated previews', () {
      expect(previewPaneKindFor('a.png'), PreviewPaneKind.image);
      expect(previewPaneKindFor('a.mkv'), PreviewPaneKind.video);
      expect(previewPaneKindFor('a.MP3'), PreviewPaneKind.audio);
      expect(previewPaneKindFor('a.flac'), PreviewPaneKind.audio);
    });

    test('text-like kinds are previewed as text', () {
      for (final name in [
        'notes.txt',
        'README.md',
        'main.dart',
        'config.json',
        'page.html',
        'sub.srt',
        'data.csv',
        'data.TSV',
      ]) {
        expect(previewPaneKindFor(name), PreviewPaneKind.text, reason: name);
      }
    });

    test('unknown extensions are sniffed, not assumed to be text', () {
      expect(previewPaneKindFor('Makefile'), PreviewPaneKind.unknownText);
      expect(previewPaneKindFor('x.gitignore'), PreviewPaneKind.unknownText);
    });

    test('fonts get a specimen', () {
      expect(previewPaneKindFor('a.ttf'), PreviewPaneKind.font);
      expect(previewPaneKindFor('a.OTF'), PreviewPaneKind.font);
    });

    test('secrets and binary kinds are never previewed', () {
      for (final name in [
        'Bank.password',
        'Visa.paymentCard',
        'a.vxenc',
        'a.aes',
        'a.kdbx',
        'a.pem',
        'a.zip',
        'a.pdf',
        'a.sqlite',
      ]) {
        expect(previewPaneKindFor(name), PreviewPaneKind.none, reason: name);
      }
    });
  });

  group('decodePreviewText', () {
    Uint8List b(List<int> v) => Uint8List.fromList(v);

    test('decodes UTF-8 and normalises CRLF', () {
      expect(
        decodePreviewText(b(utf8.encode('a\r\nb')), truncated: false),
        'a\nb',
      );
    });

    test('strips a UTF-8 BOM', () {
      expect(
        decodePreviewText(b([0xEF, 0xBB, 0xBF, 0x68, 0x69]), truncated: false),
        'hi',
      );
    });

    test('decodes BOM-marked UTF-16 in both byte orders', () {
      expect(
        decodePreviewText(b([0xFF, 0xFE, 0x68, 0, 0x69, 0]), truncated: false),
        'hi',
      );
      expect(
        decodePreviewText(b([0xFE, 0xFF, 0, 0x68, 0, 0x69]), truncated: false),
        'hi',
      );
    });

    test('drops a multi-byte character cut by the read limit', () {
      final bytes = utf8.encode('ab€');
      final cut = b(bytes.sublist(0, bytes.length - 1));
      expect(decodePreviewText(cut, truncated: true), 'ab');
      expect(decodePreviewText(b(bytes), truncated: true), 'ab€');
    });

    test('rejects binary data', () {
      expect(decodePreviewText(b([0x89, 0x50, 0, 0x47]), truncated: false), isNull);
      expect(decodePreviewText(Uint8List(0), truncated: false), isNull);
    });

    test('strict mode rejects mostly-invalid UTF-8', () {
      final latin1 = b(List<int>.filled(200, 0xE9));
      expect(decodePreviewText(latin1, truncated: false), isNotNull);
      expect(decodePreviewText(latin1, truncated: false, strict: true), isNull);
    });
  });
}
