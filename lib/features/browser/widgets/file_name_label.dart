import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/data/models/long_file_name_display_mode.dart';
import 'package:vaultexplorer/features/browser/widgets/highlighted_text.dart';

/// Renders a file/folder name on a single line, shortening it to fit
/// according to [mode] instead of ever wrapping onto a second line.
///
/// Flutter's built-in [TextOverflow.ellipsis] only ever trims from the end
/// of the text, so [LongFileNameDisplayMode.ellipsizeStart] and
/// [LongFileNameDisplayMode.ellipsizeMiddle] are implemented here by
/// measuring the text with a [TextPainter] and pre-truncating it by hand.
/// [LongFileNameDisplayMode.marquee] instead keeps the full name and scrolls
/// it back and forth. [LongFileNameDisplayMode.ellipsizeEnd] is exactly
/// Flutter's default behaviour, so that case is just a thin wrapper around
/// [HighlightedText].
class FileNameLabel extends StatelessWidget {
  final String text;
  final String? query;
  final TextStyle? style;
  final LongFileNameDisplayMode mode;

  const FileNameLabel({
    super.key,
    required this.text,
    this.query,
    this.style,
    this.mode = LongFileNameDisplayMode.ellipsizeEnd,
  });

  static const String _ellipsis = '…';

  @override
  Widget build(BuildContext context) {
    switch (mode) {
      case LongFileNameDisplayMode.marquee:
        // Search highlighting isn't meaningful on scrolling text (there's
        // no fixed viewport for a highlight to sit in), so marquee mode
        // always shows the plain name.
        return _MarqueeFileName(text: text, style: style);

      case LongFileNameDisplayMode.ellipsizeEnd:
        return HighlightedText(
          text: text,
          query: query,
          style: style,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );

      case LongFileNameDisplayMode.ellipsizeStart:
      case LongFileNameDisplayMode.ellipsizeMiddle:
        return LayoutBuilder(
          builder: (context, constraints) {
            final effectiveStyle = style ?? DefaultTextStyle.of(context).style;
            final truncated = _truncate(
              text: text,
              style: effectiveStyle,
              maxWidth: constraints.maxWidth,
              textScaler: MediaQuery.textScalerOf(context),
            );
            return HighlightedText(
              text: truncated,
              query: query,
              style: style,
              maxLines: 1,
              overflow: TextOverflow.clip,
            );
          },
        );
    }
  }

  static final Map<String, String> _truncationCache = {};
  static const int _maxCacheEntries = 1000;

  static void clearCache() => _truncationCache.clear();

  double _measure(String s, TextStyle style, TextScaler textScaler) {
    final painter = TextPainter(
      text: TextSpan(text: s, style: style),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: 1,
    )..layout();
    return painter.width;
  }

  String _truncate({
    required String text,
    required TextStyle style,
    required double maxWidth,
    required TextScaler textScaler,
  }) {
    if (maxWidth <= 0 || text.isEmpty) return text;
    final cacheKey =
        '$mode:${maxWidth.toInt()}:${style.fontSize}:${textScaler.scale(1.0)}:$text';
    final cached = _truncationCache[cacheKey];
    if (cached != null) return cached;

    final result = _computeTruncate(
      text: text,
      style: style,
      maxWidth: maxWidth,
      textScaler: textScaler,
    );

    if (_truncationCache.length >= _maxCacheEntries) {
      _truncationCache.remove(_truncationCache.keys.first);
    }
    _truncationCache[cacheKey] = result;
    return result;
  }

  String _computeTruncate({
    required String text,
    required TextStyle style,
    required double maxWidth,
    required TextScaler textScaler,
  }) {
    if (_measure(text, style, textScaler) <= maxWidth) return text;

    return mode == LongFileNameDisplayMode.ellipsizeStart
        ? _fitFromEnd(text, style, maxWidth, textScaler)
        : _fitFromMiddle(text, style, maxWidth, textScaler);
  }

