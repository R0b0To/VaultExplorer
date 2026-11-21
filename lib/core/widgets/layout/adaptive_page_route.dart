import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/utils/responsive.dart';
import 'package:vaultexplorer/core/widgets/layout/adaptive_route_frame.dart';

/// A route for a page that is full screen on a phone or small tablet and a
/// modal dialog on a large window (tablet landscape, desktop).
///
/// Use it where a `MaterialPageRoute` would push a single-purpose page such as
/// unlock or mount: on a large window the page opens as a centered panel over
/// the dimmed screen it came from, so the vault list stays in view, instead of
/// replacing the whole window. Escape closes it; tapping outside does not,
/// because a half-typed password is easy to lose.
///
/// [dialogWidth] and [dialogHeight] are the panel's largest size. The page
/// inside is told it has the panel's size, so a page that switches between one
/// and two columns by width gets its single-column layout.
///
/// Pass [context] from the place that opens the page.
Route<T> adaptivePageRoute<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  double dialogWidth = 520,
  double dialogHeight = 640,
  RouteSettings? settings,
}) {
  if (!context.prefersDialogs) {
    return MaterialPageRoute<T>(builder: builder, settings: settings);
  }
  return DialogRoute<T>(
    context: context,
    settings: settings,
    barrierDismissible: false,
    builder: (_) => AdaptiveRouteFrame(
      maxWidth: dialogWidth,
      maxHeight: dialogHeight,
      // The choice was made when the route was pushed; keep the panel even if
      // the window is later resized.
      minWindowWidth: 0,
      minWindowHeight: 0,
      showBackdrop: false,
      closeOnEscape: true,
      // A Builder so the page's builder gets a context inside the panel and
      // sees the panel's size, not the window's.
      child: Builder(builder: builder),
    ),
  );
}
