import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';

/// Dart side of Android's system picture-in-picture window (see
/// `PictureInPictureController.kt`).
///
/// [PictureInPictureCoordinator] decides when a video is worth keeping on
/// screen: [setState] arms the automatic entry when the app is left, [enter]
/// enters right away. The platform reports back through
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

  /// Whether this device can show a picture-in-picture window at all. False
  /// until the platform has answered.
  static final ValueNotifier<bool> isSupported = ValueNotifier<bool>(false);

  static final StreamController<void> _dismissed =
      StreamController<void>.broadcast();

  /// Fires when the person closes the PiP window.
  static Stream<void> get windowDismissed => _dismissed.stream;

  static bool _handlerInstalled = false;

  /// Installs the handler for platform -> Dart events. Safe to call repeatedly.
  static void ensureInitialized() {
    if (_handlerInstalled) return;
    _handlerInstalled = true;
    unawaited(_loadSupport());
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

  static Future<void> _loadSupport() async {
    try {
      isSupported.value =
          await _channel.invokeMethod<bool>('isSupported') ?? false;
    } on PlatformException catch (e) {
      VeLog.w('PictureInPicture', 'isSupported failed', e);
    } on MissingPluginException {
      // No native side (tests, other platforms): no picture-in-picture.
    }
  }

  /// Enters the picture-in-picture window now, at [width] : [height]. Returns
  /// whether the system accepted it.
  static Future<bool> enter({required int width, required int height}) async {
    try {
      return await _channel.invokeMethod<bool>('enter', {
            'width': width,
            'height': height,
          }) ??
          false;
    } on PlatformException catch (e) {
      VeLog.w('PictureInPicture', 'enter failed', e);
      return false;
    } on MissingPluginException {
      return false;
    }
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
