import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/features/browser/controllers/browser_tabs_provider.dart';
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
  final ValueListenable<PreferredSizeWidget?> appBarListenable;
  final Widget fallback;
  final ValueListenable<PreferredSizeWidget?> selectionAppBarListenable;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeTab = ref.watch(activeBrowserTabProvider(workspaceConfig));
    final aggregateSelection = ref.watch(
      aggregatedTabsSelectionProvider(workspaceConfig),
    );
    if (aggregateSelection.hasSelection) {
      return SizedBox(
        height: kToolbarHeight,
        child: SkinAreaScope(
          area: SkinArea.files,
          child: ValueListenableBuilder<PreferredSizeWidget?>(
            valueListenable: selectionAppBarListenable,
            builder: (context, appBar, _) => appBar ?? const DashboardAppBar(),
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
        child: ValueListenableBuilder<PreferredSizeWidget?>(
          valueListenable: appBarListenable,
          builder: (context, appBar, _) => appBar ?? fallback,
        ),
      ),
    );
  }
}
