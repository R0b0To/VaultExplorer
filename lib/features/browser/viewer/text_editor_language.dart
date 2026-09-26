// Resolves a file being opened in [TextEditorScreen] to a re_highlight
// language mode, and picks one of the two bundled re_highlight color themes
// (Atom One Dark / Atom One Light) to match the app's current brightness.
//
// `re_editor`'s `CodeHighlightTheme.languages` map is meant to carry exactly
// one entry per open file -- passing more than one makes it fall back to
// `highlightAuto`, which scans every candidate and is both slower and liable
// to guess wrong for short config snippets. So this always registers at
// most one language, keyed by that language's own name.
//
// This intentionally does not yet expose the bundled Dracula/Monokai/Nord/
// GitHub themes or a user-facing theme picker -- that's `EditorThemeConfig`
// from Phase 3 of the editor expansion plan. For now the two Atom One
// variants give every recognized language sensible, readable colors that
// track the app's own dark/light setting with no extra configuration.
import 'package:material_ui/material_ui.dart';
import 'package:meta/meta.dart' show immutable;
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/bash.dart';
import 'package:re_highlight/languages/c.dart';
import 'package:re_highlight/languages/cpp.dart';
import 'package:re_highlight/languages/csharp.dart';
import 'package:re_highlight/languages/css.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/dockerfile.dart';
import 'package:re_highlight/languages/go.dart';
import 'package:re_highlight/languages/gradle.dart';
import 'package:re_highlight/languages/ini.dart';
import 'package:re_highlight/languages/java.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/kotlin.dart';
import 'package:re_highlight/languages/less.dart';
import 'package:re_highlight/languages/makefile.dart';
import 'package:re_highlight/languages/markdown.dart';
import 'package:re_highlight/languages/php.dart';
import 'package:re_highlight/languages/properties.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/languages/ruby.dart';
import 'package:re_highlight/languages/rust.dart';
import 'package:re_highlight/languages/scss.dart';
import 'package:re_highlight/languages/sql.dart';
import 'package:re_highlight/languages/swift.dart';
import 'package:re_highlight/languages/typescript.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/languages/yaml.dart';
import 'package:re_highlight/re_highlight.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:re_highlight/styles/atom-one-light.dart';

/// The [CodeHighlightThemeMode] for a single recognized language, along
/// with a short id used both as its [CodeHighlightTheme.languages] key and
/// for `flutter test`/debugging output. Not shown in the UI.
@immutable
class _LanguageMatch {
  final String id;
  final Mode mode;

  const _LanguageMatch(this.id, this.mode);
}

/// Extensionless filenames that carry a well-known format, checked before
/// falling back to extension matching -- e.g. a bare `Dockerfile` or
/// `Makefile` dropped in a vault alongside the project it configures.
final Map<String, _LanguageMatch> _filenameOverrides = {
  'dockerfile': _LanguageMatch('dockerfile', langDockerfile),
  'makefile': _LanguageMatch('makefile', langMakefile),
  'gnumakefile': _LanguageMatch('makefile', langMakefile),
};

