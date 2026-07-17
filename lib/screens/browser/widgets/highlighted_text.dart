import 'package:flutter/material.dart';

/// Renders [text] with all case-insensitive occurrences of [query] highlighted.
///
/// When [query] is null or empty the widget is a plain [Text] with the given
/// [style], so callers don't need to branch.
class HighlightedText extends StatelessWidget {
  final String text;
  final String? query;
  final TextStyle? style;
  final int maxLines;
  final TextOverflow overflow;

  const HighlightedText({
    super.key,
    required this.text,
    this.query,
    this.style,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
  });

  @override
  Widget build(BuildContext context) {
    final q = query?.trim().toLowerCase() ?? '';
    if (q.isEmpty) {
      return Text(text, style: style, maxLines: maxLines, overflow: overflow);
    }

    final cs = Theme.of(context).colorScheme;
    final highlightStyle = style?.copyWith(
          color: cs.onTertiaryContainer,
          backgroundColor: cs.tertiaryContainer,
          fontWeight: FontWeight.w600,
        ) ??
        TextStyle(
          color: cs.onTertiaryContainer,
          backgroundColor: cs.tertiaryContainer,
          fontWeight: FontWeight.w600,
        );

    final spans = <TextSpan>[];
    final lower = text.toLowerCase();
    int start = 0;

    while (start < text.length) {
      final idx = lower.indexOf(q, start);
      if (idx == -1) {
        spans.add(TextSpan(text: text.substring(start), style: style));
        break;
      }
      if (idx > start) {
        spans.add(TextSpan(text: text.substring(start, idx), style: style));
      }
      spans.add(TextSpan(
        text: text.substring(idx, idx + q.length),
        style: highlightStyle,
      ));
      start = idx + q.length;
    }

    return RichText(
      text: TextSpan(children: spans),
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}
