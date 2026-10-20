import 'package:material_ui/material_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/features/browser/controllers/browser_tabs_provider.dart';
import 'package:vaultexplorer/features/browser/widgets/browser_app_bar_factory.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area_scope.dart';
import 'package:vaultexplorer/features/dashboard/widgets/dashboard_app_bar.dart';

/// Stationary app-bar slot for the browser shell. Home chrome is built by the
/// shell; the active directory viewport supplies its context-aware actions.
class AdaptiveBrowserAppBar extends ConsumerWidget
    implements PreferredSizeWidget {
  const AdaptiveBrowserAppBar({
    super.key,
    required this.workspaceConfig,
    required this.appBarListenable,
    required this.fallback,
    required this.selectionAppBarListenable,
  });

  final BrowserTabsConfig workspaceConfig;
  final ValueListenable<BrowserAppBarFactory?> appBarListenable;
  final Widget fallback;
  final ValueListenable<BrowserAppBarFactory?> selectionAppBarListenable;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeTab = ref.watch(activeBrowserTabProvider(workspaceConfig));
    final aggregateSelection = ref.watch(
      aggregatedTabsSelectionProvider(workspaceConfig),
    );
    return ValueListenableBuilder<BrowserAppBarFactory?>(
      valueListenable: selectionAppBarListenable,
      builder: (context, selectionAppBar, _) {
        if (aggregateSelection.hasSelection && selectionAppBar != null) {
          return SizedBox(
            height: kToolbarHeight,
            child: SkinAreaScope(
              area: SkinArea.files,
              child: Builder(
                builder: (appBarContext) => selectionAppBar(appBarContext),
              ),
            ),
          );
        }
        if (activeTab?.isDashboard == true) {
          return const SizedBox(
            height: kToolbarHeight,
            child: SkinAreaScope(
              area: SkinArea.dashboard,
              child: DashboardAppBar(),
            ),
          );
        }
        return SizedBox(
          height: kToolbarHeight,
          child: SkinAreaScope(
            area: SkinArea.files,
            child: ValueListenableBuilder<BrowserAppBarFactory?>(
              valueListenable: appBarListenable,
              builder: (context, appBarFactory, _) =>
                  appBarFactory?.call(context) ?? fallback,
            ),
          ),
        );
      },
    );
  }
}
