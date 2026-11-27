import 'package:flutter/services.dart';
import 'package:vaultexplorer/core/utils/platform_features.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/core/windowing/window_caption.dart';
import 'package:vaultexplorer/features/browser/widgets/tab_drag_session.dart';

/// Whether a tab that is dragged out of its strip follows the cursor live, as a
/// window of its own, and can be dropped into the strip of another window. Off,
/// a tab pulled out is only a floating copy, and the window opens when it is
/// let go. A single switch for it, should the live drag misbehave on some
/// system.
const bool kLiveTabDragEnabled = true;

/// The Windows runner's side of a live tab drag (see [TabDragSession]).
///
/// Only the runner knows where the cursor is on the screen, which windows are
/// where, and how to move a window that is not this app's drawing surface to
/// follow the cursor. Everywhere else live dragging is unavailable and the tab
/// strip keeps to the floating copy.
class WindowsTabDragPlatform implements TabDragPlatform {
  const WindowsTabDragPlatform();

  /// Whether this platform has a runner that can do it at all.
  static bool get isSupported =>
      kLiveTabDragEnabled && PlatformFeatures.isWindows;

  static const String _tag = 'TabDrag';

  @override
  Future<TabDragPoll?> poll(TabDragPollRequest request) async {
    try {
      final report = await kWindowChannel.invokeMapMethod<String, Object?>(
        'tabDragPoll',
        <String, Object?>{
          'carrierViewId': request.carrierViewId,
          'grabX': request.grabX,
          'grabY': request.grabY,
          'park': request.park,
          'candidates': request.candidates,
        },
      );
      if (report == null) return null;
      double number(String key, [double fallback = 0]) =>
          (report[key] as num?)?.toDouble() ?? fallback;
      final scale = number('scale', 1);
      return TabDragPoll(
        cursorX: number('cursorX'),
        cursorY: number('cursorY'),
        buttonDown: report['buttonDown'] == true,
        windowViewId: (report['windowViewId'] as num?)?.toInt(),
        originX: number('originX'),
        originY: number('originY'),
        scale: scale > 0 ? scale : 1,
      );
    } catch (error) {
      VeLog.w(_tag, 'The runner could not follow the drag', error);
      return null;
    }
  }

  @override
  Future<double> prepare(int viewId) async {
    try {
      return await kWindowChannel.invokeMethod<double>(
            'tabDragPrepare',
            <String, Object?>{'viewId': viewId},
          ) ??
          1;
    } catch (error) {
      VeLog.w(_tag, 'Could not get the window ready to be moved', error);
      return 1;
    }
  }

  @override
  Future<void> activate(int viewId) async {
    try {
      await kWindowChannel.invokeMethod<void>(
        'activateWindow',
        <String, Object?>{'viewId': viewId},
      );
    } on PlatformException catch (error) {
      // The window may be gone by now; nothing to bring forward then.
      VeLog.w(_tag, 'Could not bring the window forward', error);
    } on MissingPluginException catch (error) {
      VeLog.w(_tag, 'Could not bring the window forward', error);
    }
  }
}
