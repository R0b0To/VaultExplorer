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
/// [leading] replaces it with a button of the page's own.
class DesktopPageTitleBar extends StatelessWidget {
  const DesktopPageTitleBar({
    super.key,
    this.title,
    this.titleWidget,
    this.titleInteractive = false,
    this.leading,
    this.trailing,
    this.onBack,
    this.backTooltip,
  }) : assert(title != null || titleWidget != null);

  final String? title;

  /// Used instead of [title] when the page's title is more than a string.
  final Widget? titleWidget;

  /// Whether [titleWidget] takes presses of its own. Otherwise they fall
  /// through to the title bar, which drags the window.
  final bool titleInteractive;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onBack;
  final String? backTooltip;

  /// Buttons and segmented controls are sized for a pointer in a 40px bar.
  Widget _compact(BuildContext context, Widget child) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        visualDensity: VisualDensity.compact,
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(
            minimumSize: const Size(32, 32),
            maximumSize: const Size(36, 36),
            padding: EdgeInsets.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final titleStyle = textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w600,
    );
    final Widget titleChild = titleWidget != null
        ? DefaultTextStyle.merge(
            style: titleStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            child: Align(alignment: Alignment.centerLeft, child: titleWidget),
          )
        : Text(
            title!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: titleStyle,
          );
    return DesktopWindowTitleBar(
      height: kDesktopPageTitleBarHeight,
      tabs: Row(
        children: [
          if (leading != null)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: _compact(context, leading!),
            )
          else if (onBack != null)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: _compact(
                context,
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  tooltip: backTooltip,
                  onPressed: onBack,
                ),
              ),
            )
          else
            const SizedBox(width: 16),
          const SizedBox(width: 8),
          // Not hit-testable unless asked to, so a press on the title drags
          // the window.
          Expanded(
            child: IgnorePointer(ignoring: !titleInteractive, child: titleChild),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            _compact(context, trailing!),
          ],
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

/// A [Scaffold] with an [AppBar], for a page that is pushed as a route of its
/// own (the tools). Where the window draws its own caption row
/// ([pageTitleBelongsInCaption]) the app bar's title, leading button and
/// actions move into that title bar and the page has no bar of its own;
/// everywhere else it is the plain Scaffold with the plain AppBar.
///
/// In the title bar a pushed page keeps a back arrow (it is how one leaves the
/// tool), unless it has a [leading] button of its own.
class CaptionScaffold extends StatelessWidget {
  const CaptionScaffold({
    super.key,
    this.title,
    this.appBar,
    this.captionTitle,
    this.captionTitleInteractive = false,
    this.leading,
    this.actions,
    this.bottom,
    this.appBarBackgroundColor,
    this.elevation,
    this.automaticallyImplyLeading = true,
    this.body,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.backgroundColor,
    this.resizeToAvoidBottomInset,
  }) : assert(
         title != null || appBar != null,
         'Give the title, or a whole app bar to take it from.',
       );

  /// The app bar's title.
  final Widget? title;

  /// A ready-made app bar to use instead of [title], [leading], [actions] and
  /// [bottom] (for a page that builds its app bar elsewhere): it is the app bar
  /// itself where there is no title bar to host it, and where there is one its
  /// title, leading button, actions and bottom are moved into that title bar.
  final AppBar? appBar;

  /// What stands in the title bar instead of [title], for a title that needs
  /// more than the 40px bar gives it (two lines, say).
  final Widget? captionTitle;
  final bool captionTitleInteractive;
  final Widget? leading;
  final List<Widget>? actions;

  /// Drawn under the title bar (a progress line).
  final PreferredSizeWidget? bottom;
  final Color? appBarBackgroundColor;
  final double? elevation;
  final bool automaticallyImplyLeading;
  final Widget? body;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final Color? backgroundColor;
  final bool? resizeToAvoidBottomInset;

  @override
  Widget build(BuildContext context) {
    final inCaption = pageTitleBelongsInCaption(context);
    final scaffold = Scaffold(
      appBar: inCaption
          ? null
          : appBar ??
                AppBar(
              title: title,
              leading: leading,
              actions: actions,
              bottom: bottom,
              backgroundColor: appBarBackgroundColor,
              elevation: elevation,
              automaticallyImplyLeading: automaticallyImplyLeading,
            ),
      body: body,
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
      backgroundColor: backgroundColor,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
    );
    if (!inCaption) return scaffold;

    final barLeading = appBar?.leading ?? leading;
    final barActions = appBar?.actions ?? actions;
    final barBottom = appBar?.bottom ?? bottom;
    final canGoBack =
        barLeading == null &&
        (appBar?.automaticallyImplyLeading ?? automaticallyImplyLeading) &&
        (ModalRoute.of(context)?.canPop ?? false);
    final trailing = (barActions == null || barActions.isEmpty)
        ? null
        : Row(mainAxisSize: MainAxisSize.min, children: barActions);
    return Column(
      children: [
        DesktopPageTitleBar(
          titleWidget: captionTitle ?? appBar?.title ?? title,
          titleInteractive: captionTitle != null && captionTitleInteractive,
          leading: barLeading,
          trailing: trailing,
          onBack: canGoBack ? () => Navigator.of(context).maybePop() : null,
          backTooltip: MaterialLocalizations.of(context).backButtonTooltip,
        ),
        if (barBottom != null)
          SizedBox(
            height: barBottom.preferredSize.height,
            child: barBottom,
          ),
        Expanded(child: scaffold),
      ],
    );
  }
}
