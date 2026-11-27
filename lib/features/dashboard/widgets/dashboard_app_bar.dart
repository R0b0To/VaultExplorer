import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/utils/responsive.dart';
import 'package:vaultexplorer/core/widgets/activity/app_bar_authenticator_button.dart';
import 'package:vaultexplorer/core/widgets/activity/app_bar_transfer_button.dart';
import 'package:vaultexplorer/core/widgets/full_screen_drag_drawer.dart';
import 'package:vaultexplorer/features/dashboard/widgets/dashboard_layout_button.dart';

/// The Home viewport's fixed shell chrome. Standalone Dashboard routes reuse
/// the same app bar above their own Scaffold body.
class DashboardAppBar extends StatelessWidget implements PreferredSizeWidget {
  const DashboardAppBar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    // A hidden docked sidebar comes back in place; there is no drawer to open.
    final showSidebar = context.showSidebarAction;
    final hideLeading =
        DockedSidebarScope.of(context) || context.titleBarHostsSidebarMenu;
    return AppBar(
    primary: false,
    // Beside a docked sidebar or under a Windows title bar toggle there is no
    // menu button needed here.
    automaticallyImplyLeading: false,
    leading: hideLeading
        ? null
        : Builder(
            builder: (ctx) => IconButton(
              icon: Icon(
                Icons.menu_rounded,
                color: Theme.of(ctx).appBarTheme.foregroundColor,
              ),
              tooltip: context.l10n.showSidebarTooltip,
              onPressed: () {
                if (showSidebar != null) {
                  showSidebar();
                  return;
                }
                final drawer = FullScreenDragDrawerScope.maybeOf(ctx);
                if (drawer != null) {
                  drawer.openDrawer();
                } else {
                  Scaffold.of(ctx).openDrawer();
                }
              },
            ),
          ),
    title: Text(
      context.l10n.appNameVaultExplorer,
      style: const TextStyle(fontWeight: FontWeight.bold),
    ),
   actions: [
      if (defaultTargetPlatform != TargetPlatform.android)
        const DashboardLayoutButton(),
      const AppBarAuthenticatorButton(),
      const AppBarTransferButton(),
      const SizedBox(width: 4),
    ],
    );
  }
}
