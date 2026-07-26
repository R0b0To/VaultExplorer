// File: lib/features/browser/viewer/native_ffmpeg_controller.dart
import 'dart:async';
import 'dart:ui' show Size;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

@immutable
class NativeFFmpegValue {
  final bool isInitialized;
  final bool isPlaying;
  final bool hasError;
  final String errorDescription;
  final Duration position;
  final Duration duration;
  final Size size;

  const NativeFFmpegValue({
    this.isInitialized = false,
    this.isPlaying = false,
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

  NativeFFmpegValue copyWith({
    bool? isInitialized,
    bool? isPlaying,
    bool? hasError,
    String? errorDescription,
    Duration? position,
    Duration? duration,
    Size? size,
  }) {
    return NativeFFmpegValue(
      isInitialized: isInitialized ?? this.isInitialized,
      isPlaying: isPlaying ?? this.isPlaying,
      hasError: hasError ?? this.hasError,
      errorDescription: errorDescription ?? this.errorDescription,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      size: size ?? this.size,
    );
  }
}

class NativeFFmpegController extends ValueNotifier<NativeFFmpegValue> {
  static const MethodChannel _channel = MethodChannel('com.aeidolon.vaultexplorer/ffmpeg_player');
  static const String _eventChannelPrefix = 'com.aeidolon.vaultexplorer/ffmpeg_player/events/';

  final String contentUriString;
  final bool autoPlay;
  int? _playerId;
  int? _textureId;
  StreamSubscription<dynamic>? _eventSub;
  bool _disposed = false;

  // --- Seekbar smoothing ---
  // timeChanged only fires every ~15 decoded video frames (native-side
  // throttle, see kTimeChangedNotifyEveryNFrames in ffmpeg_player.h) --
  // at 30fps that's roughly every 500ms with nothing updating value.position
  // in between, which is what actually made the seekbar look like it moves
  // in visible steps rather than a genuine native limitation on how often
  // position *could* be reported. Rather than making native chattier (more
  // JNI/event-channel traffic for a purely cosmetic problem), _positionTicker
  // extrapolates value.position between real events using elapsed wall-clock
  // time * current speed, and every timeChanged/playing event snaps the
  // extrapolation anchor back to the authoritative value -- so it can never
  // drift for more than one throttle interval before being corrected.
  static const Duration _positionTickInterval = Duration(milliseconds: 66);
  Timer? _positionTicker;
  Duration _extrapolationAnchorPosition = Duration.zero;
  DateTime _extrapolationAnchorWallClock = DateTime.now();
  double _currentSpeed = 1.0;

  void _resetExtrapolationAnchor() {
    _extrapolationAnchorPosition = value.position;
    _extrapolationAnchorWallClock = DateTime.now();
  }

  void _tickExtrapolatedPosition() {
    if (_disposed || !value.isPlaying) return;
    final elapsedMs = DateTime.now().difference(_extrapolationAnchorWallClock).inMilliseconds;
    var extrapolatedMs = _extrapolationAnchorPosition.inMilliseconds + (elapsedMs * _currentSpeed).round();
    final durationMs = value.duration.inMilliseconds;
    if (durationMs > 0 && extrapolatedMs > durationMs) extrapolatedMs = durationMs;
    if (extrapolatedMs < 0) extrapolatedMs = 0;
    if (extrapolatedMs != value.position.inMilliseconds) {
      value = value.copyWith(position: Duration(milliseconds: extrapolatedMs));
    }
  }

  NativeFFmpegController({required this.contentUriString, this.autoPlay = false}) : super(const NativeFFmpegValue());

  int? get textureId => _textureId;

  Future<void> initialize() async {
    if (_playerId != null || _disposed) return;
    final created = await _channel.invokeMapMethod<String, dynamic>('create');
    if (created == null || _disposed) return;
    
    _playerId = created['playerId'] as int;
    _textureId = created['textureId'] as int;
    
    final eventChannel = EventChannel('$_eventChannelPrefix$_playerId');
    _eventSub = eventChannel.receiveBroadcastStream().listen(
      _onEvent,
      onError: (Object error, StackTrace _) {
        if (_disposed) return;
        value = value.copyWith(hasError: true, errorDescription: error.toString());
      },
    );
    _positionTicker ??= Timer.periodic(_positionTickInterval, (_) => _tickExtrapolatedPosition());

    await _channel.invokeMethod('setDataSource', {
      'playerId': _playerId,
      'contentUri': contentUriString,
      'autoPlay': autoPlay,
    });
  }

  Future<void> switchTo(String newContentUriString, {bool autoPlay = false}) async {
    if (_playerId == null || _disposed) return;
    value = const NativeFFmpegValue();
    _resetExtrapolationAnchor();
    await _channel.invokeMethod('setDataSource', {
      'playerId': _playerId,
      'contentUri': newContentUriString,
      'autoPlay': autoPlay,
    });
  }

  void _onEvent(dynamic raw) {
    if (_disposed) return;
    final map = Map<String, dynamic>.from(raw as Map);
    switch (map['event'] as String?) {
      case 'playing':
        // width/height/durationMs are only present in the map when the
        // native side actually knows them (see notifyEvent's guards) --
        // the native play() call after a pause fires this same event to
        // flip isPlaying back to true (see its own comment for why that's
        // necessary), but doesn't re-measure the video, so it sends this
        // without width/height. Falling back to value.size/value.duration
        // rather than defaulting to 0 keeps that resume from wiping out
        // the already-known video size.
        final w = (map['width'] as num?)?.toDouble();
        final h = (map['height'] as num?)?.toDouble();
        final durMs = (map['durationMs'] as num?)?.toInt();
        value = value.copyWith(
          isInitialized: true,
          isPlaying: true,
          size: (w != null && h != null && w > 0 && h > 0) ? Size(w, h) : value.size,
          duration: (durMs != null && durMs > 0) ? Duration(milliseconds: durMs) : value.duration,
        );
        _resetExtrapolationAnchor();
        break;
      case 'paused':
      case 'stopped':
        value = value.copyWith(isPlaying: false);
        break;
      case 'timeChanged':
        final newPositionMs = ((map['positionMs'] as num?) ?? 0).toInt();
        value = value.copyWith(
          isInitialized: true,
          position: Duration(milliseconds: newPositionMs),
          duration: Duration(milliseconds: ((map['durationMs'] as num?) ?? 0).toInt()),
        );
        _resetExtrapolationAnchor();
        break;
      case 'endReached':
        value = value.copyWith(isPlaying: false, position: value.duration);
        break;
      case 'error':
        value = value.copyWith(hasError: true, errorDescription: (map['message'] as String?) ?? 'Playback error');
        break;
    }
  }

  Future<void> play() async { if (!_disposed) await _channel.invokeMethod('play', {'playerId': _playerId}); }

  Future<void> pause() async {
    if (_disposed) return;
    // Set locally before the round trip, not after: _tickExtrapolatedPosition
    // only advances position while value.isPlaying is true, but that flag
    // previously only flipped once native's own "paused" event came back
    // through pause() -> JNI -> mainHandler.post -> the event channel. During
    // that window the ticker kept extrapolating position forward from the
    // last-known speed, which is what made the seek bar visibly creep after
    // the pause button was tapped. Native no longer advances its own clocks
    // once paused (see is_playing gating in video/audioDecodeThreadFunc), but
    // there's still a real round-trip delay before Dart hears about it --
    // this removes the dependency on that round trip entirely.
    value = value.copyWith(isPlaying: false);
    await _channel.invokeMethod('pause', {'playerId': _playerId});
  }
  Future<void> stop() async { if (!_disposed) await _channel.invokeMethod('stop', {'playerId': _playerId}); }
  Future<void> seekTo(Duration position) async {
    if (!_disposed) await _channel.invokeMethod('seekTo', {'playerId': _playerId, 'positionMs': position.inMilliseconds});
  }
  Future<void> setVolume(int vol) async {
    if (!_disposed) await _channel.invokeMethod('setVolume', {'playerId': _playerId, 'volume': vol});
  }
  Future<void> setPlaybackSpeed(double speed) async {
    // Bring the extrapolated position up to date under the *old* speed
    // before changing it, then re-anchor -- otherwise the ticker would
    // retroactively apply the new speed to time that already elapsed under
    // the old one, producing a visible jump.
    _tickExtrapolatedPosition();
    _resetExtrapolationAnchor();
    _currentSpeed = speed;
    if (!_disposed) await _channel.invokeMethod('setRate', {'playerId': _playerId, 'rate': speed});
  }
  Future<void> setLooping(bool loop) async {
    if (!_disposed) await _channel.invokeMethod('setLooping', {'playerId': _playerId, 'looping': loop});
  }

  /// Best-effort technical diagnostics (codec, frame rate, bitrate, sample
  /// rate...) read directly from the container/track metadata on the native
  /// side, independent of the decode pipeline. Returns an empty map if the
  /// player isn't ready yet or nothing could be determined -- callers should
  /// treat every field as optional.
  Future<Map<String, dynamic>> getDiagnostics() async {
    if (_disposed || _playerId == null) return const {};
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'getDiagnostics',
        {'playerId': _playerId},
      );
      return result ?? const {};
    } catch (_) {
      return const {};
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _positionTicker?.cancel();
    await _eventSub?.cancel();
    if (_playerId != null) {
      try { await _channel.invokeMethod('dispose', {'playerId': _playerId}); } catch (_) {}
    }
    super.dispose();
  }
}

class NativeFFmpegPlayerView extends StatelessWidget {
  final NativeFFmpegController controller;
  const NativeFFmpegPlayerView({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<NativeFFmpegValue>(
      valueListenable: controller,
      builder: (context, value, child) {
        final id = controller.textureId;
        if (id == null || !value.isInitialized) return const SizedBox.shrink();
        if (value.size.width <= 0 || value.size.height <= 0) return const SizedBox.shrink();
        return Texture(textureId: id);
      },
    );
  }
}