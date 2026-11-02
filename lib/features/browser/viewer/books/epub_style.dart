import 'dart:ui' show Color;

/// Reading themes for the EPUB reader. [original] leaves the publisher's
/// colours alone and only adds layout rules.
enum EpubTheme { original, light, dark, sepia }

enum EpubFontFace { publisher, serif, sansSerif, monospace }

enum EpubTextAlignment { publisher, left, justified, center, right }

class EpubPalette {
  final Color background;
  final Color text;
  final Color link;
  const EpubPalette(this.background, this.text, this.link);
}

/// `null` for [EpubTheme.original] (no colour overrides).
EpubPalette? epubPaletteFor(EpubTheme theme) => switch (theme) {
  EpubTheme.original => null,
  EpubTheme.light => const EpubPalette(
    Color(0xFFFFFFFF),
    Color(0xFF1A1A1A),
    Color(0xFF1A56DB),
  ),
  EpubTheme.dark => const EpubPalette(
    Color(0xFF121212),
    Color(0xFFE0E0E0),
    Color(0xFF8AB4F8),
  ),
  EpubTheme.sepia => const EpubPalette(
    Color(0xFFF4ECD8),
    Color(0xFF5B4636),
    Color(0xFF8A4B14),
  ),
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
String epubStyleCss(
  EpubTheme theme, {
  bool fixedLayout = false,
  bool paged = false,
  bool rtl = false,
  EpubFontFace fontFace = EpubFontFace.publisher,
  int fontWeight = 400,
  double lineHeight = 1.55,
  EpubTextAlignment textAlignment = EpubTextAlignment.publisher,
  bool pageMargins = true,
  bool twoPageLandscape = false,
}) {
  final css = StringBuffer();
  if (!fixedLayout && paged) {
    css.write(
      'html{box-sizing:border-box!important;width:100%!important;height:100%!important;'
      'overflow-x:auto!important;overflow-y:hidden!important}'
      'html body{display:block!important;box-sizing:border-box!important;'
      'width:100vw!important;min-width:100vw!important;height:100vh!important;min-height:100vh!important;'
      'max-width:none!important;margin:0!important;'
      'padding:${pageMargins ? '.8em 0' : '0'}!important;'
      'line-height:${lineHeight.toStringAsFixed(2)}!important;'
      'overflow-x:visible!important;overflow-y:hidden!important;'
      '-webkit-column-width:100vw!important;column-width:100vw!important;'
      '-webkit-column-count:auto!important;column-count:auto!important;'
      '-webkit-column-gap:0!important;column-gap:0!important;'
      '-webkit-column-fill:auto!important;column-fill:auto!important}'
      'html body>*{box-sizing:border-box!important;'
      'max-width:calc(100vw - ${pageMargins ? '2.4em' : '0em'})!important;'
      'margin-left:auto!important;margin-right:auto!important}',
    );
    if (twoPageLandscape) {
      css.write(
        'html body{-webkit-column-width:50vw!important;column-width:50vw!important}'
        'html body>*{max-width:calc(50vw - ${pageMargins ? '2.4em' : '0em'})!important}',
      );
    }
    if (rtl) css.write('html,body{direction:rtl}');
  } else if (!fixedLayout) {
    css.write(
      'body{box-sizing:border-box;margin:0 auto!important;'
      'padding:${pageMargins ? '.8em 5%' : '0'}!important;'
      'max-width:46em;line-height:${lineHeight.toStringAsFixed(2)}}',
    );
  }
  if (!fixedLayout) {
    final family = switch (fontFace) {
      EpubFontFace.publisher => null,
      EpubFontFace.serif => 'serif',
      EpubFontFace.sansSerif => 'sans-serif',
      EpubFontFace.monospace => 'monospace',
    };
    if (family != null) {
      css.write('body{font-family:$family!important}');
    }
    if (fontWeight != 400) {
      css.write('body{font-weight:$fontWeight!important}');
    }
    if (paged) {
      css.write('body{line-height:${lineHeight.toStringAsFixed(2)}!important}');
    }
    final alignment = switch (textAlignment) {
      EpubTextAlignment.publisher => null,
      EpubTextAlignment.left => 'left',
      EpubTextAlignment.justified => 'justify',
      EpubTextAlignment.center => 'center',
      EpubTextAlignment.right => 'right',
    };
    if (alignment != null) {
      css.write('body{text-align:$alignment!important}');
    }
  }
  final palette = epubPaletteFor(theme);
  if (palette != null) {
    css
      ..write(
        'html,body{background:${_hex(palette.background)}!important;'
        'color:${_hex(palette.text)}!important}',
      )
      ..write(
        'body *:not(a):not(img):not(svg){color:inherit!important;'
        'background-color:transparent!important}',
      )
      ..write('a,a *{color:${_hex(palette.link)}!important}');
  }
  return css.toString();
}

const int kEpubTextZoomMin = 70;
const int kEpubTextZoomMax = 250;
const int kEpubTextZoomStep = 10;
const int kEpubTextZoomDefault = 100;
