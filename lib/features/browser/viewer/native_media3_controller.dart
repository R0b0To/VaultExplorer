import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/core/services/playback_throttle_controller.dart';
import 'package:vaultexplorer/core/utils/retry.dart';
import 'package:vaultexplorer/features/browser/viewer/native_video_controller.dart';

@immutable
class AudioTrackInfo {
  final int groupIndex;
  final int trackIndex;
  final bool isSelected;
  final String language;
  final String label;
  final String mimeType;
  final String id;
  final int? channelCount;
  final int? sampleRate;
  final int? bitrate;

  const AudioTrackInfo({
    required this.groupIndex,
    required this.trackIndex,
    required this.isSelected,
    required this.language,
    required this.label,
    required this.mimeType,
    required this.id,
    this.channelCount,
    this.sampleRate,
    this.bitrate,
  });

  factory AudioTrackInfo.fromMap(Map<String, dynamic> map) {
    return AudioTrackInfo(
      groupIndex: map['groupIndex'] as int? ?? -1,
      trackIndex: map['trackIndex'] as int? ?? -1,
      isSelected: map['isSelected'] as bool? ?? false,
      language: map['language'] as String? ?? '',
      label: map['label'] as String? ?? '',
      mimeType: map['mimeType'] as String? ?? '',
      id: map['id'] as String? ?? '',
      channelCount: map['channelCount'] as int?,
      sampleRate: map['sampleRate'] as int?,
      bitrate: map['bitrate'] as int?,
    );
  }
}

@immutable
class SubtitleTrackInfo {
  final int groupIndex;
  final int trackIndex;
  final bool isSelected;
  final String language;
  final String label;
  final String mimeType;
  final String id;

  const SubtitleTrackInfo({
    required this.groupIndex,
    required this.trackIndex,
    required this.isSelected,
    required this.language,
    required this.label,
    required this.mimeType,
    required this.id,
  });

  factory SubtitleTrackInfo.fromMap(Map<String, dynamic> map) {
    return SubtitleTrackInfo(
      groupIndex: map['groupIndex'] as int? ?? -1,
      trackIndex: map['trackIndex'] as int? ?? -1,
      isSelected: map['isSelected'] as bool? ?? false,
      language: map['language'] as String? ?? '',
      label: map['label'] as String? ?? '',
      mimeType: map['mimeType'] as String? ?? '',
      id: map['id'] as String? ?? '',
    );
  }
}

@immutable
class MediaDiagnosticsInfo {
  final String videoDecoderName;
  final bool isVideoHardwareAccelerated;
  final String audioDecoderName;
  final bool isAudioHardwareAccelerated;
  final double frameRate;
  final String videoMimeType;
  final String audioMimeType;
  final int droppedFrames;
  final int decoderInitTimeMs;
  final int bufferedMs;
  final String colorInfo;
  final int volId;
  final String filePath;

  const MediaDiagnosticsInfo({
    this.videoDecoderName = 'Initializing...',
    this.isVideoHardwareAccelerated = true,
    this.audioDecoderName = 'Initializing...',
    this.isAudioHardwareAccelerated = false,
    this.frameRate = 0.0,
    this.videoMimeType = '',
    this.audioMimeType = '',
    this.droppedFrames = 0,
    this.decoderInitTimeMs = 0,
    this.bufferedMs = 0,
    this.colorInfo = 'SDR',
    this.volId = -1,
    this.filePath = '',
  });

  factory MediaDiagnosticsInfo.fromMap(Map<String, dynamic> map) {
    return MediaDiagnosticsInfo(
      videoDecoderName: map['videoDecoderName'] as String? ?? 'Unknown',
      isVideoHardwareAccelerated: map['isVideoHardwareAccelerated'] as bool? ?? true,
      audioDecoderName: map['audioDecoderName'] as String? ?? 'Unknown',
      isAudioHardwareAccelerated: map['isAudioHardwareAccelerated'] as bool? ?? false,
      frameRate: (map['frameRate'] as num?)?.toDouble() ?? 0.0,
      videoMimeType: map['videoMimeType'] as String? ?? '',
      audioMimeType: map['audioMimeType'] as String? ?? '',
      droppedFrames: (map['droppedFrames'] as num?)?.toInt() ?? 0,
      decoderInitTimeMs: (map['decoderInitTimeMs'] as num?)?.toInt() ?? 0,
      bufferedMs: (map['bufferedMs'] as num?)?.toInt() ?? 0,
      colorInfo: map['colorInfo'] as String? ?? 'SDR',
      volId: (map['volId'] as num?)?.toInt() ?? -1,
      filePath: map['filePath'] as String? ?? '',
    );
  }
}

