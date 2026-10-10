// The bar pinned above the soft keyboard while editing a file in
// TextEditorScreen -- see docs/text editor expansion plan, Phase 2. Three
// horizontally-scrollable rows:
//   1. Symbols that are awkward to reach on a stock Android keyboard layout
//      (nested punctuation, brackets, quotes).
//   2. Undo/redo, left/right caret nav, select-word, and paste -- one-tap
//      versions of gestures that are fiddly with a fingertip on a small
//      screen.
//   3. The caret scrubber -- a full-width drag strip that moves the cursor
//      left/right one character per step of travel, so repositioning the
//      caret doesn't require a fingertip directly on top of it (which is
//      exactly what obscures the thing you're trying to aim at).
//
// Every button re-requests focus on the editor after acting: a Material
// `InkWell` can otherwise pull keyboard focus onto itself for a frame,
// which would dismiss the soft keyboard the bar is meant to sit above.
import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
import 'package:re_editor/re_editor.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/data/services/text_editor_appearance_service.dart';

class EditorFocusNode extends FocusNode {
  bool keepFocusLocked = false;

  @override
  void unfocus({UnfocusDisposition disposition = UnfocusDisposition.scope}) {
    // Ignore requests to drop focus if the accessory bar is actively being touched
    if (keepFocusLocked) return;
    super.unfocus(disposition: disposition);
  }
}

class EditorAccessoryKeyBar extends StatelessWidget {
  final CodeLineEditingController controller;
  final FocusNode editorFocusNode;
  final List<String> symbols;
  final List<String> actions;
  final bool showSymbols;
  final bool showActions;
  final bool showScrubber;
  final bool isWordWrap;
  final bool isReadOnly;
  final VoidCallback? onSearch;
  final VoidCallback? onToggleWordWrap;
  final VoidCallback? onGoToLine;
  final VoidCallback? onGoToStart;
  final VoidCallback? onGoToEnd;
  final VoidCallback? onFormat;
  final VoidCallback? onToggleReadOnly;

  const EditorAccessoryKeyBar({
    super.key,
    required this.controller,
    required this.editorFocusNode,
    this.symbols = TextEditorAppearancePrefs.defaultSymbols,
    this.actions = TextEditorAppearancePrefs.defaultActions,
    this.showSymbols = true,
    this.showActions = true,
    this.showScrubber = false,
    this.isWordWrap = true,
    this.isReadOnly = false,
    this.onSearch,
    this.onToggleWordWrap,
    this.onGoToLine,
    this.onGoToStart,
    this.onGoToEnd,
    this.onFormat,
    this.onToggleReadOnly,
  });

  void _act(VoidCallback action) {
    action();
    if (!editorFocusNode.hasFocus) {
      editorFocusNode.requestFocus();
    }
  }

  void _insert(String symbol) => _act(() => controller.replaceSelection(symbol));

 void _selectWord() => _act(() {
    final selection = controller.selection;
    final lineIdx = selection.extentIndex;
    if (lineIdx < 0 || lineIdx >= controller.codeLines.length) return;
    final line = controller.codeLines[lineIdx].text;
    if (line.isEmpty) return;

    int offset = selection.extentOffset.clamp(0, line.length);
    bool isWordChar(String ch) => RegExp(r'[\w]').hasMatch(ch);

    if (offset == line.length && offset > 0) {
      offset--;
    }

    if (!isWordChar(line[offset]) && offset > 0 && isWordChar(line[offset - 1])) {
      offset--;
    }

    if (!isWordChar(line[offset])) {
      final isSpace = RegExp(r'\s').hasMatch(line[offset]);
      int start = offset;
      int end = offset;
      if (isSpace) {
        while (start > 0 && RegExp(r'\s').hasMatch(line[start - 1])) {
          start--;
        }
        while (end < line.length && RegExp(r'\s').hasMatch(line[end])) {
          end++;
        }
      } else {
        while (start > 0 && !isWordChar(line[start - 1]) && !RegExp(r'\s').hasMatch(line[start - 1])) {
          start--;
        }
        while (end < line.length && !isWordChar(line[end]) && !RegExp(r'\s').hasMatch(line[end])) {
          end++;
        }
      }
      controller.selection = CodeLineSelection(
        baseIndex: lineIdx,
        baseOffset: start,
        extentIndex: lineIdx,
        extentOffset: math.max(start + 1, end),
      );
      return;
    }

    int start = offset;
    while (start > 0 && isWordChar(line[start - 1])) {
      start--;
    }
    int end = offset;
    while (end < line.length && isWordChar(line[end])) {
      end++;
    }

    controller.selection = CodeLineSelection(
      baseIndex: lineIdx,
      baseOffset: start,
      extentIndex: lineIdx,
      extentOffset: end,
    );
  });

  void _selectAll() => _act(() {
    if (controller.codeLines.isEmpty) return;
    final lastLineIndex = controller.codeLines.length - 1;
    final lastLineLength = controller.codeLines[lastLineIndex].text.length;
    controller.selection = CodeLineSelection(
      baseIndex: 0,
      baseOffset: 0,
      extentIndex: lastLineIndex,
      extentOffset: lastLineLength,
    );
  });

