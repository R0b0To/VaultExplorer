import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/browser/viewer/books/epub_style.dart';

void main() {
  test('the original theme adds layout rules but no colour overrides', () {
    final css = epubStyleCss(EpubTheme.original);
    expect(css, contains('max-width'));
    expect(css, isNot(contains('color')));
    expect(epubPaletteFor(EpubTheme.original), isNull);
  });

  test('themed CSS forces the palette and inherits colour down the tree', () {
    final css = epubStyleCss(EpubTheme.dark);
    expect(css, contains('background:#121212!important'));
    expect(css, contains('color:#e0e0e0!important'));
    expect(css, contains('color:inherit!important'));
    expect(css, contains('a,a *{color:#8ab4f8!important}'));
  });

  test('every theme is safe to inline in an XHTML style element', () {
    for (final theme in EpubTheme.values) {
      final css = epubStyleCss(theme);
      expect(css.contains('&'), isFalse, reason: '$theme');
      expect(css.contains('<'), isFalse, reason: '$theme');
      expect(css.contains('"'), isFalse, reason: '$theme');
    }
  });

  test('window background matches the theme so chapters do not flash white', () {
    expect(epubBackgroundFor(EpubTheme.dark), const Color(0xFF121212));
    expect(epubBackgroundFor(EpubTheme.sepia), const Color(0xFFF4ECD8));
    expect(epubBackgroundFor(EpubTheme.original), const Color(0xFFFFFFFF));
  });
}
