// File: lib/features/browser/viewer/native_video_controller.dart
import 'dart:async';
import 'dart:ui' show Size;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

@immutable
class NativeVideoValue {
  final bool isInitialized;
  final bool isPlaying;
  final bool isBuffering;
  final bool hasError;
  final String errorDescription;
  final Duration position;
  final Duration duration;
  final Size size;

  const NativeVideoValue({
    this.isInitialized = false,
    this.isPlaying = false,
    this.isBuffering = false,
    this.hasError = false,
    this.errorDescription = '',
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.size = Size.zero,
  });

  double get aspectRatio {
    if (size.width <= 0 || size.height <= 0) return 1.0;
    final ratio = size.width / size.height;
    return ratio.isFinite && ratio > 0 ? ratio : 1.0;
  }

  factory NativeVideoValue.fromPlayerValue(VideoPlayerValue v) {
    return NativeVideoValue(
      isInitialized: v.isInitialized,
      isPlaying: v.isPlaying,
      isBuffering: v.isBuffering,
      hasError: v.hasError,
      errorDescription: v.errorDescription ?? '',
      position: v.position,
      duration: v.duration,
      size: v.size,
    );
  }
}

/// Thin wrapper around the Flutter team's own [VideoPlayerController].

class NativeVideoController extends ValueNotifier<NativeVideoValue> {
  final String contentUriString;
  final bool autoPlay;
  double _currentSpeed;

  VideoPlayerController? _inner;
  bool _disposed = false;

  NativeVideoController({
    required this.contentUriString,
    this.autoPlay = false,
    double initialSpeed = 1.0,
  })  : _currentSpeed = initialSpeed,
        super(const NativeVideoValue());

  /// Exposes the underlying plugin controller for [NativeVideoPlayerView]
  /// to render. Not for general use elsewhere.
  VideoPlayerController? get playerController => _inner;

  Future<void> initialize() async {
    if (_inner != null || _disposed) return;
    final controller = VideoPlayerController.contentUri(Uri.parse(contentUriString));
    _inner = controller;
    controller.addListener(_onTick);

    try {
      await controller.initialize();
    } catch (_) {
      // Failure already lands in controller.value.hasError/errorDescription
      // and is picked up by _onTick -- nothing further to do here.
      return;
    }
    if (_disposed) return;

    // Apply whichever speed the previous item in this playlist was playing
    // at (initialSpeed) so a freshly-created controller doesn't silently
    // reset to 1x. Safe to call before play(): video_player stores the
    // speed on .value regardless of playback state and (re)applies it the
    // next time play() actually starts the platform player.
    if (_currentSpeed != 1.0) {
      try {
        await controller.setPlaybackSpeed(_currentSpeed);
      } catch (_) {}
    }

    if (autoPlay && !_disposed) await play();
  }

  void _onTick() {
    if (_disposed) return;
    final inner = _inner;
    if (inner == null) return;
    value = NativeVideoValue.fromPlayerValue(inner.value);
  }

  Future<void> play() async {
    if (!_disposed) await _inner?.play();
  }

  Future<void> pause() async {
    if (!_disposed) await _inner?.pause();
  }

  Future<void> seekTo(Duration position) async {
    if (!_disposed) await _inner?.seekTo(position);
  }

  /// [vol] is 0-100, matching the rest of the app's volume UI.
  Future<void> setVolume(int vol) async {
    if (!_disposed) await _inner?.setVolume((vol / 100.0).clamp(0.0, 1.0));
  }

  Future<void> setPlaybackSpeed(double speed) async {
    _currentSpeed = speed;
    if (_disposed || _inner == null) return;
    // Swallow failures: a speed change can legitimately land just as this
    // controller is being torn down (e.g. right after swiping to the next
    // item), which is a harmless no-op for a controller nobody is looking
    // at anymore, not something that should surface as an exception.
    try {
      await _inner!.setPlaybackSpeed(speed);
    } catch (_) {}
  }

  Future<void> setLooping(bool loop) async {
    if (!_disposed) await _inner?.setLooping(loop);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _inner?.removeListener(_onTick);
    await _inner?.dispose();
    super.dispose();
  }
}

/// Renders the current video frame for [controller].
class NativeVideoPlayerView extends StatelessWidget {
  final NativeVideoController controller;
  const NativeVideoPlayerView({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<NativeVideoValue>(
      valueListenable: controller,
      builder: (context, value, child) {
        final inner = controller.playerController;
        if (inner == null || !value.isInitialized) return const SizedBox.shrink();
        if (value.size.width <= 0 || value.size.height <= 0) return const SizedBox.shrink();
        return VideoPlayer(inner);
      },
    );
  }
}
