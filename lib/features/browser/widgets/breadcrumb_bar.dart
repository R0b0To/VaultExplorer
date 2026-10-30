import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/features/browser/file_browser_screen.dart';

/// Horizontal drag recognizer that only claims victory over the Scaffold drawer
/// after the pointer has genuinely moved beyond tap jitter (> 8px).
class _BreadcrumbDragGestureRecognizer
    extends HorizontalDragGestureRecognizer {
  _BreadcrumbDragGestureRecognizer();

  final Map<int, Offset> _startPositions = {};

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    _startPositions[event.pointer] = event.position;
  }

  @override
  void rejectGesture(int pointer) {
    _startPositions.remove(pointer);
    super.rejectGesture(pointer);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) {
      final startPosition = _startPositions[event.pointer];
      if (startPosition != null) {
        final deltaX = (event.position.dx - startPosition.dx).abs();
        final deltaY = (event.position.dy - startPosition.dy).abs();

        if (deltaX > 8.0 && deltaX > deltaY) {
          resolve(GestureDisposition.accepted);
          _startPositions.remove(event.pointer);
        }
      }
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      _startPositions.remove(event.pointer);
    }
    super.handleEvent(event);
  }

  @override
  void dispose() {
    _startPositions.clear();
    super.dispose();
  }
}

class BreadcrumbBar extends StatefulWidget implements PreferredSizeWidget {
  final List<PathSegment> stack;
  final ValueChanged<int> onTap;
  final Color? backgroundColor;

  /// Segments below the current folder that were just stepped back out of,
  /// nearest first. Shown dimmed after the current segment; tapping one calls
  /// [onForwardTap] with its index in this list.
  final List<PathSegment> forwardStack;
  final ValueChanged<int>? onForwardTap;

  const BreadcrumbBar({
    super.key,
    required this.stack,
    required this.onTap,
    this.backgroundColor,
    this.forwardStack = const [],
    this.onForwardTap,
  });

  @override
  Size get preferredSize => const Size.fromHeight(40);

  @override
  State<BreadcrumbBar> createState() => _BreadcrumbBarState();
}

