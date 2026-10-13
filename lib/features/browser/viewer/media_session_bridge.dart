import 'dart:async';

import 'package:flutter/services.dart';

/// An action the user took on the media notification, the lock screen
/// controls or a headset button that only the media viewer can carry out:
/// previous / next because only it knows the playlist, stop because only it
/// can close itself.
enum MediaSessionAction { previous, next, stop }

/// Dart side of the native media session (see `VaultPlaybackSession.kt`):
/// background playback of vault and local-storage media with a notification
/// and lock screen controls.
///
/// Play / pause / seek are handled natively against the player. Previous and
/// Next are playlist concepts, and Stop closes the viewer (the native side has
/// already ended playback and the notification), so they travel here: the
/// native side emits a
/// `mediaSessionAction` player event, [NativeMedia3Controller] forwards it to
/// [dispatch], and the viewer listens on [actions]. In the other direction the
/// viewer tells the native side, via [setNavigation], whether a previous or
/// next item exists so the controls are only offered when they can act.
class MediaSessionBridge {
  MediaSessionBridge._();

  static const MethodChannel _channel = MethodChannel(
    'com.aeidolon.vaultexplorer/player',
  );

  static final StreamController<MediaSessionAction> _actions =
      StreamController<MediaSessionAction>.broadcast();

  /// Previous / Next / Stop requests from outside the app UI.
  static Stream<MediaSessionAction> get actions => _actions.stream;

  /// Called with the raw `action` string of a native `mediaSessionAction`
  /// event. Unknown values are ignored so a newer native side cannot break an
  /// older Dart one.
  static void dispatch(String? action) {
    switch (action) {
      case 'previous':
        _actions.add(MediaSessionAction.previous);
      case 'next':
        _actions.add(MediaSessionAction.next);
      case 'stop':
        _actions.add(MediaSessionAction.stop);
    }
  }

  /// Tells the native media session whether the playlist has an item before /
  /// after the current one and which item is active. Best-effort: failing to
  /// update only leaves the notification controls stale.
  static Future<void> setNavigation({
    required bool hasPrevious,
    required bool hasNext,
    int currentPosition = 0,
    int totalItems = 0,
  }) async {
    try {
      await _channel.invokeMethod<void>('setMediaNavigation', {
        'hasPrevious': hasPrevious,
        'hasNext': hasNext,
        'currentPosition': currentPosition,
        'totalItems': totalItems,
      });
    } catch (_) {
      // Informational only; see the doc comment above.
    }
  }

  /// Controls whether decrypted file names may be published to notification,
  /// lock-screen, and connected-device media controls. This is opt-in.
  static Future<void> setShowFileNamesInNotification(bool show) async {
    try {
      await _channel.invokeMethod<void>('setMediaFileNamesVisible', {
        'show': show,
      });
    } catch (_) {
      // Best-effort; a missing native implementation must not affect playback.
    }
  }
}
