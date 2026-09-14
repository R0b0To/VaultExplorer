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
  const MdImageBlock(this.alt, this.path, {super.sourceLine});
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
  const MdList({
    required this.ordered,
    required this.startNumber,
    required this.items,
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
  const MdLink(this.children, this.url);
}

class MdInlineImage extends MdInline {
  final String alt;
  final String path;
  const MdInlineImage(this.alt, this.path);
}