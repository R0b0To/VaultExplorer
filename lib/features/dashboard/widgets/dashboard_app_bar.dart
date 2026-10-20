import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/widgets/activity/app_bar_authenticator_button.dart';
import 'package:vaultexplorer/core/widgets/activity/app_bar_transfer_button.dart';
import 'package:vaultexplorer/core/widgets/full_screen_drag_drawer.dart';

/// The Home viewport's fixed shell chrome. Standalone Dashboard routes reuse
/// the same app bar above their own Scaffold body.
class DashboardAppBar extends StatelessWidget implements PreferredSizeWidget {
  const DashboardAppBar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) => AppBar(
    primary: false,
    leading: Builder(
      builder: (ctx) => IconButton(
        icon: Icon(
          Icons.menu_rounded,
          color: Theme.of(ctx).appBarTheme.foregroundColor,
        ),
        tooltip: context.l10n.storageLocationsTitle,
        onPressed: () {
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
    actions: const [
      AppBarAuthenticatorButton(),
      AppBarTransferButton(),
      SizedBox(width: 4),
    ],
  );
}
