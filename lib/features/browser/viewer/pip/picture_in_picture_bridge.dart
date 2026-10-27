import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';

/// A video's aspect ratio as the integer pair the platform wants (a fixed
/// denominator keeps it exact; the platform clamps it to what Android accepts).
({int width, int height}) pictureInPictureRatio(double aspectRatio) => (
  width: (aspectRatio * 1000).round().clamp(1, 100000),
  height: 1000,
);

/// Dart side of Android's system picture-in-picture (see
/// `PictureInPictureController.kt`).
///
/// Two ways to get a video into the PiP window:
///  * [startWindow], the viewer's button: a separate window activity takes
///    over the video while the app itself stays usable behind it. The window
///    reports back on [windowEvents] (`entered`, `expanded`, `closed`,
///    `failed`); [closeWindow] ends it.
///  * [setState], the "automatic picture-in-picture" setting: the whole app
///    becomes the PiP window when it is left, reported through
///    [isInPictureInPicture] and [windowDismissed].
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

  static final StreamController<String> _windowEvents =
      StreamController<String>.broadcast();

  /// What the PiP window activity did: `entered`, `expanded` (the person tapped
  /// it to go back to the app), `closed` (they dismissed it) or `failed`.
  static Stream<String> get windowEvents => _windowEvents.stream;

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
        case 'windowEvent':
          final payload = call.arguments;
          final event = payload is Map ? payload['event'] : null;
          if (event is String) _windowEvents.add(event);
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

  /// Opens the picture-in-picture window for the video the native player is
  /// playing, at [width] : [height], and completes once it is on screen.
  /// Returns false when it could not be shown (or took too long).
  static Future<bool> startWindow({
    required int width,
    required int height,
  }) async {
    final outcome = Completer<bool>();
    final subscription = windowEvents.listen((event) {
      if (outcome.isCompleted) return;
      outcome.complete(event == 'entered');
    });
    try {
      final started =
          await _channel.invokeMethod<bool>('startWindow', {
            'width': width,
            'height': height,
          }) ??
          false;
      if (!started) return false;
      return await outcome.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => false,
      );
    } on PlatformException catch (e) {
      VeLog.w('PictureInPicture', 'startWindow failed', e);
      return false;
    } on MissingPluginException {
      return false;
    } finally {
      await subscription.cancel();
    }
  }

  /// Reshapes the open picture-in-picture window to [width] : [height] (the
  /// next video has a different aspect ratio).
  static Future<void> setWindowRatio({
    required int width,
    required int height,
  }) async {
    try {
      await _channel.invokeMethod<bool>('setWindowRatio', {
        'width': width,
        'height': height,
      });
    } on PlatformException catch (e) {
      VeLog.w('PictureInPicture', 'setWindowRatio failed', e);
    } on MissingPluginException {
      // No native side (tests, other platforms): no window to reshape.
    }
  }

  /// Closes the picture-in-picture window, if one is open.
  static Future<void> closeWindow() async {
    try {
      await _channel.invokeMethod<bool>('closeWindow');
    } on PlatformException catch (e) {
      VeLog.w('PictureInPicture', 'closeWindow failed', e);
    } on MissingPluginException {
      // No native side (tests, other platforms): no window to close.
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
