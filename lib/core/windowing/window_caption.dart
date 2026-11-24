import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:vaultexplorer/core/windowing/secondary_windows.dart';

/// The channel the Windows runner answers the caption row's calls on
/// (minimize, maximize, close, drag).
const MethodChannel kWindowChannel = MethodChannel('vaultexplorer/window');

/// Arguments that make a [kWindowChannel] call act on the window [context] is
/// in. The runner answers for the main window when there are none, so the main
/// window sends none; a secondary window has to name its own view, or its
/// caption buttons would act on the main window.
Map<String, Object?>? windowChannelArgsFor(BuildContext context) {
  if (SecondaryWindowScope.maybeOf(context) == null) return null;
  final viewId = View.maybeOf(context)?.viewId;
  return viewId == null ? null : <String, Object?>{'viewId': viewId};
}

/// Asks the runner to hide the OS title bar of the secondary window that shows
/// [viewId], so the Flutter-drawn caption row (the one the main window has)
/// can take its place. Throws when the runner cannot do that, which is the
/// caller's cue to keep the native title bar.
Future<void> useCustomWindowCaption(int viewId) =>
    kWindowChannel.invokeMethod<void>('useCustomCaption', <String, Object?>{
      'viewId': viewId,
    });
