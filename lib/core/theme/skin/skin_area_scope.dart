import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/theme/app_skin_tokens.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area_colors.dart';

/// Gives a page its own colors.
///
/// Everything below this widget -- the page's widgets, and also the dialogs,
/// menus and sheets it opens -- sees a theme built from that page's tokens
/// only. Nothing from another page can leak in, because each scope always
/// starts again from the app's shared theme rather than from whatever page
/// happens to be underneath it.
///
/// Wrap a page's root once (for pushed pages: inside the route's builder).
/// If the app has no skin tokens (a bare test theme) the child is returned
/// untouched.
class SkinAreaScope extends StatefulWidget {
  const SkinAreaScope({
    super.key,
    required this.area,
    required this.child,
    this.baseTheme,
  });

  final SkinArea area;
  final Widget child;

  /// Build the page from this theme instead of the ambient one. The skin
  /// editor uses it to preview the light and dark skin independently of the
  /// brightness the app is currently running in.
  final ThemeData? baseTheme;

  /// The colors of the page that [context] is inside, or null on a page that
  /// uses the shared palette.
  static SkinAreaColors? maybeColorsOf(BuildContext context) =>
      _SkinAreaMarker.maybeOf(context)?.colors;

  /// Like [maybeColorsOf], but does not subscribe [context] to changes. For
  /// code that inspects an arbitrary element once (the skin editor's element
  /// picker) rather than building from it.
  static SkinAreaColors? peekColorsOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_SkinAreaMarker>()?.colors;

  /// The resolved color of [token] on the current page, or [fallback] when the
  /// context is not inside a [SkinAreaScope].
  static Color colorOf(
    BuildContext context,
    SkinToken token, {
    required Color fallback,
  }) => maybeColorsOf(context)?.color(token) ?? fallback;

  @override
  State<SkinAreaScope> createState() => _SkinAreaScopeState();
}

class _SkinAreaScopeState extends State<SkinAreaScope> {
  ThemeData? _builtFrom;
  SkinAreaColors? _builtColors;
  ThemeData? _scoped;

  @override
  Widget build(BuildContext context) {
    final marker = _SkinAreaMarker.maybeOf(context);
    // Always derive from the shared theme, never from an enclosing page.
    final base = widget.baseTheme ?? marker?.baseTheme ?? Theme.of(context);
    final tokens = base.extension<AppSkinTokens>();
    if (tokens == null) return widget.child;

    final colors = tokens.areaColors(widget.area);
    if (_scoped == null ||
        !identical(_builtFrom, base) ||
        _builtColors != colors) {
      _scoped = buildSkinAreaTheme(base, colors);
      _builtFrom = base;
      _builtColors = colors;
    }
    return _SkinAreaMarker(
      colors: colors,
      baseTheme: base,
      child: Theme(data: _scoped!, child: widget.child),
    );
  }
}

/// Records which page a subtree belongs to. It is an [InheritedTheme] so that
/// dialogs, menus and sheets (which re-create the themes above them in the
/// overlay) keep knowing which page opened them.
class _SkinAreaMarker extends InheritedTheme {
  const _SkinAreaMarker({
    required this.colors,
    required this.baseTheme,
    required super.child,
  });

  final SkinAreaColors colors;
  final ThemeData baseTheme;

  static _SkinAreaMarker? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SkinAreaMarker>();

  @override
  Widget wrap(BuildContext context, Widget child) =>
      _SkinAreaMarker(colors: colors, baseTheme: baseTheme, child: child);

  @override
  bool updateShouldNotify(_SkinAreaMarker oldWidget) =>
      colors != oldWidget.colors || !identical(baseTheme, oldWidget.baseTheme);
}

/// Tells the skin editor's element picker which page a subtree is, for pages
/// that paint their own theme instead of using a [SkinAreaScope] (the text
/// editor). It changes no color and no widget behavior.
class SkinAreaHint extends InheritedWidget {
  final SkinArea area;

  const SkinAreaHint({super.key, required this.area, required super.child});

  /// The hinted page above [context], without subscribing to it.
  static SkinArea? peek(BuildContext context) =>
      context.getInheritedWidgetOfExactType<SkinAreaHint>()?.area;

  @override
  bool updateShouldNotify(SkinAreaHint oldWidget) => area != oldWidget.area;
}
