import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/widgets.dart';
import 'package:vaultexplorer/data/models/audio_equalizer_settings.dart';
import 'package:vaultexplorer/data/models/media_decoder_mode.dart';
import 'package:vaultexplorer/core/engine/desktop/desktop_engine_binding.dart' show isDesktopEngineTarget;
import 'package:vaultexplorer/features/browser/viewer/desktop_video_backend.dart';
import 'package:vaultexplorer/features/browser/viewer/desktop_video_view.dart';
import 'package:vaultexplorer/features/browser/viewer/native_media3_controller.dart';
import 'package:vaultexplorer/features/browser/viewer/native_media3_player_view.dart';
import 'package:vaultexplorer/features/browser/viewer/video_playback_backend.dart';

@immutable
class NativeVideoValue {
  final bool isInitialized;
  final bool isPlaying;
  final bool isBuffering;
  final bool isMirrorDownloading;
  final bool hasError;
  final bool hasRenderedFirstFrame;
  final String errorDescription;
  final Duration position;
  final Duration duration;
  final Size size;
  final String captionText;

  const NativeVideoValue({
    this.isInitialized = false,
    this.isPlaying = false,
    this.isBuffering = false,
    this.isMirrorDownloading = false,
    this.hasError = false,
    this.hasRenderedFirstFrame = false,
    this.errorDescription = '',
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.size = Size.zero,
    this.captionText = '',
  });

  double get aspectRatio {
    if (size.width <= 0 || size.height <= 0) return 1.0;
    final ratio = size.width / size.height;
    return ratio.isFinite && ratio > 0 ? ratio : 1.0;
  }

  NativeVideoValue copyWith({
    bool? isInitialized,
    bool? isPlaying,
    bool? isBuffering,
    bool? isMirrorDownloading,
    bool? hasError,
    bool? hasRenderedFirstFrame,
    String? errorDescription,
    Duration? position,
    Duration? duration,
    Size? size,
    String? captionText,
  }) {
    return NativeVideoValue(
      isInitialized: isInitialized ?? this.isInitialized,
      isPlaying: isPlaying ?? this.isPlaying,
      isBuffering: isBuffering ?? this.isBuffering,
      isMirrorDownloading: isMirrorDownloading ?? this.isMirrorDownloading,
      hasError: hasError ?? this.hasError,
      hasRenderedFirstFrame:
          hasRenderedFirstFrame ?? this.hasRenderedFirstFrame,
      errorDescription: errorDescription ?? this.errorDescription,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      size: size ?? this.size,
      captionText: captionText ?? this.captionText,
    );
  }
}

/// The viewer's single entry point to video playback. It forwards to a [VideoPlaybackBackend]:
/// [NativeMedia3Controller] (Media3 ExoPlayer over native MethodChannels) on Android, and
/// [DesktopVideoBackend] (libmpv, streaming from the unlocked vault) on Linux / Windows.
class NativeVideoController extends ValueNotifier<NativeVideoValue> {
  final int volId;
  final String filePath;
  final bool autoPlay;
  final bool isLocalStorage;
  final VideoPlaybackBackend _backend;

  NativeVideoController({
    required this.volId,
    required this.filePath,
    this.autoPlay = false,
    this.isLocalStorage = false,
    double initialSpeed = 1.0,
    MediaDecoderMode videoDecoderMode = MediaDecoderMode.auto,
    MediaDecoderMode audioDecoderMode = MediaDecoderMode.auto,
    bool volumeBoostEnabled = false,
    int volumeBoostGainMb = 2000,
    AudioEqualizerSettings? equalizer,
    int initialPositionMs = 0,
    bool mediaSession = false,
  }) : _backend = isDesktopEngineTarget
           ? DesktopVideoBackend(
               volId: volId,
               filePath: filePath,
               autoPlay: autoPlay,
               isLocalStorage: isLocalStorage,
               initialSpeed: initialSpeed,
               videoDecoderMode: videoDecoderMode,
               audioDecoderMode: audioDecoderMode,
               volumeBoostEnabled: volumeBoostEnabled,
               volumeBoostGainMb: volumeBoostGainMb,
               equalizer: equalizer,
               initialPositionMs: initialPositionMs,
             )
           : NativeMedia3Controller(
               volId: volId,
               filePath: filePath,
               autoPlay: autoPlay,
               isLocalStorage: isLocalStorage,
               initialSpeed: initialSpeed,
               videoDecoderMode: videoDecoderMode,
               audioDecoderMode: audioDecoderMode,
               volumeBoostEnabled: volumeBoostEnabled,
               volumeBoostGainMb: volumeBoostGainMb,
               equalizer: equalizer,
               initialPositionMs: initialPositionMs,
               mediaSession: mediaSession,
             ),
       super(const NativeVideoValue()) {
    _backend.addListener(_onBackendStateChanged);
  }

