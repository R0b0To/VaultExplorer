import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/core/widgets/layout/settings_toggle_row.dart';

/// Where a search result should land on its destination screen.
class SettingsSearchTarget {
  const SettingsSearchTarget({
    required this.text,
    this.section,
    this.fallback,
    this.unavailableMessage,
  });

  /// The exact text of the row's title, as rendered on screen.
  final String text;

  /// Header text the row sits under. When set, only a row after that header
  /// matches, which tells apart rows that share a title.
  final String? section;

  /// Text to scroll to when the row itself isn't shown (it only appears when
  /// some other setting is on).
  final String? fallback;

  /// Shown when neither the row nor the fallback could be found.
  final String? unavailableMessage;
}

/// Wraps a settings screen and, when given a [target], scrolls the screen to
/// that row and briefly highlights it.
///
/// The row is found by its visible title text, so the settings screens need no
/// per-row annotations. Lists build their rows lazily, so the screen is paged
/// through from the top until the row has been built; the page stays hidden
/// while that happens (normally a handful of frames) so the user never sees it
/// scrolling.
class SettingsSearchTargetScope extends StatefulWidget {
  const SettingsSearchTargetScope({
    super.key,
    required this.target,
    required this.child,
  });

  final SettingsSearchTarget? target;
  final Widget child;

  @override
  State<SettingsSearchTargetScope> createState() =>
      _SettingsSearchTargetScopeState();
}

