// File: lib/features/browser/viewer/native_video_controller.dart
import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:vaultexplorer/core/services/playback_throttle_controller.dart';
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
  await PlaybackThrottleController.setActive(true);
  PlaybackThrottleController.setInitializing();

  var controller = VideoPlayerController.contentUri(Uri.parse(contentUriString));
  _inner = controller;
  controller.addListener(_onTick);
  
  try {
    await controller.initialize();
    PlaybackThrottleController.setInitialized();
  } catch (e) {
    // If the native hardware video codec was temporarily occupied (e.g. from
    // a background thumbnail extractor releasing or rapid navigation),
    // dispose the stale handle, wait 400ms for Android OS to release the MediaCodec instance,
    // and retry with a fresh controller.
    controller.removeListener(_onTick);
    await controller.dispose();
    if (_disposed) {
      PlaybackThrottleController.setInitialized();
      return;
    }

    await Future.delayed(const Duration(milliseconds: 400));
    if (_disposed) {
      PlaybackThrottleController.setInitialized();
      return;
    }

    controller = VideoPlayerController.contentUri(Uri.parse(contentUriString));
    _inner = controller;
    controller.addListener(_onTick);
    try {
      await controller.initialize();
    } catch (_) {
      PlaybackThrottleController.setInitialized();
      value = const NativeVideoValue(
        hasError: true,
        errorDescription: 'Video decoder unavailable — hardware codec contention',
      );
      return;
    }
    PlaybackThrottleController.setInitialized();
  }


  if (_disposed) return;
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

  bool get isDisposed => _disposed;

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    value = const NativeVideoValue(isInitialized: false);
    _inner?.removeListener(_onTick);
    final toDispose = _inner;
    _inner = null;
    await toDispose?.dispose();
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
        if (controller.isDisposed) return const SizedBox.shrink();
        final inner = controller.playerController;
        if (inner == null || !value.isInitialized || !inner.value.isInitialized) {
          return const SizedBox.shrink();
        }
        if (value.size.width <= 0 || value.size.height <= 0) return const SizedBox.shrink();
        return VideoPlayer(inner);
      },
    );
  }
}

