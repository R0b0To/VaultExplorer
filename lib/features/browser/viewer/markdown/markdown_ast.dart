// Pure data model for a parsed Markdown document. Each block tracks its
// starting source line so the viewer can accurately sync scroll positions.

sealed class MdBlock {
  final int sourceLine;
  const MdBlock({this.sourceLine = 0});
}

class MdHeading extends MdBlock {
  final int level;
  final List<MdInline> content;
  const MdHeading(this.level, this.content, {super.sourceLine});
}

class MdParagraph extends MdBlock {
  final List<MdInline> content;
  const MdParagraph(this.content, {super.sourceLine});
}

class MdBlockquote extends MdBlock {
  final List<MdBlock> children;
  const MdBlockquote(this.children, {super.sourceLine});
}

class MdCallout extends MdBlock {
  final String type;
  final String title;
  final List<MdBlock> children;
  final bool collapsible;
  final bool defaultCollapsed;

  const MdCallout({
    required this.type,
    required this.title,
    required this.children,
    this.collapsible = false,
    this.defaultCollapsed = false,
    super.sourceLine,
  });
}

class MdCodeBlock extends MdBlock {
  final String code;
  final String? language;
  const MdCodeBlock(this.code, this.language, {super.sourceLine});
}

class MdHorizontalRule extends MdBlock {
  const MdHorizontalRule({super.sourceLine});
}

class MdImageBlock extends MdBlock {
  final String alt;
  final String path;

  /// The optional `"title"` of `![alt](path "title")`.
  final String? title;
  const MdImageBlock(this.alt, this.path, {this.title, super.sourceLine});
}

/// A raw HTML block, exactly as written. Only produced under
/// [MdParseOptions.commonMark]; the app profile turns HTML into text instead.
class MdHtmlBlock extends MdBlock {
  final String html;
  const MdHtmlBlock(this.html, {super.sourceLine});
}

class MdListItem {
  final List<MdBlock> children;
  final bool? checked;
  final int sourceLine;
  const MdListItem({
    required this.children,
    required this.checked,
    this.sourceLine = 0,
  });
}

class MdList extends MdBlock {
  final bool ordered;
  final int startNumber;
  final List<MdListItem> items;

  /// CommonMark "tight" list: no blank lines between items or their blocks.
  final bool tight;
  const MdList({
    required this.ordered,
    required this.startNumber,
    required this.items,
    this.tight = true,
    super.sourceLine,
  });
}

enum MdTableAlign { none, left, center, right }

class MdTable extends MdBlock {
  final List<List<MdInline>> headerCells;
  final List<MdTableAlign> alignments;
  final List<List<List<MdInline>>> rows;
  const MdTable({
    required this.headerCells,
    required this.alignments,
    required this.rows,
    super.sourceLine,
  });
}

sealed class MdInline {
  const MdInline();
}

class MdText extends MdInline {
  final String text;
  const MdText(this.text);
}

class MdLineBreak extends MdInline {
  const MdLineBreak();
}

class MdBold extends MdInline {
  final List<MdInline> children;
  const MdBold(this.children);
}

class MdItalic extends MdInline {
  final List<MdInline> children;
  const MdItalic(this.children);
}

class MdUnderline extends MdInline {
  final List<MdInline> children;
  const MdUnderline(this.children);
}

class MdStrikethrough extends MdInline {
  final List<MdInline> children;
  const MdStrikethrough(this.children);
}

class MdHighlight extends MdInline {
  final List<MdInline> children;
  const MdHighlight(this.children);
}

class MdSubscript extends MdInline {
  final List<MdInline> children;
  const MdSubscript(this.children);
}

class MdSuperscript extends MdInline {
  final List<MdInline> children;
  const MdSuperscript(this.children);
}

class MdInlineCode extends MdInline {
  final String code;
  const MdInlineCode(this.code);
}

class MdLink extends MdInline {
  final List<MdInline> children;
  final String url;

  /// The optional `"title"` of `[text](url "title")`.
  final String? title;
  const MdLink(this.children, this.url, {this.title});
}

class MdInlineImage extends MdInline {
  final String alt;
  final String path;
  final String? title;
  const MdInlineImage(this.alt, this.path, {this.title});
}

/// A raw inline HTML tag, comment, processing instruction, declaration or
/// CDATA section, exactly as written. Only produced under
/// [MdParseOptions.commonMark].
class MdHtmlInline extends MdInline {
  final String html;
  const MdHtmlInline(this.html);
}

/// Switches for the parts of the parser that are app features rather than
/// CommonMark. The default is what the viewer uses; [commonMark] is the strict
/// profile the spec conformance run uses.
class MdParseOptions {
  const MdParseOptions({
    this.bareUrls = true,
    this.interpretHtml = true,
    this.spacedImageDestinations = true,
    this.softBreaksAsNewlines = false,
  });

  /// The viewer's profile.
  static const MdParseOptions app = MdParseOptions();

  /// Plain CommonMark: no extensions that change what the spec specifies.
  static const MdParseOptions commonMark = MdParseOptions(
    bareUrls: false,
    interpretHtml: false,
    spacedImageDestinations: false,
    softBreaksAsNewlines: true,
  );

  /// Turn plain `https://...` text into links (GFM-style autolinks).
  final bool bareUrls;

  /// A native viewer cannot render HTML: formatting tags (`<b>`, `<u>`, `<a>`
  /// ...) become formatting, `<br>` a line break, comments disappear, any other
  /// tag stays visible as text. When false, raw HTML is kept as [MdHtmlBlock] /
  /// [MdHtmlInline] nodes instead.
  final bool interpretHtml;

  /// Keep `![alt](my file.png)` working: notes the old editor wrote contain
  /// image destinations with raw spaces, which CommonMark does not allow.
  final bool spacedImageDestinations;

  /// A line break inside a paragraph becomes `\n` instead of a space. The
  /// viewer wants the space (a `\n` would force a visible break); it only
  /// matters when the text is later re-serialised, e.g. into HTML `<pre>`.
  final bool softBreaksAsNewlines;
}