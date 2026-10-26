import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:vaultexplorer/features/browser/viewer/native_video_controller.dart';
import 'package:vaultexplorer/features/browser/viewer/pip/picture_in_picture_bridge.dart';

/// Decides when the system picture-in-picture window may take over, and what
/// it shows.
///
/// The media viewer [attach]es the controller of the video it shows. From then
/// on:
///  * [enterNow] (the viewer's picture-in-picture button) puts that video in
///    the PiP window right away, whatever the settings say;
///  * with `autoEnter` on (the "automatic picture-in-picture" setting), the
///    platform is also told to enter PiP by itself as soon as the person
///    leaves the app while the video plays, and not otherwise.
///
/// The attached controller is published as [source], which
/// `PictureInPictureLayer` shows, alone, once the window is up.
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

  /// Whether a video is attached that [enterNow] could put on screen.
  bool get canEnter {
    final controller = _controller;
    return PictureInPictureBridge.isSupported.value &&
        controller != null &&
        !controller.isDisposed &&
        controller.value.isInitialized;
  }

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
    _publishSource();
    _apply();
  }

  /// Puts the attached video in the PiP window now. Returns whether the
  /// system accepted it.
  Future<bool> enterNow() async {
    final controller = _controller;
    if (!canEnter || controller == null) return false;
    final ratio = _ratioOf(controller.value);
    return PictureInPictureBridge.enter(
      width: ratio.width,
      height: ratio.height,
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

  // A fixed denominator keeps the ratio an integer pair; the platform clamps
  // it to what Android accepts.
  ({int width, int height}) _ratioOf(NativeVideoValue value) =>
      (width: (value.aspectRatio * 1000).round().clamp(1, 100000), height: 1000);

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
      ratio = _ratioOf(value);
    }
    if (armed == _lastArmed &&
        ratio.width == _lastWidth &&
        ratio.height == _lastHeight) {
      return;
    }
    _lastArmed = armed;
    _lastWidth = ratio.width;
    _lastHeight = ratio.height;
    unawaited(
      PictureInPictureBridge.setState(
        armed: armed,
        width: ratio.width,
        height: ratio.height,
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
