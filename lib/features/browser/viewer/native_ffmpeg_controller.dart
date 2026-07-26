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

    await _channel.invokeMethod('setDataSource', {
      'playerId': _playerId,
      'contentUri': contentUriString,
      'autoPlay': autoPlay,
    });
  }

  Future<void> switchTo(String newContentUriString, {bool autoPlay = false}) async {
    if (_playerId == null || _disposed) return;
    value = const NativeFFmpegValue();
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
        break;
      case 'paused':
      case 'stopped':
        value = value.copyWith(isPlaying: false);
        break;
      case 'timeChanged':
        value = value.copyWith(
          isInitialized: true,
          position: Duration(milliseconds: ((map['positionMs'] as num?) ?? 0).toInt()),
          duration: Duration(milliseconds: ((map['durationMs'] as num?) ?? 0).toInt()),
        );
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
  Future<void> pause() async { if (!_disposed) await _channel.invokeMethod('pause', {'playerId': _playerId}); }
  Future<void> stop() async { if (!_disposed) await _channel.invokeMethod('stop', {'playerId': _playerId}); }
  Future<void> seekTo(Duration position) async {
    if (!_disposed) await _channel.invokeMethod('seekTo', {'playerId': _playerId, 'positionMs': position.inMilliseconds});
  }
  Future<void> setVolume(int vol) async {
    if (!_disposed) await _channel.invokeMethod('setVolume', {'playerId': _playerId, 'volume': vol});
  }
  Future<void> setPlaybackSpeed(double speed) async {
    if (!_disposed) await _channel.invokeMethod('setRate', {'playerId': _playerId, 'rate': speed});
  }
  Future<void> setLooping(bool loop) async {
    if (!_disposed) await _channel.invokeMethod('setLooping', {'playerId': _playerId, 'looping': loop});
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
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