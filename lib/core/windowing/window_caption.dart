import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:vaultexplorer/core/utils/platform_features.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';

/// The channel the Windows runner answers the caption row's calls on
/// (minimize, maximize, close, drag).
const MethodChannel kWindowChannel = MethodChannel('vaultexplorer/window');

/// Arguments that make a [kWindowChannel] call act on the window [context] is
/// in.
///
/// The runner answers for its own window when there are none. That is the
/// window the app is drawn in when it runs without native windows (the
/// platform's implicit view), so it sends none. Every other window, the main
/// window of the desktop build included, has to name its own view, or its
/// caption buttons would act on the runner's window, which shows nothing.
Map<String, Object?>? windowChannelArgsFor(BuildContext context) {
  final viewId = View.maybeOf(context)?.viewId;
  if (viewId == null) return null;
  if (viewId == PlatformDispatcher.instance.implicitView?.viewId) return null;
  return <String, Object?>{'viewId': viewId};
}

/// Asks the runner to hide the OS title bar of the window that shows [viewId],
/// so the Flutter-drawn caption row can take its place. Throws when the runner
/// cannot do that, which is the caller's cue to keep the native title bar.
Future<void> useCustomWindowCaption(int viewId) =>
    kWindowChannel.invokeMethod<void>('useCustomCaption', <String, Object?>{
      'viewId': viewId,
    });

/// Tells the Windows runner that the app draws every window, the main one
/// included, as a view of its own, so the window the runner created shows
/// nothing and must stay hidden. Without it the runner shows that empty window
/// when the first frame of any window is ready.
///
/// Not needed on Linux, whose runner shows its window from that window's own
/// first frame. Never throws: a runner that does not know the call leaves
/// things as they were.
Future<void> declareRunnerWindowUnused() async {
  if (!PlatformFeatures.isWindows) return;
  try {
    await kWindowChannel.invokeMethod<void>('implicitWindowUnused');
  } catch (error) {
    VeLog.w('WindowCaption', 'The runner did not accept the call', error);
  }
}

/// Moves the window that shows [viewId] so that the mouse cursor ends up
/// [anchor] (logical pixels) inside its top-left corner, and keeps it on the
/// screen the cursor is on.
///
/// Used for a window opened by dragging a tab out of another one, so that it
/// appears where the tab was let go. Windows only: that is where the runner
/// can answer. Elsewhere the window manager places new windows itself and this
/// does nothing. Never throws; a runner that does not know the call (or a
/// window that is already gone) leaves the window where the platform put it.
Future<void> placeWindowAtCursor(
  int viewId, {
  Offset anchor = Offset.zero,
}) async {
  if (!PlatformFeatures.isWindows) return;
  try {
    await kWindowChannel.invokeMethod<void>('placeAtCursor', <String, Object?>{
      'viewId': viewId,
      'anchorX': anchor.dx,
      'anchorY': anchor.dy,
    });
  } catch (error) {
    VeLog.w('WindowCaption', 'Could not place the window at the cursor', error);
  }
}

/// Moves the window that shows [viewId] to the middle of the window that shows
/// [overViewId] (the one it was opened from), keeping it on that window's
/// screen. Without [overViewId], or when that window is hidden or minimized, it
/// is centered on the screen it is already on.
///
/// Windows only: the Linux window manager places new windows itself, and the
/// window API has no way to ask it for more. Never throws. The native window of
/// a view that was only just created can take a moment to exist, so a call that
/// finds none is tried again a few times.
Future<void> centerWindowOver(int viewId, {int? overViewId}) async {
  if (!PlatformFeatures.isWindows) return;
  const attempts = 4;
  for (var attempt = 1; attempt <= attempts; attempt++) {
    try {
      await kWindowChannel.invokeMethod<void>('centerOverWindow', <String, Object?>{
        'viewId': viewId,
        if (overViewId != null) 'overViewId': overViewId,
      });
      return;
    } catch (error) {
      if (attempt == attempts) {
        VeLog.w('WindowCaption', 'Could not center the window', error);
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
  }
}

/// Makes the window that shows [viewId] impossible to resize: the runner takes
/// away its sizing border and its maximize box, so dragging an edge, snapping
/// it and maximizing it all do nothing.
///
/// Windows only. Elsewhere the window is pinned to its size by its constraints
/// alone (see `SecondaryWindows.open`). Never throws; a runner that does not
/// know the call leaves the window as it was, and the constraints still hold.
Future<void> lockWindowSize(int viewId) async {
  if (!PlatformFeatures.isWindows) return;
  try {
    await kWindowChannel.invokeMethod<void>('lockSize', <String, Object?>{
      'viewId': viewId,
    });
  } catch (error) {
    VeLog.w('WindowCaption', 'Could not lock the window size', error);
  }
}

/// Puts the window that shows [viewId] in the bottom-right corner of the work
/// area of the screen it is on (clear of the taskbar), like a notification.
///
/// Windows only; elsewhere the window manager places new windows itself. Never
/// throws. The native window of a view that was only just created can take a
/// moment to exist, so a call that finds none is tried again a few times.
Future<void> dockWindowBottomRight(int viewId) async {
  if (!PlatformFeatures.isWindows) return;
  const attempts = 4;
  for (var attempt = 1; attempt <= attempts; attempt++) {
    try {
      await kWindowChannel.invokeMethod<void>('dockBottomRight', <String, Object?>{
        'viewId': viewId,
      });
      return;
    } catch (error) {
      if (attempt == attempts) {
        VeLog.w('WindowCaption', 'Could not dock the window', error);
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
  }
}

/// Sets the height of the window that shows [viewId] to [height] logical
/// pixels of content, keeping its width and its bottom edge where they are (so
/// a window docked in a corner grows upward), and keeping it on the screen.
///
/// Windows only. Never throws.
Future<void> setWindowContentHeight(int viewId, double height) async {
  if (!PlatformFeatures.isWindows) return;
  try {
    await kWindowChannel.invokeMethod<void>('setContentHeight', <String, Object?>{
      'viewId': viewId,
      'height': height,
    });
  } catch (error) {
    VeLog.w('WindowCaption', 'Could not resize the window', error);
  }
}

/// Puts a window into real fullscreen (no frame, covering its whole monitor,
/// taskbar included) or back, and returns whether the runner did it.
///
/// [windowArgs] names the window, as [windowChannelArgsFor] gives it. Taking
/// them rather than a context lets a page that is being disposed leave
/// fullscreen again. Windows only: where the runner cannot (Linux), this
/// returns false and the caller keeps whatever it did to its own chrome. Never
/// throws.
Future<bool> setWindowFullscreen(
  Map<String, Object?>? windowArgs,
  bool fullscreen,
) async {
  if (!PlatformFeatures.isWindows) return false;
  try {
    await kWindowChannel.invokeMethod<bool>('setFullscreen', <String, Object?>{
      ...?windowArgs,
      'fullscreen': fullscreen,
    });
    return true;
  } catch (error) {
    VeLog.w('WindowCaption', 'Could not change fullscreen', error);
    return false;
  }
}
