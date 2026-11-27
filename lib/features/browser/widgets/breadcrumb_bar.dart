import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/core/utils/platform_features.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/widgets/full_screen_drag_drawer.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
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

        // Claim early and without demanding a perfectly flat swipe: the
        // drawer's recognizer accepts after one touch slop (about 8dp on
        // Android) of horizontal travel however steep the swipe is, so a
        // stricter test here let it win on slightly diagonal swipes.
        if (deltaX > 6.0 && deltaX >= deltaY * 0.5) {
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

/// Icon in front of the first crumb for [container]: the device for Local
/// Storage, a drive or card for another storage location, a lock for a vault.
IconData breadcrumbRootIconFor(MountedContainer container) {
  if (container.isPrimaryLocalStorage) return PlatformFeatures.localStorageIcon;
  if (container.isLocalStorage) return PlatformFeatures.externalStorageIcon;
  return Icons.lock_outline_rounded;
}

/// Makes the path in a [BreadcrumbBar] editable, like the address bar of a
/// desktop file manager: tapping the empty part of the bar (or the current
/// folder, or long-pressing anywhere on it) turns the crumbs into a text field
/// holding the full path.
class BreadcrumbEditConfig {
  const BreadcrumbEditConfig({
    required this.pathText,
    required this.onSubmit,
    this.hintText = '',
    this.tooltip = '',
    this.goTooltip = '',
    this.cancelTooltip = '',
  });

  /// The text the field starts with: the full path of the current folder.
  final String pathText;

  /// Called with what was typed. Returns true when it navigated (the field
  /// closes), false when it could not (the field stays open, outlined as an
  /// error, so the text can be corrected; the caller says why).
  final Future<bool> Function(String text) onSubmit;

  final String hintText;

  /// Accessibility label for tapping the bar to edit it.
  final String tooltip;
  final String goTooltip;
  final String cancelTooltip;
}

/// Lets a screen open the bar's editor from outside (Ctrl+L, Alt+D, F4).
class BreadcrumbBarController {
  _BreadcrumbBarState? _state;

  bool get isAttached => _state != null;
  bool get isEditing => _state?._editing ?? false;

  /// Opens the editor with the whole path selected. Does nothing when the bar
  /// is not on screen or is not editable right now.
  void startEditing() => _state?._startEditing();
}

class BreadcrumbBar extends StatefulWidget implements PreferredSizeWidget {
  final List<PathSegment> stack;
  final ValueChanged<int> onTap;
  final Color? backgroundColor;

  /// What the first crumb says, in place of the home icon: the vault's name,
  /// the storage's name or the drive letter. Without it the first crumb is
  /// the home icon.
  final String? rootLabel;

  /// Small icon in front of [rootLabel] (a lock for a vault, a drive for a
  /// storage).
  final IconData? rootIcon;

  /// Turns on editing the path as text. Null leaves the bar read-only.
  final BreadcrumbEditConfig? edit;
  final BreadcrumbBarController? controller;

  /// Segments below the current folder that were just stepped back out of,
  /// nearest first. Shown dimmed after the current segment; tapping one calls
  /// [onForwardTap] with its index in this list.
  final List<PathSegment> forwardStack;
  final ValueChanged<int>? onForwardTap;

   /// Controls placed before the address field (such as back/forward/refresh
  /// on desktop).
  final Widget? leading;

  /// A separate box at the end of the row (the desktop search field). The
  /// path then shares the row with it, like Explorer's address and search
  /// boxes, instead of filling it.
  final Widget? trailing;

  const BreadcrumbBar({
    super.key,
    required this.stack,
    required this.onTap,
    this.backgroundColor,
    this.forwardStack = const [],
    this.onForwardTap,
    this.leading,
    this.trailing,
    this.rootLabel,
    this.rootIcon,
    this.edit,
    this.controller,
  });

  @override
  Size get preferredSize => const Size.fromHeight(40);

  @override
  State<BreadcrumbBar> createState() => _BreadcrumbBarState();
}

class _BreadcrumbBarState extends State<BreadcrumbBar> {
  static const Color _archiveColor = Color(0xFFFF8F00);

  final ScrollController _scrollController = ScrollController();
  final GlobalKey _currentKey = GlobalKey();
  int _lastStackLength = 0;
  String _lastTailPath = '';
  int _lastForwardLength = 0;
  String _lastForwardTailPath = '';
  double? _lastWidth;

  Drag? _drag;
  ScrollHoldController? _hold;

  /// The full-screen drawer's "ignore drags" switch, captured in [build] so it
  /// can still be released from [dispose]. That drawer watches raw pointer
  /// events and never enters the gesture arena, so winning the arena with the
  /// crumbs' own drag recognizer does not stop it from opening.
  ValueChanged<bool>? _setDrawerDragBlocked;
  final Set<int> _blockingPointers = <int>{};

  // Editing the path as text.
  final TextEditingController _editController = TextEditingController();
  final FocusNode _editFocus = FocusNode();
  bool _editing = false;

  /// A submitted path is being checked / navigated to.
  bool _busy = false;

  /// The last submitted path was refused; the field is outlined as an error
  /// until the text changes.
  bool _rejected = false;

  @override
  void initState() {
    super.initState();
    widget.controller?._state = this;
    _editFocus.addListener(_onEditFocusChanged);
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
    if (oldWidget.controller != widget.controller) {
      if (oldWidget.controller?._state == this) {
        oldWidget.controller?._state = null;
      }
      widget.controller?._state = this;
    }
    // The path stopped being editable (an archive was opened, say) while the
    // field was open: drop back to the crumbs.
    if (widget.edit == null && _editing) {
      _editing = false;
      _busy = false;
      _rejected = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _editFocus.hasFocus) _editFocus.unfocus();
      });
    }

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

  // ── Editing the path as text ─────────────────────────────────────────────

  void _startEditing() {
    final edit = widget.edit;
    if (edit == null || _editing || !mounted) return;
    _editController.value = TextEditingValue(
      text: edit.pathText,
      // Everything selected, so typing replaces the path and Ctrl+C copies it.
      selection: TextSelection(
        baseOffset: 0,
        extentOffset: edit.pathText.length,
      ),
    );
    setState(() {
      _editing = true;
      _busy = false;
      _rejected = false;
    });
    // Not `autofocus`: that is ignored while another node (the file list) has
    // focus, which is exactly the Ctrl+L case.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _editing) _editFocus.requestFocus();
    });
  }

  void _stopEditing() {
    if (!_editing) return;
    setState(() {
      _editing = false;
      _busy = false;
      _rejected = false;
    });
    if (_editFocus.hasFocus) _editFocus.unfocus();
    // The crumbs' scroll view was gone while editing, so it comes back at the
    // start; put the current folder back in view.
    _scrollToEnd(animated: false);
  }

  /// Clicking away or tabbing out cancels, as in a desktop address bar. Not
  /// while a submitted path is being resolved.
  void _onEditFocusChanged() {
    if (_editing && !_busy && !_editFocus.hasFocus) _stopEditing();
  }

  Future<void> _commitEdit() async {
    final edit = widget.edit;
    if (edit == null || !_editing || _busy) return;
    final text = _editController.text;
    final trimmed = text.trim();
    if (trimmed.isEmpty || trimmed == edit.pathText) {
      _stopEditing();
      return;
    }
    setState(() {
      _busy = true;
      _rejected = false;
    });
    var accepted = false;
    try {
      accepted = await edit.onSubmit(text);
    } catch (_) {
      accepted = false;
    }
    if (!mounted) return;
    if (accepted) {
      _stopEditing();
    } else {
      setState(() {
        _busy = false;
        _rejected = true;
      });
      _editFocus.requestFocus();
    }
  }

  // ── Scrolling the crumbs by dragging ─────────────────────────────────────

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

  /// A finger went down on the bar. When the crumbs overflow (so a swipe here
  /// scrolls them), keep the full-screen drawer from treating the same swipe
  /// as an open-drawer drag until every finger on the bar is lifted.
  void _handleBarPointerDown(PointerDownEvent event) {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.maxScrollExtent <= 0) return;
    _blockingPointers.add(event.pointer);
    _setDrawerDragBlocked?.call(true);
  }

  void _handleBarPointerEnd(PointerEvent event) {
    if (!_blockingPointers.remove(event.pointer)) return;
    if (_blockingPointers.isEmpty) _setDrawerDragBlocked?.call(false);
  }

  void _handleDragCancel() {
    _hold?.cancel();
    _hold = null;
    _drag?.cancel();
    _drag = null;
  }

  @override
  void dispose() {
    if (widget.controller?._state == this) widget.controller?._state = null;
    if (_blockingPointers.isNotEmpty) {
      _blockingPointers.clear();
      _setDrawerDragBlocked?.call(false);
    }
    _editFocus.removeListener(_onEditFocusChanged);
    _editFocus.dispose();
    _editController.dispose();
    _hold?.cancel();
    _drag?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  // ── Building ─────────────────────────────────────────────────────────────

  /// What one crumb shows. The first crumb is the storage's name (with its
  /// icon) when [BreadcrumbBar.rootLabel] is given, the home icon otherwise.
  Widget _crumbContent(
    PathSegment segment,
    int index, {
    required bool current,
    required ColorScheme cs,
    required TextTheme textTheme,
    bool dimmed = false,
  }) {
    final isRoot = index == 0 && !dimmed;
    final rootLabel = widget.rootLabel;
    if (isRoot && rootLabel == null) {
      return Icon(
        current ? Icons.home_rounded : Icons.home_outlined,
        color: current ? cs.onSurface : cs.primary,
        size: AppIconSize.standard,
      );
    }

    final isArchive = segment.isArchiveRoot;
    final Color color;
    if (dimmed) {
      color = cs.onSurfaceVariant.withValues(alpha: 0.6);
    } else if (isArchive) {
      color = _archiveColor;
    } else {
      color = current ? cs.onSurface : cs.primary;
    }
    final IconData? icon = isRoot
        ? widget.rootIcon
        : (isArchive ? Icons.archive_rounded : null);
    final iconColor = dimmed && isArchive
        ? _archiveColor.withValues(alpha: 0.55)
        : (isArchive ? _archiveColor : color);

    // Names are always shown in full; a long path scrolls instead.
    final text = Text(
      isRoot ? rootLabel! : segment.label,
      maxLines: 1,
      softWrap: false,
      style: textTheme.labelLarge?.copyWith(
        color: color,
        fontWeight: dimmed
            ? FontWeight.w400
            : (current ? FontWeight.w600 : FontWeight.w500),
      ),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Icon(icon, color: iconColor, size: 16),
          ),
        text,
      ],
    );
  }

  /// The crumbs themselves; horizontal scrolling is handled by
  /// [_withDragScroll], which wraps the whole bar so that the margins around
  /// the field scroll it too.
  Widget _buildCrumbs(ColorScheme cs, TextTheme textTheme) {
    return SingleChildScrollView(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (int i = 0; i < widget.stack.length; i++) ...[
                if (i == widget.stack.length - 1)
                  // Current directory (not a link; tapping it edits the path)
                  Container(
                    key: _currentKey,
                    height: 32,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: _crumbContent(
                      widget.stack[i],
                      i,
                      current: true,
                      cs: cs,
                      textTheme: textTheme,
                    ),
                  )
                else
                  // Clickable historical directories
                  InkWell(
                    onTap: () => widget.onTap(i),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    child: Container(
                      height: 32,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: _crumbContent(
                        widget.stack[i],
                        i,
                        current: false,
                        cs: cs,
                        textTheme: textTheme,
                      ),
                    ),
                  ),
                if (i < widget.stack.length - 1)
                  Container(
                    height: 32,
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
                  height: 32,
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
                    height: 32,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: _crumbContent(
                      widget.forwardStack[f],
                      f,
                      current: false,
                      cs: cs,
                      textTheme: textTheme,
                      dimmed: true,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
  }

  /// Lets the crumbs be scrolled by dragging (and by the mouse wheel) from
  /// anywhere on the bar, margins included. The bar sits under a side drawer
  /// that opens on a horizontal drag from anywhere on screen, so a drag that
  /// starts on a spot this does not cover would open the drawer instead.
  Widget _withDragScroll(Widget child) {
    _setDrawerDragBlocked = FullScreenDragDrawerScope.maybeOf(
      context,
    )?.setDrawerDragBlocked;
    return Listener(
      onPointerDown: _handleBarPointerDown,
      onPointerUp: _handleBarPointerEnd,
      onPointerCancel: _handleBarPointerEnd,
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
        child: child,
      ),
    );
  }

  /// The path as an editable text field, with a go and a cancel button (the
  /// buttons are what a touch keyboard's "go" key is for, and what a mouse
  /// user without Enter at hand clicks).
  Widget _buildEditor(
    ColorScheme cs,
    TextTheme textTheme,
    BreadcrumbEditConfig edit,
  ) {
    const buttonConstraints = BoxConstraints.tightFor(width: 28, height: 28);
    return Row(
      children: [
        Expanded(
          child: Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.escape) {
                _stopEditing();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: TextField(
              controller: _editController,
              focusNode: _editFocus,
              readOnly: _busy,
              autocorrect: false,
              enableSuggestions: false,
              smartDashesType: SmartDashesType.disabled,
              smartQuotesType: SmartQuotesType.disabled,
              textInputAction: TextInputAction.go,
              textAlignVertical: TextAlignVertical.center,
              style: textTheme.labelLarge?.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.w500,
              ),
              onChanged: (_) {
                if (_rejected) setState(() => _rejected = false);
              },
              // Overridden so the field keeps focus while the path is being
              // checked (the default drops it before onSubmitted runs, which
              // would read as clicking away and cancel).
              onEditingComplete: () {},
              onSubmitted: (_) => unawaited(_commitEdit()),
              // A touch outside cancels on every platform (Flutter's default
              // is to do so only on desktop).
              onTapOutside: (_) => _stopEditing(),
              decoration: InputDecoration(
                hintText: edit.hintText,
                hintStyle: textTheme.labelLarge?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isCollapsed: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10),
              ),
            ),
          ),
        ),
        // Inside the field's tap region: pressing them is not "clicking away".
        // ExcludeFocus: pressing them must not move focus off the field, which
        // would read as clicking away and cancel before the press lands.
        TextFieldTapRegion(
          child: ExcludeFocus(
            child: _busy
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 7),
                    child: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: cs.primary,
                      ),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.arrow_forward_rounded),
                    iconSize: 18,
                    color: cs.primary,
                    padding: EdgeInsets.zero,
                    constraints: buttonConstraints,
                    tooltip: edit.goTooltip.isEmpty ? null : edit.goTooltip,
                    onPressed: () => unawaited(_commitEdit()),
                  ),
          ),
        ),
        TextFieldTapRegion(
          child: ExcludeFocus(
            child: IconButton(
              icon: const Icon(Icons.close_rounded),
              iconSize: 16,
              color: cs.onSurfaceVariant,
              padding: EdgeInsets.zero,
              constraints: buttonConstraints,
              tooltip: edit.cancelTooltip.isEmpty ? null : edit.cancelTooltip,
              onPressed: _stopEditing,
            ),
          ),
        ),
        const SizedBox(width: 2),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final edit = widget.edit;
    final editing = _editing && edit != null;

    // Styled like a browser's address bar: a rounded field that the path sits
    // inside, always pinned to the left. It gets an outline while it is being
    // edited.
    Widget content;
    if (editing) {
      content = _buildEditor(cs, textTheme, edit);
    } else {
      content = _buildCrumbs(cs, textTheme);
    }

    final pathField = Container(
      alignment: Alignment.centerLeft,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
        border: editing
            ? Border.all(color: _rejected ? cs.error : cs.primary, width: 1.5)
            : null,
      ),
      child: content,
    );

    final leading = widget.leading;
    final trailing = widget.trailing;
    // The 4px above and below the field belong to the drag area too.
    Widget field = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: pathField,
    );
    if (!editing) field = _withDragScroll(field);
    if (edit != null && !editing) {
      // Every part of the address field that is not a crumb link opens the
      // editor: the empty space after the path, the current folder, and the
      // field margins. Kept on the field itself so leading nav buttons and the
      // trailing search box keep their own cursor and tap behavior.
      field = Semantics(
        label: edit.tooltip.isEmpty ? null : edit.tooltip,
        onTap: _startEditing,
        child: MouseRegion(
          cursor: SystemMouseCursors.text,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _startEditing,
            onLongPress: _startEditing,
            child: field,
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      height: 40,
      padding: (leading == null && trailing == null)
          ? null
          : EdgeInsets.only(
              left: leading == null ? 8 : 6,
              right: 8,
            ),
      decoration: BoxDecoration(
        color: widget.backgroundColor ?? cs.surface,
      ),
      child: (leading == null && trailing == null)
          ? field
          : LayoutBuilder(
              builder: (context, constraints) {
                final reservedLeading = leading != null ? 136.0 : 0.0;
                final remaining = (constraints.maxWidth - reservedLeading)
                    .clamp(0.0, double.infinity);
                final trailingWidth = math.min(260.0, remaining * 0.4);
                return Row(
                  children: [
                    if (leading != null) ...[
                      leading,
                      const SizedBox(width: 4),
                    ],
                    Expanded(child: field),
                    if (trailing != null) ...[
                      const SizedBox(width: 8),
                      SizedBox(
                        width: trailingWidth,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: trailing,
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
    );
  }
}
