import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
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
    final foreground =
        appBarTheme.foregroundColor ?? theme.colorScheme.onSurface;
    return AppBar(
      automaticallyImplyLeading: false,
      leading: Builder(
        builder: (context) {
          if (drawer != null && !preferBackButton) {
            return IconButton(
              icon: Icon(Icons.menu_rounded, color: foreground),
              tooltip: context.l10n.storageLocationsTitle,
              onPressed: drawer.openDrawer,
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
          if (drawer != null) {
            return IconButton(
              icon: Icon(Icons.menu_rounded, color: foreground),
              tooltip: context.l10n.storageLocationsTitle,
              onPressed: drawer.openDrawer,
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
