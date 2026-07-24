import 'dart:async';
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Immutable playback state for a [NativeVlcController], deliberately
/// shaped like `video_player`'s `VideoPlayerValue` so call sites written
/// against that API (aspect ratio, position/duration, hasError/
/// errorDescription) don't need to change.
@immutable
class NativeVlcValue {
  final bool isInitialized;
  final bool isPlaying;
  final bool hasError;
  final String errorDescription;
  final Duration position;
  final Duration duration;
  final Size size;

  const NativeVlcValue({
    this.isInitialized = false,
    this.isPlaying = false,
    this.hasError = false,
    this.errorDescription = '',
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.size = Size.zero,
  });

  /// `size.width / size.height`, or `1.0` before the real size is known
  /// (matches `video_player`'s fallback so layout code doesn't need a
  /// special case for the pre-init frame).
  double get aspectRatio {
    if (size.width <= 0 || size.height <= 0) return 1.0;
    final ratio = size.width / size.height;
    return ratio.isFinite && ratio > 0 ? ratio : 1.0;
  }

  NativeVlcValue copyWith({
    bool? isInitialized,
    bool? isPlaying,
    bool? hasError,
    String? errorDescription,
    Duration? position,
    Duration? duration,
    Size? size,
  }) {
    return NativeVlcValue(
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

/// Controls a native libVLC player instance running behind
/// `com.aeidolon.vaultexplorer.vlcplayer.VlcPlayerPlugin` on the Android
/// side.
///
/// Unlike `flutter_vlc_player`'s `VlcPlayerController`, [initialize] is a
/// plain async method you can call before anything is on screen — the
/// native side creates its `MediaPlayer` + Flutter `Texture` immediately
/// and starts opening the media right away. That means [VideoPlaybackManager]
/// can genuinely prewarm the next item in the background again, the same
/// way the old `video_player`-based implementation did.
class NativeVlcController extends ValueNotifier<NativeVlcValue> {
  static const MethodChannel _channel =
      MethodChannel('com.aeidolon.vaultexplorer/vlc_player');
  static const String _eventChannelPrefix =
      'com.aeidolon.vaultexplorer/vlc_player/events/';

  final String contentUriString;
  final bool autoPlay;

  int? _playerId;
  int? _textureId;
  StreamSubscription<dynamic>? _eventSub;
  bool _disposed = false;
  bool _initCompleted = false;
  final List<VoidCallback> _onInitListeners = [];

  NativeVlcController({
    required this.contentUriString,
    this.autoPlay = false,
  }) : super(const NativeVlcValue());

  /// The Flutter `Texture` id to render with, once [initialize] resolves.
  int? get textureId => _textureId;

  /// Fires once, the first time the player reports a real frame size
  /// (mirrors `flutter_vlc_player`'s `addOnInitListener`, kept for a
  /// familiar call shape — most call sites can just await [initialize]
  /// instead).
  void addOnInitListener(VoidCallback listener) => _onInitListeners.add(listener);
  void removeOnInitListener(VoidCallback listener) => _onInitListeners.remove(listener);

  /// Creates the native player + texture and starts opening
  /// [contentUriString]. Safe to call well before any widget referencing
  /// this controller is built.
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

  void _onEvent(dynamic raw) {
    if (_disposed) return;
    final map = Map<String, dynamic>.from(raw as Map);

    switch (map['event'] as String?) {
      case 'playing':
        value = value.copyWith(
          isInitialized: true,
          isPlaying: true,
          size: Size(
            ((map['width'] as num?) ?? 0).toDouble(),
            ((map['height'] as num?) ?? 0).toDouble(),
          ),
          duration: Duration(milliseconds: ((map['durationMs'] as num?) ?? 0).toInt()),
        );
        _fireInitListenersOnce();
        break;

      case 'paused':
        value = value.copyWith(isPlaying: false);
        break;

      case 'stopped':
        value = value.copyWith(isPlaying: false);
        break;

      case 'timeChanged':
        value = value.copyWith(
          isInitialized: true,
          position: Duration(milliseconds: ((map['positionMs'] as num?) ?? 0).toInt()),
          duration: Duration(milliseconds: ((map['durationMs'] as num?) ?? 0).toInt()),
        );
        _fireInitListenersOnce();
        break;

      case 'lengthChanged':
        value = value.copyWith(
          duration: Duration(milliseconds: ((map['durationMs'] as num?) ?? 0).toInt()),
        );
        break;

      case 'endReached':
        value = value.copyWith(isPlaying: false);
        break;

      case 'error':
        value = value.copyWith(
          hasError: true,
          errorDescription: (map['message'] as String?) ?? 'Playback error',
        );
        break;
    }
  }

  void _fireInitListenersOnce() {
    if (_initCompleted) return;
    _initCompleted = true;
    for (final listener in List<VoidCallback>.from(_onInitListeners)) {
      listener();
    }
  }

  Future<void> play() async {
    if (_playerId == null || _disposed) return;
    await _channel.invokeMethod('play', {'playerId': _playerId});
  }

  Future<void> pause() async {
    if (_playerId == null || _disposed) return;
    await _channel.invokeMethod('pause', {'playerId': _playerId});
  }

  Future<void> stop() async {
    if (_playerId == null || _disposed) return;
    await _channel.invokeMethod('stop', {'playerId': _playerId});
  }

  Future<void> seekTo(Duration position) async {
    if (_playerId == null || _disposed) return;
    await _channel.invokeMethod('seekTo', {
      'playerId': _playerId,
      'positionMs': position.inMilliseconds,
    });
  }

  /// `volume` is 0-100 (libVLC's native scale), not the 0.0-1.0 scale
  /// `video_player` used.
  Future<void> setVolume(int volume) async {
    if (_playerId == null || _disposed) return;
    await _channel.invokeMethod('setVolume', {
      'playerId': _playerId,
      'volume': volume.clamp(0, 100),
    });
  }

  Future<void> setPlaybackSpeed(double speed) async {
    if (_playerId == null || _disposed) return;
    await _channel.invokeMethod('setRate', {'playerId': _playerId, 'rate': speed});
  }

  Future<void> setLooping(bool looping) async {
    if (_playerId == null || _disposed) return;
    await _channel.invokeMethod('setLooping', {
      'playerId': _playerId,
      'looping': looping,
    });
  }

  Future<Map<int, String>> getSpuTracks() async {
    if (_playerId == null || _disposed) return {};
    final res = await _channel.invokeMapMethod<String, dynamic>(
      'getSpuTracks',
      {'playerId': _playerId},
    );
    if (res == null) return {};
    return res.map((key, value) => MapEntry(int.parse(key), value as String));
  }

  Future<void> setSpuTrack(int trackId) async {
    if (_playerId == null || _disposed) return;
    await _channel.invokeMethod('setSpuTrack', {
      'playerId': _playerId,
      'trackId': trackId,
    });
  }

  Future<Map<int, String>> getAudioTracks() async {
    if (_playerId == null || _disposed) return {};
    final res = await _channel.invokeMapMethod<String, dynamic>(
      'getAudioTracks',
      {'playerId': _playerId},
    );
    if (res == null) return {};
    return res.map((key, value) => MapEntry(int.parse(key), value as String));
  }

  Future<void> setAudioTrack(int trackId) async {
    if (_playerId == null || _disposed) return;
    await _channel.invokeMethod('setAudioTrack', {
      'playerId': _playerId,
      'trackId': trackId,
    });
  }

  /// Releases the native player + texture. Safe to call even if
  /// [initialize] never finished.
  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _eventSub?.cancel();
    final id = _playerId;
    if (id != null) {
      try {
        await _channel.invokeMethod('dispose', {'playerId': id});
      } catch (_) {}
    }
    super.dispose();
  }
}

/// Renders a [NativeVlcController]'s video frames. Deliberately a bare
/// `Texture` (like `video_player`'s `VideoPlayer` widget) with no built-in
/// aspect-ratio wrapping, so it drops into whatever `AspectRatio` /
/// `RotatedBox` layout the caller already has.
class NativeVlcPlayerView extends StatelessWidget {
  final NativeVlcController controller;
  const NativeVlcPlayerView({super.key, required this.controller});
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<NativeVlcValue>(
      valueListenable: controller,
      builder: (context, value, child) {
        final id = controller.textureId;
        if (id == null || !value.isInitialized) return const SizedBox.shrink();
        if (value.size.width <= 0 || value.size.height <= 0) {
          return const SizedBox.shrink();
        }
        return Texture(textureId: id);
      },
    );
  }
}