/// Extension (without the leading dot, lower-cased) to language mode.
/// Deliberately scoped to the "configs and scripts" a vault is likely to
/// hold rather than the full ~100 languages `re_highlight` ships --
/// unrecognized extensions fall back to no highlighting at all (see
/// [resolveEditorSyntaxStyle]) rather than a wrong guess.
final Map<String, _LanguageMatch> _extensionLanguages = {
  'json': _LanguageMatch('json', langJson),
  'js': _LanguageMatch('javascript', langJavascript),
  'mjs': _LanguageMatch('javascript', langJavascript),
  'cjs': _LanguageMatch('javascript', langJavascript),
  'jsx': _LanguageMatch('javascript', langJavascript),
  'ts': _LanguageMatch('typescript', langTypescript),
  'tsx': _LanguageMatch('typescript', langTypescript),
  'html': _LanguageMatch('xml', langXml),
  'htm': _LanguageMatch('xml', langXml),
  'xhtml': _LanguageMatch('xml', langXml),
  'xml': _LanguageMatch('xml', langXml),
  'svg': _LanguageMatch('xml', langXml),
  'plist': _LanguageMatch('xml', langXml),
  'css': _LanguageMatch('css', langCss),
  'scss': _LanguageMatch('scss', langScss),
  'less': _LanguageMatch('less', langLess),
  'dart': _LanguageMatch('dart', langDart),
  'yaml': _LanguageMatch('yaml', langYaml),
  'yml': _LanguageMatch('yaml', langYaml),
  'md': _LanguageMatch('markdown', langMarkdown),
  'markdown': _LanguageMatch('markdown', langMarkdown),
  'py': _LanguageMatch('python', langPython),
  'pyw': _LanguageMatch('python', langPython),
  'sh': _LanguageMatch('bash', langBash),
  'bash': _LanguageMatch('bash', langBash),
  'zsh': _LanguageMatch('bash', langBash),
  'sql': _LanguageMatch('sql', langSql),
  'ini': _LanguageMatch('ini', langIni),
  'cfg': _LanguageMatch('ini', langIni),
  'conf': _LanguageMatch('ini', langIni),
  'properties': _LanguageMatch('properties', langProperties),
  'c': _LanguageMatch('c', langC),
  'h': _LanguageMatch('c', langC),
  'cpp': _LanguageMatch('cpp', langCpp),
  'cc': _LanguageMatch('cpp', langCpp),
  'cxx': _LanguageMatch('cpp', langCpp),
  'hpp': _LanguageMatch('cpp', langCpp),
  'java': _LanguageMatch('java', langJava),
  'kt': _LanguageMatch('kotlin', langKotlin),
  'kts': _LanguageMatch('kotlin', langKotlin),
  'gradle': _LanguageMatch('gradle', langGradle),
  'go': _LanguageMatch('go', langGo),
  'rs': _LanguageMatch('rust', langRust),
  'rb': _LanguageMatch('ruby', langRuby),
  'swift': _LanguageMatch('swift', langSwift),
  'php': _LanguageMatch('php', langPhp),
  'cs': _LanguageMatch('csharp', langCsharp),
};

_LanguageMatch? _matchFor(String filePath) {
  final slash = filePath.lastIndexOf('/');
  final fileName = slash >= 0 ? filePath.substring(slash + 1) : filePath;
  final byName = _filenameOverrides[fileName.toLowerCase()];
  if (byName != null) return byName;

  final dot = fileName.lastIndexOf('.');
  if (dot <= 0 || dot == fileName.length - 1) return null; // no/leading-only dot
  final ext = fileName.substring(dot + 1).toLowerCase();
  return _extensionLanguages[ext];
}

/// Builds the [CodeHighlightTheme] to pass as `CodeEditorStyle.codeTheme`
/// for [filePath], or `null` when the extension isn't recognized -- plain
/// `.txt`/`.log` files and anything else unmapped render as plain
/// monospace text with no highlighting pass, which is both correct (there's
/// no syntax to highlight) and cheaper for large files.
CodeHighlightTheme? _resolveCodeHighlightTheme(String filePath, Brightness brightness) {
  final match = _matchFor(filePath);
  if (match == null) return null;
  return CodeHighlightTheme(
    languages: {match.id: CodeHighlightThemeMode(mode: match.mode)},
    theme: brightness == Brightness.dark ? atomOneDarkTheme : atomOneLightTheme,
  );
}

/// The editor colors for one open file: the (optional) syntax theme plus
/// the background/text colors that actually match it, read straight off
/// the bundled theme's own `'root'` entry rather than duplicated as
/// separate literals that could quietly drift out of sync with it.
@immutable
class EditorSyntaxStyle {
  final CodeHighlightTheme? codeTheme;
  final Color backgroundColor;
  final Color textColor;

  const EditorSyntaxStyle({
    required this.codeTheme,
    required this.backgroundColor,
    required this.textColor,
  });
}

/// Resolves [filePath] to the style [TextEditorScreen] should render it
/// with. [fallback] supplies colors for files with no recognized syntax
/// (and no bundled theme to draw them from) -- normally the current
/// `Theme.of(context).colorScheme`, so a plain `.txt`/`.log` file still
/// blends with the app's own light/dark setting instead of picking a
/// default that only looks right in one of the two.
EditorSyntaxStyle resolveEditorSyntaxStyle(String filePath, Brightness brightness, ColorScheme fallback) {
  final codeTheme = _resolveCodeHighlightTheme(filePath, brightness);
  final root = codeTheme?.theme['root'];
  return EditorSyntaxStyle(
    codeTheme: codeTheme,
    backgroundColor: root?.backgroundColor ?? fallback.surface,
    textColor: root?.color ?? fallback.onSurface,
  );
}
