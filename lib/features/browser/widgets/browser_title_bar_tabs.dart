import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/widgets/desktop_window_title_bar.dart';
import 'package:vaultexplorer/features/browser/controllers/browser_tabs_provider.dart';
import 'package:vaultexplorer/features/browser/widgets/browser_tab_strip.dart';

/// The browser tabs as they sit in a desktop window's title row (the main
/// window's and a file manager window's): one strip, or one per pane while the
/// two panes are shown side by side, lined up with the panes below.
///
/// [splitFraction] is where the browser puts the divider between the panes
/// (`BrowserTabsShell.onDualPaneSplitFractionChanged`). [docked] says whether a
/// permanent sidebar sits at the left of the window, which changes how much of
/// the row's width the panes below do not share with it.
class BrowserTitleBarTabs extends ConsumerWidget {
  const BrowserTitleBarTabs({
    super.key,
    required this.workspace,
    required this.docked,
    required this.splitFraction,
    required this.onNewTab,
    required this.onDuplicate,
  });

  final BrowserTabsConfig workspace;
  final bool docked;
  final ValueListenable<double> splitFraction;
  final VoidCallback onNewTab;
  final ValueChanged<BrowserTabState> onDuplicate;

  Widget _strip({TabPane? pane}) => BrowserTabStrip(
    workspaceConfig: workspace,
    onNewTab: onNewTab,
    onDuplicate: onDuplicate,
    pane: pane,
    height: 32,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSplit = ref.watch(
      browserTabsProvider(workspace).select((state) => state.isSplit),
    );
    if (!isSplit) return _strip();
    return LayoutBuilder(
      builder: (context, constraints) => ValueListenableBuilder<double>(
        valueListenable: splitFraction,
        builder: (context, fraction, _) {
          final paneSplitInset = docked ? 0.0 : 48.0;
          final pageWidth =
              constraints.maxWidth +
              kDesktopTitleBarTrailingWidth +
              paneSplitInset;
          final firstExtent =
              (fraction * (pageWidth - 8) - paneSplitInset)
                  .clamp(
                    0.0,
                    (constraints.maxWidth - 8).clamp(0.0, double.infinity),
                  )
                  .toDouble();
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: firstExtent,
                child: _strip(pane: TabPane.primary),
              ),
              Container(
                width: 8,
                color: Theme.of(context).scaffoldBackgroundColor,
                alignment: Alignment.center,
              ),
              Expanded(child: _strip(pane: TabPane.secondary)),
            ],
          );
        },
      ),
    );
  }
}