class _SettingsSearchTargetScopeState extends State<SettingsSearchTargetScope>
    with SingleTickerProviderStateMixin {
  static const _lookupTimeout = Duration(milliseconds: 2500);
  static const _highlightDuration = Duration(milliseconds: 1800);

  late final AnimationController _pulse;
  late bool _revealed;
  Rect? _highlight;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: _highlightDuration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() => _highlight = null);
        }
      });
    final target = widget.target;
    _revealed = target == null;
    if (target != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _locate(target));
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _locate(SettingsSearchTarget target) async {
    Element? found;
    var usedFallback = false;
    try {
      found = await _sweep(target.text, target.section);
      if (found == null && target.fallback != null) {
        found = await _sweep(target.fallback!, null);
        usedFallback = found != null;
      }
      if (!mounted) return;

      Rect? rect;
      if (found != null && found.mounted) {
        await Scrollable.ensureVisible(
          found,
          alignment: 0.3,
          duration: Duration.zero,
        );
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
        rect = found.mounted ? _rowRect(found) : null;
      }

      setState(() {
        _revealed = true;
        _highlight = rect;
      });
      if (rect != null) _pulse.forward(from: 0);

      if ((found == null || usedFallback) && target.unavailableMessage != null) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(target.unavailableMessage!)),
        );
      }
    } catch (e) {
      // Locating a row is a convenience; never leave the page hidden.
      VeLog.w('SettingsSearch', 'Could not locate "${target.text}"', e);
      if (mounted) setState(() => _revealed = true);
    }
  }

  /// Pages the screen's main list from the top until a Text equal to [text]
  /// (after the [section] header, if given) is built. Gives up after two full
  /// passes with no match, or when the lookup times out (screens that load
  /// their data asynchronously are waited for).
  Future<Element?> _sweep(String text, String? section) async {
    final deadline = DateTime.now().add(_lookupTimeout);
    var passes = 0;
    var jumpedToTop = false;

    while (mounted) {
      final texts = _collectTexts();
      final match = _findText(texts, text, section);
      if (match != null) return match;

      final position = _scrollPosition();
      final scrollable = position != null &&
          position.hasContentDimensions &&
          position.maxScrollExtent > 0;

      if (scrollable) {
        if (!jumpedToTop && position.pixels > position.minScrollExtent) {
          jumpedToTop = true;
          position.jumpTo(position.minScrollExtent);
        } else if (position.pixels >= position.maxScrollExtent - 1) {
          passes++;
          if (passes >= 2) return null;
          position.jumpTo(position.minScrollExtent);
        } else {
          position.jumpTo(
            math.min(
              position.maxScrollExtent,
              position.pixels + position.viewportDimension * 0.85,
            ),
          );
        }
      } else if (texts.length >= 4) {
        // Content is on screen and fits without scrolling: the row isn't here.
        return null;
      }

      if (DateTime.now().isAfter(deadline)) return null;
      await WidgetsBinding.instance.endOfFrame;
    }
    return null;
  }

  /// All Text widgets under this scope in tree (= reading) order, skipping the
  /// app bar and anything off-stage.
  List<Element> _collectTexts() {
    final out = <Element>[];
    void visit(Element element) {
      final widget = element.widget;
      if (widget is AppBar) return;
      if (widget is Offstage && widget.offstage) return;
      if (widget is Text) {
        out.add(element);
        return;
      }
      element.visitChildren(visit);
    }

    (context as Element).visitChildren(visit);
    return out;
  }

  Element? _findText(List<Element> texts, String text, String? section) {
    var start = 0;
    if (section != null) {
      final header = texts.indexWhere((e) => _textOf(e) == section);
      if (header < 0) return null; // header not built yet: keep paging
      start = header + 1;
    }
    for (var i = start; i < texts.length; i++) {
      if (_textOf(texts[i]) == text) return texts[i];
    }
    return null;
  }

  String _textOf(Element element) {
    final widget = element.widget as Text;
    return (widget.data ?? widget.textSpan?.toPlainText() ?? '').trim();
  }

  /// The position of the first vertical scrollable under this scope.
  ScrollPosition? _scrollPosition() {
    ScrollPosition? result;
    void visit(Element element) {
      if (result != null) return;
      final widget = element.widget;
      if (widget is AppBar) return;
      if (widget is Scrollable &&
          widget.axis == Axis.vertical &&
          element is StatefulElement) {
        final state = element.state;
        if (state is ScrollableState) {
          result = state.position;
          return;
        }
      }
      element.visitChildren(visit);
    }

    (context as Element).visitChildren(visit);
    return result;
  }

  /// The bounds, in this scope's coordinates, of the settings row that holds
  /// [textElement]: its enclosing tile if there is one, else the text itself.
  Rect? _rowRect(Element textElement) {
    Element? row;
    var depth = 0;
    textElement.visitAncestorElements((ancestor) {
      depth++;
      final widget = ancestor.widget;
      if (widget is ListTile || widget is SettingsToggleRow) {
        row = ancestor;
        return false;
      }
      return widget is! Scrollable && depth < 14;
    });

    final element = row ?? textElement;
    final renderObject = element.renderObject;
    final scopeBox = context.findRenderObject();
    if (renderObject is! RenderBox ||
        !renderObject.attached ||
        !renderObject.hasSize ||
        scopeBox is! RenderBox) {
      return null;
    }
    final topLeft = renderObject.localToGlobal(Offset.zero, ancestor: scopeBox);
    final rect = topLeft & renderObject.size;
    return row == null ? rect.inflate(6) : rect;
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final rect = _highlight;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        IgnorePointer(
          ignoring: !_revealed,
          child: Opacity(
            opacity: _revealed ? 1 : 0,
            child: NotificationListener<ScrollStartNotification>(
              onNotification: (notification) {
                // The user took over: drop the highlight instead of leaving it
                // floating over rows that have moved.
                if (notification.dragDetails != null && _highlight != null) {
                  _pulse.stop();
                  setState(() => _highlight = null);
                }
                return false;
              },
              child: widget.child,
            ),
          ),
        ),
        if (rect != null)
          Positioned.fromRect(
            rect: rect,
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (context, _) {
                  final t = _pulse.value;
                  final fade = t < 0.12
                      ? t / 0.12
                      : (t < 0.7 ? 1.0 : 1.0 - (t - 0.7) / 0.3);
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.16 * fade),
                      border: Border.all(
                        color: color.withValues(alpha: 0.55 * fade),
                        width: 1.5,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}
