import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/widgets/layout/adaptive_page_route.dart';
import 'package:vaultexplorer/core/windowing/secondary_windows.dart';
import 'package:vaultexplorer/core/windowing/window_caption.dart';

/// Shows a single-purpose page (unlock, mount) the way the platform expects.
///
/// On Linux and Windows the page opens in a native window of its own, sized
/// for the form, and the returned future completes when that window is gone.
/// It is centered over the window it was opened from (on Windows; on Linux the
/// window manager places it). Asking again for the same [key] brings the open
/// window forward instead of opening a second one. Everywhere else, and wherever native windows turn out
/// to be unavailable, the page is pushed with [adaptivePageRoute] (a full
/// screen page on a phone, a centered dialog on a large window), exactly as
/// before.
///
/// Returns whether the page was shown in a native window. A caller that used
/// to hand the page a route to open afterwards (see `UnlockSheet`) needs that
/// to open it itself: a window has its own `Navigator`, so a route pushed
/// from inside it would end up inside the small window.
///
/// The window outlives the page that asked for it. Nothing in [builder] may
/// hold on to that page's `ref` or `State`; capture the notifiers it needs
/// first (see `openContainerConfig`).
Future<bool> pushWindowedPage(
  BuildContext context, {
  required String key,
  required String title,
  required WidgetBuilder builder,
  Size size = const Size(480, 560),
  BoxConstraints constraints = const BoxConstraints(
    minWidth: 420,
    minHeight: 420,
  ),
}) async {
  final windows = SecondaryWindows.instance;
  // The window this page was opened from: the new one is centered over it.
  final openedFrom = View.maybeOf(context)?.viewId;
  final opened = windows.open(
    key: key,
    title: title,
    builder: builder,
    size: size,
    constraints: constraints,
    onCreated: (entry) =>
        unawaited(centerWindowOver(entry.viewId, overViewId: openedFrom)),
  );
  if (opened) {
    await windows.entryFor(key)?.closed;
    return true;
  }
  await Navigator.push<void>(
    context,
    adaptivePageRoute<void>(context, builder: builder),
  );
  return false;
}