class _BreadcrumbBarState extends State<BreadcrumbBar> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _currentKey = GlobalKey();
  int _lastStackLength = 0;
  String _lastTailPath = '';
  int _lastForwardLength = 0;
  String _lastForwardTailPath = '';
  double? _lastWidth;

  Drag? _drag;
  ScrollHoldController? _hold;

  @override
  void initState() {
    super.initState();
    _lastStackLength = widget.stack.length;
    _lastTailPath = widget.stack.isNotEmpty ? widget.stack.last.fatPath : '';
    _lastForwardLength = widget.forwardStack.length;
    _lastForwardTailPath = widget.forwardStack.isNotEmpty
        ? widget.forwardStack.last.fatPath
        : '';
    _scrollToEnd(animated: false);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final width = MediaQuery.sizeOf(context).width;
    if (_lastWidth != null && _lastWidth != width) {
      _scrollToEnd(animated: false);
    }
    _lastWidth = width;
  }

  @override
  void didUpdateWidget(covariant BreadcrumbBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final currentLength = widget.stack.length;
    final currentTailPath =
        widget.stack.isNotEmpty ? widget.stack.last.fatPath : '';
    final forwardLength = widget.forwardStack.length;
    final forwardTailPath = widget.forwardStack.isNotEmpty
        ? widget.forwardStack.last.fatPath
        : '';

    if (currentLength != _lastStackLength ||
        currentTailPath != _lastTailPath ||
        forwardLength != _lastForwardLength ||
        forwardTailPath != _lastForwardTailPath) {
      _lastStackLength = currentLength;
      _lastTailPath = currentTailPath;
      _lastForwardLength = forwardLength;
      _lastForwardTailPath = forwardTailPath;
      _scrollToEnd(animated: true);
    }
  }

  void _scrollToEnd({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final position = _scrollController.position;
      var target = position.maxScrollExtent;
      // With a forward path after the current folder, the end of the bar is
      // the forward tail. Show as much of it as fits, but never scroll the
      // current folder itself off the left edge.
      if (widget.forwardStack.isNotEmpty) {
        final currentBox = _currentKey.currentContext?.findRenderObject();
        final barBox = context.findRenderObject();
        if (currentBox is RenderBox &&
            currentBox.attached &&
            barBox is RenderBox &&
            barBox.attached) {
          final currentLeft = currentBox
              .localToGlobal(Offset.zero, ancestor: barBox)
              .dx;
          final currentLeftInContent = currentLeft + _scrollController.offset;
          target = (currentLeftInContent - 8.0)
              .clamp(0.0, position.maxScrollExtent)
              .toDouble();
        }
      }
      if ((_scrollController.offset - target).abs() < 1.0) return;

      if (animated) {
        _scrollController.animateTo(
          target,
          duration: AppMotion.short2,
          curve: Curves.easeOutCubic,
        );
      } else {
        _scrollController.jumpTo(target);
      }
    });
  }

  void _disposeHold() => _hold = null;
  void _disposeDrag() => _drag = null;

  void _handleDragDown(DragDownDetails details) {
    if (!_scrollController.hasClients) return;
    _hold = _scrollController.position.hold(_disposeHold);
  }

  void _handleDragStart(DragStartDetails details) {
    if (!_scrollController.hasClients) return;
    _drag = _scrollController.position.drag(details, _disposeDrag);
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    _drag?.update(details);
  }

  void _handleDragEnd(DragEndDetails details) {
    _drag?.end(details);
    _drag = null;
  }

  void _handleDragCancel() {
    _hold?.cancel();
    _hold = null;
    _drag?.cancel();
    _drag = null;
  }

  @override
  void dispose() {
    _hold?.cancel();
    _drag?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      height: 40,
      alignment: Alignment.centerLeft, // Always pin breadcrumbs to the left
      decoration: BoxDecoration(
        color: widget.backgroundColor ?? cs.surface,
      ),
      child: Listener(
        onPointerSignal: (event) {
          if (event is PointerScrollEvent && _scrollController.hasClients) {
            final delta = event.scrollDelta.dy != 0
                ? event.scrollDelta.dy
                : event.scrollDelta.dx;
            final target = (_scrollController.offset + delta).clamp(
              0.0,
              _scrollController.position.maxScrollExtent,
            );
            if (target != _scrollController.offset) {
              _scrollController.jumpTo(target);
            }
          }
        },
        child: RawGestureDetector(
          behavior: HitTestBehavior.opaque,
          gestures: <Type, GestureRecognizerFactory>{
            _BreadcrumbDragGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<
                    _BreadcrumbDragGestureRecognizer>(
              () => _BreadcrumbDragGestureRecognizer(),
              (_BreadcrumbDragGestureRecognizer instance) {
                instance
                  ..onDown = _handleDragDown
                  ..onStart = _handleDragStart
                  ..onUpdate = _handleDragUpdate
                  ..onEnd = _handleDragEnd
                  ..onCancel = _handleDragCancel;
              },
            ),
          },
          child: SingleChildScrollView(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                for (int i = 0; i < widget.stack.length; i++) ...[
                  if (i == widget.stack.length - 1)
                    // Current directory (non-interactive, full 40px height)
                    Container(
                      key: _currentKey,
                      height: 40,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: i == 0
                          ? Icon(
                              Icons.home_rounded,
                              color: cs.onSurface,
                              size: AppIconSize.standard,
                            )
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (widget.stack[i].isArchiveRoot)
                                  const Padding(
                                    padding: EdgeInsets.only(right: 6),
                                    child: Icon(
                                      Icons.archive_rounded,
                                      color: Color(0xFFFF8F00),
                                      size: 16,
                                    ),
                                  ),
                                Text(
                                  widget.stack[i].label,
                                  maxLines: 1,
                                  style: textTheme.labelLarge?.copyWith(
                                    color: widget.stack[i].isArchiveRoot
                                        ? const Color(0xFFFF8F00)
                                        : cs.onSurface,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                    )
                  else
                    // Clickable historical directories (full 40px height touch target)
                    InkWell(
                      onTap: () => widget.onTap(i),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      child: Container(
                        height: 40,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: i == 0
                            ? Icon(
                                Icons.home_outlined,
                                color: cs.primary,
                                size: AppIconSize.standard,
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (widget.stack[i].isArchiveRoot)
                                    const Padding(
                                      padding: EdgeInsets.only(right: 6),
                                      child: Icon(
                                        Icons.archive_rounded,
                                        color: Color(0xFFFF8F00),
                                        size: 16,
                                      ),
                                    ),
                                  Text(
                                    widget.stack[i].label,
                                    maxLines: 1,
                                    style: textTheme.labelLarge?.copyWith(
                                      color: widget.stack[i].isArchiveRoot
                                          ? const Color(0xFFFF8F00)
                                          : cs.primary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  if (i < widget.stack.length - 1)
                    Container(
                      height: 40,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        size: AppIconSize.small,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                      ),
                    ),
                ],
                // Forward history: the folders just stepped back out of, dimmed
                // and still tappable so the person can walk back down.
                for (int f = 0; f < widget.forwardStack.length; f++) ...[
                  Container(
                    height: 40,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: AppIconSize.small,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.28),
                    ),
                  ),
                  InkWell(
                    onTap: widget.onForwardTap == null
                        ? null
                        : () => widget.onForwardTap!(f),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    child: Container(
                      height: 40,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.forwardStack[f].isArchiveRoot)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Icon(
                                Icons.archive_rounded,
                                color: const Color(
                                  0xFFFF8F00,
                                ).withValues(alpha: 0.55),
                                size: 16,
                              ),
                            ),
                          Text(
                            widget.forwardStack[f].label,
                            maxLines: 1,
                            style: textTheme.labelLarge?.copyWith(
                              color: cs.onSurfaceVariant.withValues(
                                alpha: 0.6,
                              ),
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}