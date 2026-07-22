import 'package:flutter/material.dart';

/// Search field pinned above the on-screen keyboard, docked at the bottom
/// of the screen.
class BottomSearchBar extends StatefulWidget {
  final String initialQuery;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;

  const BottomSearchBar({
    super.key,
    required this.initialQuery,
    required this.onChanged,
    required this.onClose,
  });

  @override
  State<BottomSearchBar> createState() => _BottomSearchBarState();
}

class _BottomSearchBarState extends State<BottomSearchBar> {
  late final TextEditingController _ctrl;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialQuery);
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      // Sits slightly elevated above the keyboard or screen bottom
      padding: EdgeInsets.only(
        bottom: bottomInset + 8,
        left: 8,
        right: 8,
      ),
      child: SafeArea(
        top: false,
        child: Material(
          elevation: 6,
          color: cs.surfaceContainerHigh,
          shape: const StadiumBorder(), // Modern pill-shape footprint
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(
              children: [
                // Back arrow (close search) — left side
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, size: 20),
                  tooltip: 'Close search',
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.onClose,
                ),
                // Text field
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    focusNode: _focusNode,
                    onChanged: widget.onChanged,
                    textInputAction: TextInputAction.search,
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Search in this folder…',
                      hintStyle: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 14,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
                // Clear button — only when text is non-empty
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _ctrl,
                  builder: (context, value, child) {
                    if (value.text.isEmpty) return const SizedBox.shrink();
                    return IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      tooltip: 'Clear',
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        _ctrl.clear();
                        widget.onChanged('');
                      },
                    );
                  },
                ),
                // Search icon — right side
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(Icons.search_rounded, color: cs.primary, size: 20),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
