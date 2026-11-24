import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';

/// What the app asks of the platform runner about the main window (Linux and
/// Windows).
///
/// The main window is the one the runner creates at startup. It owns the
/// Flutter engine and the widget tree that every other window is drawn into
/// (see `SecondaryWindows`), so it cannot be destroyed while another window is
/// still open: the engine, the mounted vaults and the other windows would go
/// with it.
///
/// To let a window outlive the one it was opened from, as a file manager's
/// windows do, the runner therefore *hides* the main window when it is closed
/// instead of destroying it, and the app ends when the last window that can
/// stand on its own closes. The runner owns the hiding (the close request
/// arrives there first); this class tells it when to do that and when to
/// finish the job.
///
/// Every call is fire-and-forget and safe to make on a platform or runner that
/// does not answer: the main window then simply closes with everything else,
/// as it always did.
///
/// Set `VE_SURVIVE_MAIN_CLOSE=0` in the environment to switch this off and get
/// that behaviour back.
abstract final class MainWindowHost {
  static const String _logTag = 'MainWindowHost';

  // The channel the runners answer window calls on. window_caption.dart names
  // the same channel (kWindowChannel) but imports secondary_windows.dart, which
  // imports this file, so it is repeated here instead of creating an import
  // cycle.
  static const MethodChannel _channel = MethodChannel('vaultexplorer/window');

  static bool get _enabled =>
      !kIsWeb &&
      (Platform.isLinux || Platform.isWindows) &&
      Platform.environment['VE_SURVIVE_MAIN_CLOSE'] != '0';

  static bool _independentWindowsOpen = false;

  /// Reports whether a window that can outlive the main one is open. Call it
  /// whenever that changes (repeating the same value is harmless).
  ///
  /// While one is open, closing the main window hides it instead of destroying
  /// it. When the last one closes, a main window that was hidden for its sake
  /// has no reason left to exist and the app ends; with the main window on
  /// screen nothing happens beyond the hiding being switched off.
  static void setIndependentWindowsOpen(bool open) {
    if (open == _independentWindowsOpen) return;
    _independentWindowsOpen = open;
    unawaited(_call('setHideOnClose', <String, Object?>{'enabled': open}));
    if (!open) unawaited(_call('quitIfMainHidden'));
  }

  /// Shows the main window again if it was hidden by being closed. It does not
  /// take the focus, and does nothing when the window is already on screen
  /// (minimized or behind another window included).
  ///
  /// The lock gate is drawn by the main window, so whatever locks the app calls
  /// this before it closes the other windows: otherwise nothing would be left
  /// on screen.
  static void revealIfHidden() {
    unawaited(_call('revealMainWindow'));
  }

  static Future<void> _call(String method, [Object? arguments]) async {
    if (!_enabled) return;
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      // A runner that predates these calls: the main window closes as before.
    } catch (error) {
      VeLog.w(_logTag, 'The runner did not accept "$method"', error);
    }
  }
}
