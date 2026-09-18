import 'dart:ui';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/features/browser/file_browser_screen.dart';

/// Horizontal drag recognizer that only claims victory over the Scaffold drawer
/// after the pointer has genuinely moved beyond tap jitter (> 8px).
class _BreadcrumbDragGestureRecognizer
    extends HorizontalDragGestureRecognizer {
  _BreadcrumbDragGestureRecognizer();

  Offset? _startPosition;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _startPosition = event.position;
    super.addAllowedPointer(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent && _startPosition != null) {
      final deltaX = (event.position.dx - _startPosition!.dx).abs();
      final deltaY = (event.position.dy - _startPosition!.dy).abs();

      // Only claim the gesture if there is clear horizontal movement > 8px.
      // This allows natural tap jitter (1-4px) to register cleanly as taps,
      // while still beating the Scaffold drawer (which waits for 18px slop).
      if (deltaX > 8.0 && deltaX > deltaY) {
        resolve(GestureDisposition.accepted);
      }
    }
    super.handleEvent(event);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _startPosition = null;
    super.didStopTrackingLastPointer(pointer);
  }
}

class BreadcrumbBar extends StatefulWidget implements PreferredSizeWidget {
  final List<PathSegment> stack;
  final ValueChanged<int> onTap;

  const BreadcrumbBar({super.key, required this.stack, required this.onTap});

  @override
  Size get preferredSize => const Size.fromHeight(40);

  @override
  State<BreadcrumbBar> createState() => _BreadcrumbBarState();
}

class _BreadcrumbBarState extends State<BreadcrumbBar> {
  final ScrollController _scrollController = ScrollController();
  int _lastStackLength = 0;
  String _lastTailPath = '';
  double? _lastWidth;

  Drag? _drag;
  ScrollHoldController? _hold;

  @override
  void initState() {
    super.initState();
    _lastStackLength = widget.stack.length;
    _lastTailPath = widget.stack.isNotEmpty ? widget.stack.last.fatPath : '';
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

    if (currentLength != _lastStackLength || currentTailPath != _lastTailPath) {
      _lastStackLength = currentLength;
      _lastTailPath = currentTailPath;
      _scrollToEnd(animated: true);
    }
  }

  void _scrollToEnd({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
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
        color: cs.surface,
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}