  Widget? _buildActionButton(BuildContext context, String actionKey, ColorScheme cs) {
    switch (actionKey) {
      case 'undo':
        return _IconKeyButton(
          icon: Icons.undo_rounded,
          tooltip: context.l10n.actionUndo,
          enabled: controller.canUndo,
          onTap: () => _act(controller.undo),
        );
      case 'redo':
        return _IconKeyButton(
          icon: Icons.redo_rounded,
          tooltip: context.l10n.actionRedo,
          enabled: controller.canRedo,
          onTap: () => _act(controller.redo),
        );
      case 'cursorLeft':
        return _IconKeyButton(
          icon: Icons.keyboard_arrow_left_rounded,
          tooltip: context.l10n.actionCursorLeft,
          onTap: () => _act(() => controller.moveCursor(AxisDirection.left)),
        );
      case 'cursorRight':
        return _IconKeyButton(
          icon: Icons.keyboard_arrow_right_rounded,
          tooltip: context.l10n.actionCursorRight,
          onTap: () => _act(() => controller.moveCursor(AxisDirection.right)),
        );
      case 'selectWord':
        return _IconKeyButton(
          icon: Icons.highlight_alt_rounded,
          tooltip: context.l10n.actionSelectWord,
          onTap: _selectWord,
        );
      case 'selectAll':
        return _IconKeyButton(
          icon: Icons.select_all_rounded,
          tooltip: context.l10n.actionSelectAll,
          onTap: _selectAll,
        );
      case 'copy':
        return _IconKeyButton(
          icon: Icons.content_copy_rounded,
          tooltip: context.l10n.actionCopy,
          onTap: () => _act(controller.copy),
        );
      case 'cut':
        return _IconKeyButton(
          icon: Icons.content_cut_rounded,
          tooltip: context.l10n.actionCut,
          enabled: !isReadOnly,
          onTap: () => _act(controller.cut),
        );
      case 'paste':
        return _IconKeyButton(
          icon: Icons.content_paste_rounded,
          tooltip: context.l10n.actionPaste,
          enabled: !isReadOnly,
          onTap: () => _act(controller.paste),
        );
      case 'find':
        return _IconKeyButton(
          icon: Icons.search_rounded,
          tooltip: context.l10n.actionFind,
          onTap: () => _act(() => onSearch?.call()),
        );
      case 'wordWrap':
        return _IconKeyButton(
          icon: Icons.wrap_text_rounded,
          tooltip: context.l10n.actionWordWrap,
          selected: isWordWrap,
          onTap: () => _act(() => onToggleWordWrap?.call()),
        );
      case 'goToLine':
        return _IconKeyButton(
          icon: Icons.format_list_numbered_rounded,
          tooltip: context.l10n.actionGoToLine,
          onTap: () => _act(() => onGoToLine?.call()),
        );
      case 'goToStart':
        return _IconKeyButton(
          icon: Icons.vertical_align_top_rounded,
          tooltip: context.l10n.actionGoToStart,
          onTap: () => _act(() => onGoToStart?.call()),
        );
      case 'goToEnd':
        return _IconKeyButton(
          icon: Icons.vertical_align_bottom_rounded,
          tooltip: context.l10n.actionGoToEnd,
          onTap: () => _act(() => onGoToEnd?.call()),
        );
      case 'indent':
        return _IconKeyButton(
          icon: Icons.format_indent_increase_rounded,
          tooltip: context.l10n.actionIndent,
          enabled: !isReadOnly,
          onTap: () => _act(controller.applyIndent),
        );
      case 'outdent':
        return _IconKeyButton(
          icon: Icons.format_indent_decrease_rounded,
          tooltip: context.l10n.actionOutdent,
          enabled: !isReadOnly,
          onTap: () => _act(controller.applyOutdent),
        );
      case 'format':
        return _IconKeyButton(
          icon: Icons.auto_fix_high_rounded,
          tooltip: context.l10n.actionFormat,
          enabled: !isReadOnly && onFormat != null,
          onTap: () => _act(() => onFormat?.call()),
        );
      case 'readOnly':
        return _IconKeyButton(
          icon: isReadOnly ? Icons.lock_rounded : Icons.lock_open_rounded,
          tooltip: context.l10n.actionReadOnly,
          selected: isReadOnly,
          onTap: () => _act(() => onToggleReadOnly?.call()),
        );
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    void setFocusLock(bool locked) {
      if (editorFocusNode is EditorFocusNode) {
        (editorFocusNode as EditorFocusNode).keepFocusLocked = locked;
      }
    }

    final hasSymbols = showSymbols && symbols.isNotEmpty;
    final hasActions = showActions && actions.isNotEmpty;

    return Listener(
      onPointerDown: (_) => setFocusLock(true),
      onPointerUp: (_) => setFocusLock(false),
      onPointerCancel: (_) => setFocusLock(false),
      child: TapRegion(
        groupId: EditableText,
        child: TapRegion(
          groupId: editorFocusNode,
          child: ExcludeFocus(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                border: Border(top: BorderSide(color: cs.outlineVariant, width: 0.5)),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (hasSymbols)
                      SizedBox(
                        height: 40,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                          itemCount: symbols.length,
                          separatorBuilder: (context, index) => const SizedBox(width: 4),
                          itemBuilder: (context, index) {
                            final symbol = symbols[index];
                            final isTab = symbol == 'Tab';
                            return _KeyButton(
                              label: symbol,
                              onTap: isTab
                                  ? () => _act(controller.applyIndent)
                                  : () => _insert(symbol),
                            );
                          },
                        ),
                      ),
                    if (hasActions)
                      SizedBox(
                        height: 40,
                        child: ListenableBuilder(
                          listenable: controller,
                          builder: (context, child) {
                            return ListView.separated(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                              itemCount: actions.length,
                              separatorBuilder: (context, index) => const SizedBox(width: 4),
                              itemBuilder: (context, index) {
                                final widget = _buildActionButton(context, actions[index], cs);
                                return widget ?? const SizedBox.shrink();
                              },
                            );
                          },
                        ),
                      ),
                    if (showScrubber)
                      _CaretScrubber(controller: controller, editorFocusNode: editorFocusNode),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A single symbol/text key -- sized to its label so `Tab` isn't cramped
/// next to single-character keys.
class _KeyButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _KeyButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        canRequestFocus: false,
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minWidth: 34),
          height: 34,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'JetBrains Mono',
              fontFamilyFallback: const ['monospace'],
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

/// An icon key, optionally disabled (used for undo/redo when there's
/// nothing to undo/redo).
class _IconKeyButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool enabled;
  final bool selected;

  const _IconKeyButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.enabled = true,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: selected ? cs.primaryContainer : cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        canRequestFocus: false,
        borderRadius: BorderRadius.circular(6),
        onTap: enabled ? onTap : null,
        child: Container(
          width: 40,
          height: 34,
          alignment: Alignment.center,
          child: Tooltip(
            message: tooltip,
            child: Icon(
              icon,
              size: 20,
              color: !enabled
                  ? cs.onSurface.withValues(alpha: 0.35)
                  : (selected ? cs.onPrimaryContainer : cs.onSurface),
            ),
          ),
        ),
      ),
    );
  }
}

/// A full-width horizontal drag strip: dragging right or left moves the
/// caret forward/backward one character per [_pixelsPerStep] of travel.
/// Lives in its own row (rather than layered on the text) specifically so
/// scrubbing doesn't put a fingertip over the caret it's positioning.
class _CaretScrubber extends StatefulWidget {
  final CodeLineEditingController controller;
  final FocusNode editorFocusNode;