  /// Auxiliary constructor for parsing content URI string:
  /// `content://com.aeidolon.vaultexplorer.documents/document/{volId}%3Afile%3A{escapedPath}`
  factory NativeVideoController.fromUri({
    required String contentUriString,
    bool autoPlay = false,
    double initialSpeed = 1.0,
    MediaDecoderMode videoDecoderMode = MediaDecoderMode.auto,
    MediaDecoderMode audioDecoderMode = MediaDecoderMode.auto,
    bool volumeBoostEnabled = false,
    int volumeBoostGainMb = 2000,
    AudioEqualizerSettings? equalizer,
    int initialPositionMs = 0,
    bool mediaSession = false,
  }) {
    final parsed = _parseContentUri(contentUriString);
    return NativeVideoController(
      volId: parsed.volId,
      filePath: parsed.filePath,
      autoPlay: autoPlay,
      initialSpeed: initialSpeed,
      videoDecoderMode: videoDecoderMode,
      audioDecoderMode: audioDecoderMode,
      volumeBoostEnabled: volumeBoostEnabled,
      volumeBoostGainMb: volumeBoostGainMb,
      equalizer: equalizer,
      initialPositionMs: initialPositionMs,
      mediaSession: mediaSession,
    );
  }

  static ({int volId, String filePath}) _parseContentUri(String uriString) {
    try {
      final uri = Uri.parse(uriString);
      final lastSegment = Uri.decodeComponent(uri.pathSegments.last);
      // Format: "volId:type:path"
      final parts = lastSegment.split(':');
      final volId = int.parse(parts[0]);
      final filePath = parts.sublist(2).join(':');
      return (volId: volId, filePath: filePath);
    } catch (_) {
      return (volId: 0, filePath: uriString);
    }
  }

  int get initialPositionMs => _backend.initialPositionMs;

  /// What actually plays the video; the player view picks its rendering from this.
  VideoPlaybackBackend get backend => _backend;

  /// The last volume level (0-100) applied via [setVolume].
  int get currentVolume => _backend.currentVolume;
  ValueNotifier<List<AudioTrackInfo>> get audioTracksNotifier =>
      _backend.audioTracksNotifier;
  ValueNotifier<List<SubtitleTrackInfo>> get subtitleTracksNotifier =>
      _backend.subtitleTracksNotifier;
  ValueNotifier<MediaDiagnosticsInfo> get diagnosticsNotifier =>
      _backend.diagnosticsNotifier;
  List<AudioTrackInfo> get audioTracks => _backend.audioTracks;
  List<SubtitleTrackInfo> get subtitleTracks => _backend.subtitleTracks;
  MediaDiagnosticsInfo get diagnostics => _backend.diagnostics;
  Future<MediaDiagnosticsInfo> fetchDiagnostics() => _backend.fetchDiagnostics();

  void _onBackendStateChanged() {
    value = _backend.value;
  }

  Future<void> initialize() async {
    await _backend.initialize();
  }

  Future<void> play() async {
    await _backend.play();
  }

  Future<void> pause() async {
    await _backend.pause();
  }

  Future<void> seekTo(Duration position) async {
    await _backend.seekTo(position);
  }

  Future<void> setVolume(int vol) async {
    await _backend.setVolume(vol);
  }

  Future<void> setAudioOnly(bool enabled) async {
    await _backend.setAudioOnly(enabled);
  }

  /// See [NativeMedia3Controller.pauseRequested].
  bool get pauseRequested => _backend.pauseRequested;

  /// See [NativeMedia3Controller.playWhenReady].
  Future<void> playWhenReady() => _backend.playWhenReady();

  Future<void> setVolumeBoost(bool enabled, int gainMb) async {
    await _backend.setVolumeBoost(enabled, gainMb);
  }

  Future<void> setEqualizer(AudioEqualizerSettings settings) async {
    await _backend.setEqualizer(settings);
  }

  Future<void> setDecoderModes(
    MediaDecoderMode videoMode,
    MediaDecoderMode audioMode,
  ) async {
    await _backend.setDecoderModes(videoMode, audioMode);
  }

  Future<void> setPlaybackSpeed(double speed) async {
    await _backend.setPlaybackSpeed(speed);
  }

  Future<void> setLooping(bool loop) async {
    await _backend.setLooping(loop);
  }

  Future<Duration?> getExactPosition() => _backend.getExactPosition();

  Future<void> setAbLoop(Duration start, Duration end) =>
      _backend.setAbLoop(start, end);

  Future<void> setAbLoopStart(Duration start) => _backend.setAbLoopStart(start);

  Future<void> clearAbLoop() => _backend.clearAbLoop();

  Future<void> selectAudioTrack(int groupIndex, int trackIndex) async {
    await _backend.selectAudioTrack(groupIndex, trackIndex);
  }

  Future<void> selectSubtitleTrack(int groupIndex, int trackIndex) async {
    await _backend.selectSubtitleTrack(groupIndex, trackIndex);
  }

  Future<void> disableSubtitleTrack() async {
    await _backend.disableSubtitleTrack();
  }

  Future<bool> startScrubPreview() => _backend.startScrubPreview();

  Future<Uint8List?> getScrubPreviewFrame(
    Duration position, {
    int maxSize = 200,
    int quality = 55,
  }) => _backend.getScrubPreviewFrame(
    position,
    maxSize: maxSize,
    quality: quality,
  );

  Future<void> endScrubPreview() => _backend.endScrubPreview();

  bool get isDisposed => _backend.isDisposed;

  @override
  Future<void> dispose() async {
    _backend.removeListener(_onBackendStateChanged);
    await _backend.dispose();
    super.dispose();
  }
}

class NativeVideoPlayerView extends StatelessWidget {
  final NativeVideoController controller;
  const NativeVideoPlayerView({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final backend = controller.backend;
    if (backend is DesktopVideoBackend) {
      return DesktopVideoView(backend: backend);
    }
    return NativeMedia3PlayerView(
      media3Controller: backend as NativeMedia3Controller,
    );
  }
}
