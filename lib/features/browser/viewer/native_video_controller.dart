import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:vaultexplorer/features/browser/viewer/native_media3_controller.dart';
import 'package:vaultexplorer/features/browser/viewer/native_media3_player_view.dart';

@immutable
class NativeVideoValue {
  final bool isInitialized;
  final bool isPlaying;
  final bool isBuffering;
  final bool hasError;
  final bool hasRenderedFirstFrame;
  final String errorDescription;
  final Duration position;
  final Duration duration;
  final Size size;

  const NativeVideoValue({
    this.isInitialized = false,
    this.isPlaying = false,
    this.isBuffering = false,
    this.hasError = false,
    this.hasRenderedFirstFrame = false,
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

  NativeVideoValue copyWith({
    bool? isInitialized,
    bool? isPlaying,
    bool? isBuffering,
    bool? hasError,
    bool? hasRenderedFirstFrame,
    String? errorDescription,
    Duration? position,
    Duration? duration,
    Size? size,
  }) {
    return NativeVideoValue(
      isInitialized: isInitialized ?? this.isInitialized,
      isPlaying: isPlaying ?? this.isPlaying,
      isBuffering: isBuffering ?? this.isBuffering,
      hasError: hasError ?? this.hasError,
      hasRenderedFirstFrame: hasRenderedFirstFrame ?? this.hasRenderedFirstFrame,
      errorDescription: errorDescription ?? this.errorDescription,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      size: size ?? this.size,
    );
  }
}

/// Refactored controller backed by [NativeMedia3Controller] directly communicating
/// with the Media3 ExoPlayer instance over native MethodChannels.
class NativeVideoController extends ValueNotifier<NativeVideoValue> {
  final int volId;
  final String filePath;
  final bool autoPlay;
  final NativeMedia3Controller _media3;

  NativeVideoController({
    required this.volId,
    required this.filePath,
    this.autoPlay = false,
    double initialSpeed = 1.0,
  })  : _media3 = NativeMedia3Controller(
          volId: volId,
          filePath: filePath,
          autoPlay: autoPlay,
          initialSpeed: initialSpeed,
        ),
        super(const NativeVideoValue()) {
    _media3.addListener(_onMedia3StateChanged);
  }

  /// Auxiliary constructor for parsing content URI string:
  /// `content://com.aeidolon.vaultexplorer.documents/document/{volId}%3Afile%3A{escapedPath}`
  factory NativeVideoController.fromUri({
    required String contentUriString,
    bool autoPlay = false,
    double initialSpeed = 1.0,
  }) {
    final parsed = _parseContentUri(contentUriString);
    return NativeVideoController(
      volId: parsed.volId,
      filePath: parsed.filePath,
      autoPlay: autoPlay,
      initialSpeed: initialSpeed,
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

  NativeMedia3Controller get media3Controller => _media3;
  ValueNotifier<List<AudioTrackInfo>> get audioTracksNotifier => _media3.audioTracksNotifier;
  ValueNotifier<List<SubtitleTrackInfo>> get subtitleTracksNotifier => _media3.subtitleTracksNotifier;
  ValueNotifier<MediaDiagnosticsInfo> get diagnosticsNotifier => _media3.diagnosticsNotifier;
  List<AudioTrackInfo> get audioTracks => _media3.audioTracks;
  List<SubtitleTrackInfo> get subtitleTracks => _media3.subtitleTracks;
  MediaDiagnosticsInfo get diagnostics => _media3.diagnostics;
  Future<MediaDiagnosticsInfo> fetchDiagnostics() => _media3.fetchDiagnostics();

  void _onMedia3StateChanged() {
    value = _media3.value;
  }

Future<void> initialize() async {
    await _media3.initialize();
  }

  Future<void> play() async {
    await _media3.play();
  }

  Future<void> pause() async {
    await _media3.pause();
  }

  Future<void> seekTo(Duration position) async {
    await _media3.seekTo(position);
  }

  Future<void> setVolume(int vol) async {
    await _media3.setVolume(vol);
  }

  Future<void> setPlaybackSpeed(double speed) async {
    await _media3.setPlaybackSpeed(speed);
  }

  Future<void> setLooping(bool loop) async {
    await _media3.setLooping(loop);
  }

  Future<void> selectAudioTrack(int groupIndex, int trackIndex) async {
    await _media3.selectAudioTrack(groupIndex, trackIndex);
  }

  Future<void> selectSubtitleTrack(int groupIndex, int trackIndex) async {
    await _media3.selectSubtitleTrack(groupIndex, trackIndex);
  }

  Future<void> disableSubtitleTrack() async {
    await _media3.disableSubtitleTrack();
  }

  bool get isDisposed => _media3.isDisposed;

  @override
  Future<void> dispose() async {
    _media3.removeListener(_onMedia3StateChanged);
    await _media3.dispose();
    super.dispose();
  }
}

class NativeVideoPlayerView extends StatelessWidget {
  final NativeVideoController controller;
  const NativeVideoPlayerView({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return NativeMedia3PlayerView(media3Controller: controller.media3Controller);
  }
}