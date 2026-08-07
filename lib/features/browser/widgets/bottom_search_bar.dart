import 'package:flutter/material.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';

/// Search field pinned above the on-screen keyboard, docked at the bottom of the screen.
class BottomSearchBar extends StatefulWidget {
  final String initialQuery;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;
  final bool isDeepSearch;
  final ValueChanged<bool>? onDeepSearchToggle;
  final bool isSearchingSubfolders;

  const BottomSearchBar({
    super.key,
    required this.initialQuery,
    required this.onChanged,
    required this.onClose,
    this.isDeepSearch = false,
    this.onDeepSearchToggle,
    this.isSearchingSubfolders = false,
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
          shape: const StadiumBorder(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, size: 20),
                  tooltip: context.l10n.closeSearchTooltip,
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.onClose,
                ),
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    focusNode: _focusNode,
                    enableSuggestions: false,
                    autocorrect: false,
                    onChanged: widget.onChanged,
                    textInputAction: TextInputAction.search,
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: widget.isDeepSearch
                          ? context.l10n.searchInSubfoldersHint
                          : context.l10n.searchInThisFolderHint,
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
                if (widget.isSearchingSubfolders)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: cs.primary,
                      ),
                    ),
                  ),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _ctrl,
                  builder: (context, value, child) {
                    if (value.text.isEmpty) return const SizedBox.shrink();
                    return IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      tooltip: context.l10n.clearTooltip,
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        _ctrl.clear();
                        widget.onChanged('');
                      },
                    );
                  },
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
                        color: widget.isDeepSearch ? cs.primary : cs.onSurfaceVariant,
                        size: 20,
                      ),
                      visualDensity: VisualDensity.compact,
                      onPressed: () =>
                          widget.onDeepSearchToggle!(!widget.isDeepSearch),
                    ),
                  ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}