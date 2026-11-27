import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/utils/platform_features.dart';
import 'package:vaultexplorer/core/utils/responsive.dart';
import 'package:vaultexplorer/core/widgets/desktop_window_frame.dart';
import 'package:vaultexplorer/core/widgets/desktop_window_title_bar.dart';

/// Height of the title bar that carries a page's title (and its controls).
const double kDesktopPageTitleBarHeight = 40;

/// Whether the page at [context] sits in a window whose caption row it can
/// fill itself: a Windows window without a native title bar that is not the
/// main shell (which draws its own row, with the sidebar button and the tabs).
///
/// Such a page draws its title in the title bar through [DesktopPageTitleBar]
/// instead of in an app bar of its own, so nothing is left at the top of the
/// page. Call it from `build`.
bool pageTitleBelongsInCaption(BuildContext context) =>
    PlatformFeatures.isWindows &&
    !NativeWindowChrome.of(context) &&
    DesktopCaptionClaimsScope.maybeOf(context) != null &&
    !DockedSidebarScope.of(context) &&
    !context.titleBarHostsSidebarMenu;

/// A page title in the window's title bar, left of the minimize / maximize /
/// close buttons. [trailing] (a search box, say) sits right before them. The
/// empty stretch still drags the window and double-click still maximizes it.
///
/// [onBack] adds a back arrow in front of the title, for a page that was
/// pushed over another one; a page that has a window of its own passes none.
class DesktopPageTitleBar extends StatelessWidget {
  const DesktopPageTitleBar({
    super.key,
    required this.title,
    this.trailing,
    this.onBack,
    this.backTooltip,
  });

  final String title;
  final Widget? trailing;
  final VoidCallback? onBack;
  final String? backTooltip;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return DesktopWindowTitleBar(
      height: kDesktopPageTitleBarHeight,
      tabs: Row(
        children: [
          if (onBack != null)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: IconButton(
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                tooltip: backTooltip,
                onPressed: onBack,
                style: IconButton.styleFrom(
                  minimumSize: const Size(32, 32),
                  maximumSize: const Size(32, 32),
                  padding: EdgeInsets.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            )
          else
            const SizedBox(width: 16),
          const SizedBox(width: 8),
          // Not hit-testable, so a press on the title drags the window.
          Expanded(
            child: IgnorePointer(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}