class NativeMedia3Controller extends ValueNotifier<NativeVideoValue> {
  static const MethodChannel _cmdChannel =
      MethodChannel('com.aeidolon.vaultexplorer/player');
  static const EventChannel _eventChannel =
      EventChannel('com.aeidolon.vaultexplorer/player_events');

  final int volId;
  final String filePath;
  final bool autoPlay;
  double _currentSpeed;
  StreamSubscription<dynamic>? _eventSubscription;
  bool _disposed = false;
  int? textureId;

  final ValueNotifier<List<AudioTrackInfo>> audioTracksNotifier =
      ValueNotifier<List<AudioTrackInfo>>([]);
  final ValueNotifier<List<SubtitleTrackInfo>> subtitleTracksNotifier =
      ValueNotifier<List<SubtitleTrackInfo>>([]);
  final ValueNotifier<MediaDiagnosticsInfo> diagnosticsNotifier =
      ValueNotifier<MediaDiagnosticsInfo>(const MediaDiagnosticsInfo());

  List<AudioTrackInfo> get audioTracks => audioTracksNotifier.value;
  List<SubtitleTrackInfo> get subtitleTracks => subtitleTracksNotifier.value;
  MediaDiagnosticsInfo get diagnostics => diagnosticsNotifier.value;

  NativeMedia3Controller({
    required this.volId,
    required this.filePath,
    this.autoPlay = false,
    double initialSpeed = 1.0,
  })  : _currentSpeed = initialSpeed,
        super(const NativeVideoValue());