  /// Binary-searches the longest trailing chunk of [text] that, prefixed
  /// with an ellipsis, still fits in [maxWidth].
  String _fitFromEnd(
    String text,
    TextStyle style,
    double maxWidth,
    TextScaler textScaler,
  ) {
    int lo = 1, hi = text.length;
    String best = _ellipsis;
    while (lo <= hi) {
      final mid = (lo + hi) ~/ 2;
      final candidate = '$_ellipsis${text.substring(text.length - mid)}';
      if (_measure(candidate, style, textScaler) <= maxWidth) {
        best = candidate;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return best;
  }

  /// Binary-searches the longest symmetric head+tail of [text] that, joined
  /// by an ellipsis, still fits in [maxWidth]. Biases the tail slightly
  /// longer than the head so a file extension near the end tends to stay
  /// readable.
  String _fitFromMiddle(
    String text,
    TextStyle style,
    double maxWidth,
    TextScaler textScaler,
  ) {
    final maxHalf = (text.length / 2).ceil();
    int lo = 1, hi = maxHalf;
    String best = _ellipsis;
    while (lo <= hi) {
      final mid = (lo + hi) ~/ 2;
      final headLen = mid;
      final tailLen = (mid + 2).clamp(0, text.length - headLen);
      final head = text.substring(0, headLen);
      final tail = tailLen == 0 ? '' : text.substring(text.length - tailLen);
      final candidate = '$head$_ellipsis$tail';
      if (_measure(candidate, style, textScaler) <= maxWidth) {
        best = candidate;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return best;
  }
}

/// Horizontally scrolls [text] in an unbroken, continuous loop when it
/// overflows its container width. Text that already fits is rendered statically.
class _MarqueeFileName extends StatefulWidget {
  final String text;
  final TextStyle? style;

  const _MarqueeFileName({required this.text, this.style});

  @override
  State<_MarqueeFileName> createState() => _MarqueeFileNameState();
}

class _MarqueeFileNameState extends State<_MarqueeFileName>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  double? _lastCycleDistance;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  @override
  void didUpdateWidget(covariant _MarqueeFileName oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.style != widget.style) {
      _lastCycleDistance = null;
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Size _measure(String s, TextStyle style, TextScaler textScaler) {
    final painter = TextPainter(
      text: TextSpan(text: s, style: style),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: 1,
    )..layout();
    return painter.size;
  }

  void _updateAnimation(double cycleDistance) {
    if (_lastCycleDistance == cycleDistance) return;
    _lastCycleDistance = cycleDistance;
    // ~30 px/sec for an unhurried, readable marquee pace
    final durationMs = (cycleDistance / 30.0 * 1000).round().clamp(1000, 60000);
    _controller.duration = Duration(milliseconds: durationMs);
    if (!_controller.isAnimating) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_controller.isAnimating) {
          _controller.repeat();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.text.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final effectiveStyle =
            widget.style ?? DefaultTextStyle.of(context).style;
        final textScaler = MediaQuery.textScalerOf(context);
        final textSize = _measure(widget.text, effectiveStyle, textScaler);
        final textWidth = textSize.width;
        final textHeight = textSize.height;

        // Fits inside available space -- static render, 0 animation cost
        if (constraints.maxWidth <= 0 || textWidth <= constraints.maxWidth) {
          return Text(
            widget.text,
            style: widget.style,
            maxLines: 1,
            overflow: TextOverflow.clip,
          );
        }

        const gap = 48.0;
        final cycleDistance = textWidth + gap;
        _updateAnimation(cycleDistance);

        final textWidget = Text(
          widget.text,
          style: widget.style,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.visible,
        );

        return SizedBox(
          width: constraints.maxWidth,
          height: textHeight,
          child: ClipRect(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(-_controller.value * cycleDistance, 0),
                  child: child,
                );
              },
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: Directionality(
                      textDirection: TextDirection.ltr,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          textWidget,
                          const SizedBox(width: gap),
                          textWidget,
                          const SizedBox(width: gap),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
