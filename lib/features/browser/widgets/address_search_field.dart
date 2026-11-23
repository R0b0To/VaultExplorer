import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';

/// Explorer-style search box that sits beside the breadcrumb path on desktop,
/// and in the Home row of the dashboard.
///
/// A rounded, always-visible input with the search icon at its end. It owns
/// only the text; the screen that hosts it decides what the query filters.
/// [query] is the screen's current query: when it changes from outside (a
/// folder change cleared the search, say) the field follows.
class AddressSearchField extends StatefulWidget {
  const AddressSearchField({
    super.key,
    required this.query,
    required this.onChanged,
    required this.onClear,
    required this.hintText,
    this.focusNode,
    this.height = 32,
    this.isSearching = false,
    this.isDeepSearch = false,
    this.onDeepSearchToggle,
  });

  final String query;
  final ValueChanged<String> onChanged;

  /// Clear button or Escape: the screen closes the search entirely.
  final VoidCallback onClear;
  final String hintText;
  final FocusNode? focusNode;
  final double height;

  /// Shows a small spinner while a subfolder scan is running.
  final bool isSearching;

  /// "Search subfolders" toggle, shown only when [onDeepSearchToggle] is set.
  final bool isDeepSearch;
  final ValueChanged<bool>? onDeepSearchToggle;

  @override
  State<AddressSearchField> createState() => _AddressSearchFieldState();
}

class _AddressSearchFieldState extends State<AddressSearchField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.query,
  );
  FocusNode? _ownFocus;

  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  @override
  void didUpdateWidget(covariant AddressSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Follow a query changed from elsewhere, but never rewrite what the
    // person is typing: that would reset the caret.
    if (widget.query != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.query,
        selection: TextSelection.collapsed(offset: widget.query.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _ownFocus?.dispose();
    super.dispose();
  }

  void _clear() {
    _controller.clear();
    widget.onClear();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Focus(
      // Escape empties the box and hands the keyboard back to the list.
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape &&
            (_controller.text.isNotEmpty || _focus.hasFocus)) {
          _clear();
          _focus.unfocus();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Container(
        height: widget.height,
        padding: const EdgeInsets.only(left: 10),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focus,
                autocorrect: false,
                textAlignVertical: TextAlignVertical.center,
                onChanged: widget.onChanged,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  hintStyle: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 14,
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            if (widget.isSearching)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: cs.primary,
                  ),
                ),
              ),
            if (widget.onDeepSearchToggle != null)
              Tooltip(
                message: widget.isDeepSearch
                    ? context.l10n.deepSearchEnabledTooltip
                    : context.l10n.deepSearchDisabledTooltip,
                child: IconButton(
                  icon: Icon(
                    widget.isDeepSearch
                        ? Icons.account_tree_rounded
                        : Icons.account_tree_outlined,
                    color: widget.isDeepSearch
                        ? cs.primary
                        : cs.onSurfaceVariant,
                  ),
                  iconSize: 16,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 28,
                    height: 28,
                  ),
                  onPressed: () =>
                      widget.onDeepSearchToggle!(!widget.isDeepSearch),
                ),
              ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _controller,
              builder: (context, value, _) => value.text.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.only(left: 4, right: 10),
                      child: Icon(
                        Icons.search_rounded,
                        size: 16,
                        color: cs.onSurfaceVariant,
                      ),
                    )
                  : IconButton(
                      icon: const Icon(Icons.close_rounded),
                      iconSize: 16,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 28,
                        height: 28,
                      ),
                      tooltip: context.l10n.clearTooltip,
                      onPressed: _clear,
                    ),
            ),
            const SizedBox(width: 2),
          ],
        ),
      ),
    );
  }
}