  const _CaretScrubber({required this.controller, required this.editorFocusNode});

  @override
  State<_CaretScrubber> createState() => _CaretScrubberState();
}

class _CaretScrubberState extends State<_CaretScrubber> {
  static const double _pixelsPerStep = 10;
  // A single fast flick can report a large delta in one callback; cap how
  // many characters one update can move the caret so that stays a scrub,
  // not a teleport.
  static const int _maxStepsPerUpdate = 20;

  double _dragAccumulator = 0;
  bool _isDragging = false;

  void _onDragStart(DragStartDetails details) {
    _dragAccumulator = 0;
    setState(() => _isDragging = true);
    if (!widget.editorFocusNode.hasFocus) {
      widget.editorFocusNode.requestFocus();
    }
  }

  void _onDragUpdate(DragUpdateDetails details) {
    _dragAccumulator += details.delta.dx;
    var steps = 0;
    while (_dragAccumulator.abs() >= _pixelsPerStep && steps < _maxStepsPerUpdate) {
      if (_dragAccumulator > 0) {
        widget.controller.moveCursor(AxisDirection.right);
        _dragAccumulator -= _pixelsPerStep;
      } else {
        widget.controller.moveCursor(AxisDirection.left);
        _dragAccumulator += _pixelsPerStep;
      }
      steps++;
    }
  }

  void _onDragEnd(DragEndDetails details) => setState(() {
    _isDragging = false;
    _dragAccumulator = 0;
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 4),
      child: Semantics(
        label: context.l10n.textEditorCaretScrubberLabel,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: _onDragStart,
          onHorizontalDragUpdate: _onDragUpdate,
          onHorizontalDragEnd: _onDragEnd,
          onHorizontalDragCancel: () => setState(() {
            _isDragging = false;
            _dragAccumulator = 0;
          }),
          child: Container(
            height: 26,
            width: double.infinity,
            decoration: BoxDecoration(
              color: _isDragging ? cs.primary.withValues(alpha: 0.16) : cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.chevron_left_rounded, size: 16, color: cs.onSurfaceVariant),
                const SizedBox(width: 4),
                Container(
                  width: 28,
                  height: 3,
                  decoration: BoxDecoration(
                    color: cs.onSurfaceVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded, size: 16, color: cs.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}