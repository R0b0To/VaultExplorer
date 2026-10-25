part of re_editor;

abstract class IParagraph {

  double get width;
  double get height;
  double get preferredLineHeight;
  bool get trucated;
  int get length;
  int get lineCount;

  void draw(Canvas canvas, Offset offset);

  TextPosition getPosition(Offset offset);

  TextRange getWord(Offset offset);
  
  InlineSpan? getSpanForPosition(TextPosition position);

  TextRange getRangeForSpan(InlineSpan span);

  TextRange getLineBoundary(TextPosition position);

  Offset? getOffset(TextPosition position);

  List<Rect> getRangeRects(TextRange range);

}

/// Implemented by render objects that paint text a tool cannot read back from
/// the widget tree (the code canvas and its line numbers are painted straight
/// onto a canvas). Lets an inspector ask what color the text under a point is.
abstract class CodeTextColorProbe {

  /// The color of the text painted at [globalPosition], or null when that point
  /// is not over text this object paints.
  Color? textColorAt(Offset globalPosition);

}
