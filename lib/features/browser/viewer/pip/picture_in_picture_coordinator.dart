import 'dart:async';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:vaultexplorer/features/browser/viewer/native_video_controller.dart';
import 'package:vaultexplorer/features/browser/viewer/pip/picture_in_picture_bridge.dart';

/// Decides when the system picture-in-picture window may take over, and what
/// it shows.
///
/// The whole app becomes the PiP window, the same activity that is already
/// playing the video. The media viewer, or the floating player (through
/// `BackgroundPlaybackHost`), [attach]es the controller of the video it shows;
/// with `autoEnter` on the platform is told to enter PiP by itself as soon as
/// the person leaves the app while the video plays, and not otherwise. The
/// viewer's picture-in-picture button does it on request with [enterNow].
///
/// The attached controller is published as [source], which
/// `PictureInPictureLayer` shows, alone, once that window is up.
///
/// What makes the transition look continuous is [setSourceRect]: the owner
/// says where the video is on screen, and Android animates from that area into
/// the window (and back out of it), instead of shrinking the whole app and
/// showing the video once the layout has switched.
///
/// A [detach] from anyone but the current owner is ignored, so a closing
/// viewer can't withdraw the video a newer one has just attached.
class PictureInPictureCoordinator {
  PictureInPictureCoordinator._() {
    PictureInPictureBridge.ensureInitialized();
    PictureInPictureBridge.windowDismissed.listen((_) => _onWindowDismissed());
  }

  static final PictureInPictureCoordinator instance =
      PictureInPictureCoordinator._();

  /// The video the PiP window shows, or null.
  final ValueNotifier<NativeVideoController?> source =
      ValueNotifier<NativeVideoController?>(null);

  Object? _owner;
  NativeVideoController? _controller;
  bool _autoEnter = false;

  bool _lastArmed = false;
  int _lastWidth = 0;
  int _lastHeight = 0;

  /// Where the video is on screen (physical pixels of the app's view), as the
  /// owner last reported it; null when unknown.
  Rect? _sourceRect;
  Rect? _lastRect;
  Timer? _rectTimer;

  /// Makes [owner] the source of the PiP window, playing [controller].
  /// [autoEnter] is the "automatic picture-in-picture" setting.
  void attach(
    Object owner,
    NativeVideoController controller, {
    required bool autoEnter,
  }) {
    if (controller.isDisposed) {
      detach(owner);
      return;
    }
    if (!identical(_controller, controller)) {
      _unbind();
      _controller = controller;
      controller.addListener(_apply);
    }
    // Another owner has its own idea of where the video is.
    if (!identical(_owner, owner)) _sourceRect = null;
    _owner = owner;
    _autoEnter = autoEnter;
    _publishSource();
    _apply();
  }

  /// Stops [owner] from being the PiP source. A no-op for anyone else.
  void detach(Object owner) {
    if (!identical(_owner, owner)) return;
    _unbind();
    _owner = null;
    _autoEnter = false;
    _sourceRect = null;
    _rectTimer?.cancel();
    _rectTimer = null;
    _publishSource();
    _apply();
  }

  /// Says where the video is on screen, as [logical] pixels in the app's own
  /// coordinates (null: not known). Ignored from anyone but the owner, and
  /// while the app already is the PiP window (its layout is then the PiP one).
  /// Android uses it as the source rect hint, so it should be the area the
  /// video occupies when the person leaves the app.
  void setSourceRect(
    Object owner,
    Rect? logical, {
    required double devicePixelRatio,
  }) {
    if (!identical(_owner, owner)) return;
    if (PictureInPictureBridge.isInPictureInPicture.value) return;
    final physical = logical == null || logical.isEmpty || devicePixelRatio <= 0
        ? null
        : Rect.fromLTRB(
            (logical.left * devicePixelRatio).roundToDouble(),
            (logical.top * devicePixelRatio).roundToDouble(),
            (logical.right * devicePixelRatio).roundToDouble(),
            (logical.bottom * devicePixelRatio).roundToDouble(),
          );
    if (_sourceRect == physical) return;
    _sourceRect = physical;
    // A moving video (pinch zoom) changes this every frame; the platform only
    // needs the value it settles on.
    if (_rectTimer?.isActive ?? false) return;
    _rectTimer = Timer(const Duration(milliseconds: 120), () {
      _rectTimer = null;
      _apply();
    });
  }

  /// The viewer's picture-in-picture button: the app becomes the window right
  /// now. False when [owner] is not the one attached, or the system refuses.
  Future<bool> enterNow(Object owner) async {
    final controller = _controller;
    if (!identical(_owner, owner) ||
        controller == null ||
        controller.isDisposed) {
      return false;
    }
    final ratio = pictureInPictureRatio(controller.value.aspectRatio);
    return PictureInPictureBridge.enterNow(
      width: ratio.width,
      height: ratio.height,
      sourceRect: _sourceRect,
    );
  }

  void _unbind() {
    final controller = _controller;
    if (controller != null) {
      try {
        controller.removeListener(_apply);
      } catch (_) {
        // Already disposed along with its player; the reference is dropped
        // either way.
      }
    }
    _controller = null;
  }

  // Notified from a microtask: attach / detach run from initState, dispose
  // and notifier callbacks, where changing a notifier that widgets listen to
  // can throw.
  void _publishSource() {
    scheduleMicrotask(() {
      if (source.value != _controller) source.value = _controller;
    });
  }

  void _apply() {
    final controller = _controller;
    var armed = false;
    var ratio = (width: 16, height: 9);
    if (controller != null && !controller.isDisposed) {
      final value = controller.value;
      armed =
          _autoEnter &&
          value.isInitialized &&
          value.isPlaying &&
          !value.hasError;
      ratio = pictureInPictureRatio(value.aspectRatio);
    }
    final rect = controller != null && !controller.isDisposed
        ? _sourceRect
        : null;
    if (armed == _lastArmed &&
        ratio.width == _lastWidth &&
        ratio.height == _lastHeight &&
        rect == _lastRect) {
      return;
    }
    _lastArmed = armed;
    _lastWidth = ratio.width;
    _lastHeight = ratio.height;
    _lastRect = rect;
    unawaited(
      PictureInPictureBridge.setState(
        armed: armed,
        width: ratio.width,
        height: ratio.height,
        sourceRect: rect,
      ),
    );
  }

  /// The person closed the PiP window: the video should not carry on behind
  /// their back.
  void _onWindowDismissed() {
    final controller = _controller;
    if (controller == null || controller.isDisposed) return;
    unawaited(controller.pause());
  }
}
