import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/utils/responsive.dart';
import 'package:vaultexplorer/core/widgets/activity/app_bar_transfer_button.dart';
import 'package:vaultexplorer/core/widgets/full_screen_drag_drawer.dart';

/// Builds a browser app bar with the context of the shell that displays it.
/// Directory views can live in independently mounted tab viewports, so an
/// already-built AppBar must not retain their BuildContext when hoisted into
/// the stationary browser chrome.
typedef BrowserAppBarFactory =
    PreferredSizeWidget Function(BuildContext context);

/// A real, stable-height toolbar shown while a directory viewport is starting
/// and has not published its context-aware toolbar yet. Keeping Material chrome
/// in this slot avoids a transparent/empty frame during route and tab changes.
class BrowserAppBarFallback extends StatelessWidget
    implements PreferredSizeWidget {
  const BrowserAppBarFallback({
    super.key,
    required this.title,
    this.showBackButton = true,
    this.preferBackButton = false,
    this.onBackPressed,
  });

  final String title;
  final bool showBackButton;
  final bool preferBackButton;
  final VoidCallback? onBackPressed;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

@override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appBarTheme = theme.appBarTheme;
    final drawer = FullScreenDragDrawerScope.maybeOf(context);
    // A hidden docked sidebar comes back in place; the browser has no drawer of
    // its own then, so there would be nothing for [drawer] to open.
    final showSidebar = context.showSidebarAction;
    final titleBarOwnsMenu = context.titleBarHostsSidebarMenu;
    final VoidCallback? openMenu =
        titleBarOwnsMenu ? null : (showSidebar ?? drawer?.openDrawer);
    final foreground =
        appBarTheme.foregroundColor ?? theme.colorScheme.onSurface;
    final hideLeading =
        DockedSidebarScope.of(context) ||
        (titleBarOwnsMenu && (!preferBackButton || !showBackButton));
    return AppBar(
      automaticallyImplyLeading: false,
      leading: hideLeading
          ? null
          : Builder(
        builder: (context) {
          final menuTooltip = context.l10n.showSidebarTooltip;
          if (openMenu != null && !preferBackButton) {
            return IconButton(
              icon: Icon(Icons.menu_rounded, color: foreground),
              tooltip: menuTooltip,
              onPressed: openMenu,
            );
          }
          if (showBackButton) {
            return IconButton(
              icon: Icon(Icons.arrow_back, color: foreground),
              tooltip: context.l10n.backToDashboardTooltip,
              onPressed:
                  onBackPressed ?? () => Navigator.of(context).maybePop(),
            );
          }
          if (openMenu != null) {
            return IconButton(
              icon: Icon(Icons.menu_rounded, color: foreground),
              tooltip: menuTooltip,
              onPressed: openMenu,
            );
          }
          return const SizedBox.shrink();
        },
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      actions: const [AppBarTransferButton(), SizedBox(width: 4)],
    );
  }
}