  Future<void> initialize() async {
    if (_disposed) return;
    PlaybackThrottleController.setInitializing();
    value = value.copyWith(isInitialized: false, hasRenderedFirstFrame: false);
    try {
      await retryWithBackoff<void>(
        (attempt) async {
          if (_disposed) throw StateError('disposed');
          final result = await _cmdChannel.invokeMethod('initialize', {
            'volId': volId,
            'filePath': filePath,
          });
          if (result is Map && result.containsKey('textureId')) {
            textureId = (result['textureId'] as num?)?.toInt();
          }
        },
        maxAttempts: 3,
        initialDelay: const Duration(milliseconds: 500),
        maxDelay: const Duration(seconds: 2),
        retryIf: (_) => !_disposed,
      );
    } catch (e) {
      PlaybackThrottleController.setInitialized();
      if (_disposed) return;
      value = NativeVideoValue(
        hasError: true,
        errorDescription: _describeInitError(e),
      );
      return;
    }

    await _eventSubscription?.cancel();
    _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
          _handleNativeEvent,
          onError: (err) {
            if (_disposed) return;
            value = value.copyWith(
              hasError: true,
              errorDescription: err.toString(),
            );
          },
        );
    PlaybackThrottleController.setInitialized();
    if (_disposed) return;
    if (_currentSpeed != 1.0) {
      try {
        await setPlaybackSpeed(_currentSpeed);
      } catch (_) {}
    }
    if (autoPlay && !_disposed) {
      await play();
    }
  }


  void _handleNativeEvent(dynamic rawEvent) {
    if (_disposed || rawEvent is! Map) return;
    final eventMap = Map<String, dynamic>.from(rawEvent);
    final type = eventMap['event'] as String?;

    switch (type) {
      case 'renderedFirstFrame':
        value = value.copyWith(hasRenderedFirstFrame: true);
        break;
      case 'playbackState':
        final state = eventMap['state'] as String?;
        final isBuffering = state == 'buffering';
        final isInitialized = state == 'ready' || state == 'buffering' || value.isInitialized;
        value = value.copyWith(
          isInitialized: isInitialized,
          isBuffering: isBuffering,
        );
        break;
      case 'playingChanged':
        final isPlaying = eventMap['isPlaying'] as bool? ?? false;
        value = value.copyWith(isPlaying: isPlaying);
        break;
      case 'positionUpdate':
        final posMs = (eventMap['positionMs'] as num?)?.toInt() ?? 0;
        final durMs = (eventMap['durationMs'] as num?)?.toInt() ?? 0;
        value = value.copyWith(
          position: Duration(milliseconds: posMs),
          duration: Duration(milliseconds: durMs),
          // Force fallback true if it has progressed time but missed the event somehow
          hasRenderedFirstFrame: value.hasRenderedFirstFrame || posMs > 0,
        );
        break;
      case 'videoSize':
        final w = (eventMap['width'] as num?)?.toDouble() ?? 0.0;
        final h = (eventMap['height'] as num?)?.toDouble() ?? 0.0;
        value = value.copyWith(size: Size(w, h));
        break;
      case 'tracksChanged':
        _updateTracksFromMap(eventMap);
        break;
      case 'diagnosticsUpdate':
        diagnosticsNotifier.value = MediaDiagnosticsInfo.fromMap(eventMap);
        break;
      case 'error':
        final msg = eventMap['message'] as String? ?? 'Playback error';
        value = value.copyWith(
          hasError: true,
          errorDescription: msg,
        );
        break;
    }
  }

  Future<MediaDiagnosticsInfo> fetchDiagnostics() async {
    if (_disposed) return diagnostics;
    try {
      final map = await _cmdChannel.invokeMethod('getDiagnostics');
      if (map is Map) {
        final info = MediaDiagnosticsInfo.fromMap(Map<String, dynamic>.from(map));
        diagnosticsNotifier.value = info;
        return info;
      }
    } catch (_) {}
    return diagnostics;
  }

  void _updateTracksFromMap(Map<String, dynamic> eventMap) {
    final rawAudio = eventMap['audioTracks'] as List?;
    if (rawAudio != null) {
      audioTracksNotifier.value = rawAudio
          .whereType<Map>()
          .map((m) => AudioTrackInfo.fromMap(Map<String, dynamic>.from(m)))
          .toList();
    }
    final rawSubs = eventMap['subtitleTracks'] as List?;
    if (rawSubs != null) {
      subtitleTracksNotifier.value = rawSubs
          .whereType<Map>()
          .map((m) => SubtitleTrackInfo.fromMap(Map<String, dynamic>.from(m)))
          .toList();
    }
  }

  String _describeInitError(Object error) {
    final msg = error.toString().toLowerCase();
    final looksLikeDecoderContention = msg.contains('codec') ||
        msg.contains('decoder') ||
        msg.contains('no_memory') ||
        msg.contains('insufficientresources') ||
        msg.contains('0x80001000');
    return looksLikeDecoderContention
        ? 'Video decoder unavailable — hardware codec contention'
        : error.toString();
  }

  Future<void> play() async {
    if (!_disposed) {
      await _cmdChannel.invokeMethod('play');
    }
  }

  Future<void> pause() async {
    if (!_disposed) {
      await _cmdChannel.invokeMethod('pause');
    }
  }

  Future<void> seekTo(Duration position) async {
    if (!_disposed) {
      await _cmdChannel.invokeMethod('seekTo', {
        'positionMs': position.inMilliseconds,
      });
    }
  }

  Future<void> setVolume(int vol) async {
    if (!_disposed) {
      final double normalized = (vol / 100.0).clamp(0.0, 1.0);
      await _cmdChannel.invokeMethod('setVolume', {'volume': normalized});
    }
  }

  Future<void> setPlaybackSpeed(double speed) async {
    _currentSpeed = speed;
    if (!_disposed) {
      try {
        await _cmdChannel.invokeMethod('setSpeed', {'speed': speed});
      } catch (_) {}
    }
  }

  Future<void> setLooping(bool loop) async {
    if (!_disposed) {
      await _cmdChannel.invokeMethod('setLooping', {'loop': loop});
    }
  }

  Future<void> selectAudioTrack(int groupIndex, int trackIndex) async {
    if (!_disposed) {
      await _cmdChannel.invokeMethod('selectAudioTrack', {
        'groupIndex': groupIndex,
        'trackIndex': trackIndex,
      });
    }
  }

  Future<void> selectSubtitleTrack(int groupIndex, int trackIndex) async {
    if (!_disposed) {
      await _cmdChannel.invokeMethod('selectSubtitleTrack', {
        'groupIndex': groupIndex,
        'trackIndex': trackIndex,
      });
    }
  }

  Future<void> disableSubtitleTrack() async {
    if (!_disposed) {
      await _cmdChannel.invokeMethod('disableSubtitleTrack');
    }
  }

  bool get isDisposed => _disposed;

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    value = const NativeVideoValue(isInitialized: false, hasRenderedFirstFrame: false);
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    audioTracksNotifier.dispose();
    subtitleTracksNotifier.dispose();
    try {
      await _cmdChannel.invokeMethod('release');
    } catch (_) {}
    super.dispose();
  }
}