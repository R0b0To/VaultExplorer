// The bar pinned above the soft keyboard while editing a file in
// TextEditorScreen -- see docs/text editor expansion plan, Phase 2. Two
// horizontally-scrollable rows:
//   1. Symbols that are awkward to reach on a stock Android keyboard layout
//      (nested punctuation, brackets, quotes).
//   2. Undo/redo, left/right caret nav, select-word, and paste -- one-tap
//      versions of gestures that are fiddly with a fingertip on a small
//      screen.
//
// Every button re-requests focus on the editor after acting: a Material
// `InkWell` can otherwise pull keyboard focus onto itself for a frame,
// which would dismiss the soft keyboard the bar is meant to sit above.
import 'package:flutter/rendering.dart' show AxisDirection;
import 'package:material_ui/material_ui.dart';
import 'package:re_editor/re_editor.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';

class EditorAccessoryKeyBar extends StatelessWidget {
  final CodeLineEditingController controller;
  final FocusNode editorFocusNode;

  const EditorAccessoryKeyBar({
    super.key,
    required this.controller,
    required this.editorFocusNode,
  });

  static const List<String> _symbolRow = [
    'Tab', '{', '}', '[', ']', '(', ')', '=', '"', "'",
    ':', ';', '/', '\\', '<', '>', '_', '-', '&', '|', '!',
  ];

  void _act(VoidCallback action) {
    action();
    if (!editorFocusNode.hasFocus) {
      editorFocusNode.requestFocus();
    }
  }

  void _insert(String symbol) => _act(() => controller.replaceSelection(symbol));

  void _selectWord() => _act(() {
    controller.moveCursorToWordBoundaryBackward();
    controller.extendSelectionToWordBoundaryForward();
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        border: Border(top: BorderSide(color: cs.outlineVariant, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                itemCount: _symbolRow.length,
                separatorBuilder: (context, index) => const SizedBox(width: 4),
                itemBuilder: (context, index) {
                  final symbol = _symbolRow[index];
                  final isTab = symbol == 'Tab';
                  return _KeyButton(
                    label: symbol,
                    onTap: isTab ? () => _act(controller.applyIndent) : () => _insert(symbol),
                  );
                },
              ),
            ),
            SizedBox(
              height: 40,
              child: ListenableBuilder(
                listenable: controller,
                builder: (context, child) {
                  return ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    children: [
                      _IconKeyButton(
                        icon: Icons.undo_rounded,
                        tooltip: context.l10n.undoTooltip,
                        enabled: controller.canUndo,
                        onTap: () => _act(controller.undo),
                      ),
                      const SizedBox(width: 4),
                      _IconKeyButton(
                        icon: Icons.redo_rounded,
                        tooltip: context.l10n.redoTooltip,
                        enabled: controller.canRedo,
                        onTap: () => _act(controller.redo),
                      ),
                      const SizedBox(width: 4),
                      _IconKeyButton(
                        icon: Icons.keyboard_arrow_left_rounded,
                        tooltip: context.l10n.textEditorMoveCursorLeftTooltip,
                        onTap: () => _act(() => controller.moveCursor(AxisDirection.left)),
                      ),
                      const SizedBox(width: 4),
                      _IconKeyButton(
                        icon: Icons.keyboard_arrow_right_rounded,
                        tooltip: context.l10n.textEditorMoveCursorRightTooltip,
                        onTap: () => _act(() => controller.moveCursor(AxisDirection.right)),
                      ),
                      const SizedBox(width: 4),
                      _IconKeyButton(
                        icon: Icons.highlight_alt_rounded,
                        tooltip: context.l10n.textEditorSelectWordTooltip,
                        onTap: _selectWord,
                      ),
                      const SizedBox(width: 4),
                      _IconKeyButton(
                        icon: Icons.content_paste_rounded,
                        tooltip: context.l10n.paste,
                        onTap: () => _act(controller.paste),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
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

  const _IconKeyButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
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
              color: enabled ? cs.onSurface : cs.onSurface.withValues(alpha: 0.35),
            ),
          ),
        ),
      ),
    );
  }
}
