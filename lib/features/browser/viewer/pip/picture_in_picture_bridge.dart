import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';

/// Dart side of Android's system picture-in-picture window (see
/// `PictureInPictureController.kt`).
///
/// [PictureInPictureCoordinator] decides when a video is worth keeping on
/// screen and calls [setState]; the platform reports back through
/// [isInPictureInPicture] (the window is up) and [windowDismissed] (the
/// person closed it).
class PictureInPictureBridge {
  PictureInPictureBridge._();

  static const MethodChannel _channel = MethodChannel(
    'com.aeidolon.vaultexplorer/pip',
  );

  /// True while the activity is shown in the PiP window.
  static final ValueNotifier<bool> isInPictureInPicture = ValueNotifier<bool>(
    false,
  );

  static final StreamController<void> _dismissed =
      StreamController<void>.broadcast();

  /// Fires when the person closes the PiP window.
  static Stream<void> get windowDismissed => _dismissed.stream;

  static bool _handlerInstalled = false;

  /// Installs the handler for platform -> Dart events. Safe to call repeatedly.
  static void ensureInitialized() {
    if (_handlerInstalled) return;
    _handlerInstalled = true;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'modeChanged':
          final args = call.arguments;
          isInPictureInPicture.value = args is Map && args['active'] == true;
        case 'dismissed':
          _dismissed.add(null);
      }
      return null;
    });
  }

  /// Tells the platform whether to enter PiP when the person leaves the app,
  /// and at what aspect ratio ([width] : [height]).
  static Future<void> setState({
    required bool armed,
    required int width,
    required int height,
  }) async {
    try {
      await _channel.invokeMethod<bool>('setState', {
        'armed': armed,
        'width': width,
        'height': height,
      });
    } on PlatformException catch (e) {
      VeLog.w('PictureInPicture', 'setState failed', e);
    } on MissingPluginException {
      // No native side (tests, other platforms): nothing to arm.
    }
  }
}
