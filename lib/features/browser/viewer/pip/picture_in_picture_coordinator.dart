import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:vaultexplorer/features/browser/viewer/native_video_controller.dart';
import 'package:vaultexplorer/features/browser/viewer/pip/picture_in_picture_bridge.dart';

/// Decides when the system picture-in-picture window may take over, and what
/// it shows.
///
/// Whoever is playing a video -- the media viewer, or the mini player once the
/// viewer is closed -- [attach]es its controller here. While that video plays
/// (and the "Picture-in-picture" setting is on) the platform is told to enter
/// PiP as soon as the person leaves the app; otherwise it is told not to. The
/// controller is also published as [source], which `PictureInPictureLayer`
/// shows, alone, once the window is up.
///
/// Only one owner is active at a time: a new [attach] takes over from the
/// previous owner, and a [detach] from anyone but the current owner is
/// ignored, so a closing viewer can't disarm the mini player taking over.
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
  bool _enabled = false;

  bool _lastArmed = false;
  int _lastWidth = 0;
  int _lastHeight = 0;

  /// Makes [owner] the source of the PiP window, playing [controller].
  /// [enabled] is the person's "Picture-in-picture" setting; when it is off
  /// this is the same as [detach].
  void attach(
    Object owner,
    NativeVideoController controller, {
    required bool enabled,
  }) {
    if (!enabled || controller.isDisposed) {
      detach(owner);
      return;
    }
    if (!identical(_controller, controller)) {
      _unbind();
      _controller = controller;
      controller.addListener(_apply);
    }
    _owner = owner;
    _enabled = true;
    _publishSource();
    _apply();
  }

  /// Stops [owner] from being the PiP source. A no-op for anyone else.
  void detach(Object owner) {
    if (!identical(_owner, owner)) return;
    _unbind();
    _owner = null;
    _enabled = false;
    _publishSource();
    _apply();
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
    var width = 16;
    var height = 9;
    if (_enabled && controller != null && !controller.isDisposed) {
      final value = controller.value;
      armed = value.isInitialized && value.isPlaying && !value.hasError;
      // A fixed denominator keeps the ratio an integer pair; the platform
      // clamps it to what Android accepts.
      width = (value.aspectRatio * 1000).round().clamp(1, 100000);
      height = 1000;
    }
    if (armed == _lastArmed && width == _lastWidth && height == _lastHeight) {
      return;
    }
    _lastArmed = armed;
    _lastWidth = width;
    _lastHeight = height;
    unawaited(
      PictureInPictureBridge.setState(
        armed: armed,
        width: width,
        height: height,
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
