// Flutter's desktop windowing API is experimental and lives in
// `package:flutter/src/`, so the imports below are deliberate. Everything that
// touches those internals is kept in lib/core/windowing/ so a rename in a
// future Flutter release is a change in this folder only.
// ignore_for_file: invalid_use_of_internal_member, implementation_imports
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/src/foundation/_features.dart' as flutter_features;
import 'package:flutter/src/widgets/_window.dart' as flutter_window;
import 'package:flutter/widgets.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';

/// Gate for native secondary windows (Linux and Windows only).
///
/// On the stable channel `flutter config --enable-windowing` does not exist
/// and the framework keeps `isWindowingEnabled` false, which makes every
/// windowing API throw. The flag is a plain mutable variable though, so it is
/// switched on here instead, and only when a window is actually about to be
/// opened. That is deliberate:
///
///  * Nothing changes at startup, on any platform. The binding keeps its
///    "unsupported" windowing owner until the first window is requested.
///  * Android never gets near any of this.
///  * If the embedder cannot provide windows, [ensureReady] returns false and
///    the caller keeps using the in-window route it used before.
///
/// Set `VE_MULTI_WINDOW=0` in the environment to switch the feature off.
abstract final class DesktopWindowing {
  static const String _logTag = 'DesktopWindowing';

  static bool _attempted = false;
  static bool _ready = false;

  /// Whether this build can ever open a native secondary window.
  static bool get isSupportedPlatform =>
      !kIsWeb &&
      (Platform.isLinux || Platform.isWindows) &&
      Platform.environment['VE_MULTI_WINDOW'] != '0';

  /// Turns the windowing API on (once) and installs the platform's windowing
  /// owner. Returns whether native windows can be opened.
  ///
  /// A failed attempt is remembered, so a broken embedder costs one logged
  /// warning rather than an exception on every call.
  static bool ensureReady() {
    if (_ready) return true;
    if (_attempted || !isSupportedPlatform) return false;
    _attempted = true;
    try {
      flutter_features.isWindowingEnabled = true;
      WidgetsBinding.instance.windowingOwner = flutter_window
          .createDefaultWindowingOwner();
      _ready = true;
    } catch (error) {
      flutter_features.isWindowingEnabled = false;
      VeLog.w(
        _logTag,
        'Native windows are unavailable; falling back to in-window pages',
        error,
      );
    }
    return _ready;
  }
}
