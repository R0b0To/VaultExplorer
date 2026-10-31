import 'dart:ui' show Color;

/// Reading themes for the EPUB reader. [original] leaves the publisher's
/// colours alone and only adds layout rules.
enum EpubTheme { original, light, dark, sepia }

class EpubPalette {
  final Color background;
  final Color text;
  final Color link;
  const EpubPalette(this.background, this.text, this.link);
}

/// `null` for [EpubTheme.original] (no colour overrides).
EpubPalette? epubPaletteFor(EpubTheme theme) => switch (theme) {
      EpubTheme.original => null,
      EpubTheme.light =>
        const EpubPalette(Color(0xFFFFFFFF), Color(0xFF1A1A1A), Color(0xFF1A56DB)),
      EpubTheme.dark =>
        const EpubPalette(Color(0xFF121212), Color(0xFFE0E0E0), Color(0xFF8AB4F8)),
      EpubTheme.sepia =>
        const EpubPalette(Color(0xFFF4ECD8), Color(0xFF5B4636), Color(0xFF8A4B14)),
    };

/// Window colour behind the page, so there is no white flash while a chapter
/// loads in a dark theme.
Color epubBackgroundFor(EpubTheme theme) =>
    epubPaletteFor(theme)?.background ?? const Color(0xFFFFFFFF);

String _hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

/// CSS injected into every chapter by the native side, after its own base
/// rules (images capped to the screen width, long words allowed to break).
///
/// Colour rules use `!important` and inherit down the tree on purpose: a
/// publisher's "black text" inside a dark theme would otherwise be unreadable.
/// No `&`, `<` or quotes: the text is placed inside an XHTML `<style>`.
String epubStyleCss(EpubTheme theme) {
  final css = StringBuffer(
    'body{margin:0 auto!important;padding:.8em 5%!important;'
    'max-width:46em;line-height:1.55}',
  );
  final palette = epubPaletteFor(theme);
  if (palette != null) {
    css
      ..write('html,body{background:${_hex(palette.background)}!important;'
          'color:${_hex(palette.text)}!important}')
      ..write('body *:not(a):not(img):not(svg){color:inherit!important;'
          'background-color:transparent!important}')
      ..write('a,a *{color:${_hex(palette.link)}!important}');
  }
  return css.toString();
}

const int kEpubTextZoomMin = 70;
const int kEpubTextZoomMax = 250;
const int kEpubTextZoomStep = 10;
const int kEpubTextZoomDefault = 100;
