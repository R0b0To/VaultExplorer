import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:vaultexplorer/core/engine/desktop/desktop_engine_binding.dart';
import 'package:vaultexplorer/core/engine/desktop/desktop_media_server.dart';
import 'package:vaultexplorer/data/models/audio_equalizer_settings.dart';
import 'package:vaultexplorer/data/models/media_decoder_mode.dart';
import 'package:vaultexplorer/features/browser/viewer/native_media3_controller.dart'
    show AudioTrackInfo, MediaDiagnosticsInfo, SubtitleTrackInfo;
import 'package:vaultexplorer/features/browser/viewer/native_video_controller.dart' show NativeVideoValue;
import 'package:vaultexplorer/features/browser/viewer/video_playback_backend.dart';

/// Video playback on Linux and Windows: libmpv (through media_kit) decoding and rendering, fed by
/// [DesktopMediaServer], which streams the decrypted bytes out of the unlocked vault over loopback HTTP.
///
/// Nothing decrypted is written to storage:
///  * the source is a loopback URL, not a file;
///  * mpv's on-disk demuxer cache (media_kit turns it on) is switched off, and playback is refused if that
///    cannot be confirmed -- see [_lockDownPlayer];
///  * mpv may only use the `http` / `tcp` protocols (`file` for plain local-storage items), so a container
///    that references other files or URLs cannot make it read or fetch anything else.
///
/// Android-only features have no meaning here and answer inertly: background playback / media session
/// (`mediaSession`), scrub-preview frames and the Media3 decoder-contention handling.
class DesktopVideoBackend extends ValueNotifier<NativeVideoValue> implements VideoPlaybackBackend {
  DesktopVideoBackend({
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
    this.initialPositionMs = 0,
    DesktopMediaServer? server,
  }) : _speed = initialSpeed,
       _videoDecoderMode = videoDecoderMode,
       _volumeBoostEnabled = volumeBoostEnabled,
       _volumeBoostGainMb = volumeBoostGainMb,
       _equalizer = equalizer ?? AudioEqualizerSettings.defaults,
       _serverOverride = server,
       super(const NativeVideoValue());

  final int volId;
  final String filePath;
  final bool autoPlay;
  final bool isLocalStorage;
  @override
  final int initialPositionMs;

  final DesktopMediaServer? _serverOverride;

  double _speed;
  MediaDecoderMode _videoDecoderMode;
  bool _volumeBoostEnabled;
  int _volumeBoostGainMb;
  AudioEqualizerSettings _equalizer;
  int _currentVolume = 100;
  bool _audioOnly = false;
  bool _looping = false;
  bool _pauseRequested = false;
  bool _playOnInit = false;
  bool _initFinished = false;
  bool _disposed = false;
  Future<void>? _initFuture;

  Player? _player;
  VideoController? _videoController;
  DesktopMediaSession? _session;
  final List<StreamSubscription<Object?>> _subscriptions = [];

  List<AudioTrack> _audioTrackRefs = const [];
  List<SubtitleTrack> _subtitleTrackRefs = const [];
  Track _selected = const Track();

  // Position events arrive on every mpv time-pos change; the viewer expects roughly Android's 200 ms cadence.
  static const Duration _positionInterval = Duration(milliseconds: 200);
  DateTime _lastPositionEmit = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _positionTimer;
  Duration _latestPosition = Duration.zero;

  @override
  final ValueNotifier<List<AudioTrackInfo>> audioTracksNotifier = ValueNotifier<List<AudioTrackInfo>>([]);
  @override
  final ValueNotifier<List<SubtitleTrackInfo>> subtitleTracksNotifier = ValueNotifier<List<SubtitleTrackInfo>>([]);
  @override
  final ValueNotifier<MediaDiagnosticsInfo> diagnosticsNotifier = ValueNotifier<MediaDiagnosticsInfo>(
    const MediaDiagnosticsInfo(),
  );

  @override
  List<AudioTrackInfo> get audioTracks => audioTracksNotifier.value;
  @override
  List<SubtitleTrackInfo> get subtitleTracks => subtitleTracksNotifier.value;
  @override
  MediaDiagnosticsInfo get diagnostics => diagnosticsNotifier.value;
  @override
  int get currentVolume => _currentVolume;
  @override
  bool get pauseRequested => _pauseRequested;
  @override
  bool get isDisposed => _disposed;

  /// The media_kit controller the video widget renders; null until [initialize] has created it.
  VideoController? get videoController => _videoController;

  // ── lifecycle ───────────────────────────────────────────────────────────

  @override
  Future<void> initialize() => _initFuture ??= _initialize();

  Future<void> _initialize() async {
    if (_disposed) return;
    value = value.copyWith(isInitialized: false, hasRenderedFirstFrame: false, captionText: '');
    try {
      MediaKit.ensureInitialized();
      final player = Player(
        configuration: PlayerConfiguration(
          title: 'Vault Explorer',
          // Only the protocol the source uses: see the class comment.
          protocolWhitelist: isLocalStorage ? const ['file'] : const ['http', 'tcp'],
        ),
      );
      _player = player;
      await _lockDownPlayer(player);

      _videoController = VideoController(
        player,
        configuration: VideoControllerConfiguration(
          enableHardwareAcceleration: _videoDecoderMode != MediaDecoderMode.software &&
              _videoDecoderMode != MediaDecoderMode.ffmpeg,
        ),
      );
      _listen(player);
      unawaited(
        _videoController!.waitUntilFirstFrameRendered.then((_) {
          if (!_disposed) value = value.copyWith(hasRenderedFirstFrame: true);
        }, onError: (Object _) {}),
      );
      // The widget may already be waiting for the controller.
      notifyListeners();

      await _applyHwdec(player);
      final Media media;
      if (isLocalStorage) {
        media = Media(Uri.file(filePath).toString(), start: _startOrNull());
      } else {
        final server = _serverOverride ?? DesktopEngineRuntime.instance.host.mediaServer;
        final session = await server.open(volId: volId, filePath: filePath);
        if (_disposed) {
          await session.close();
          return;
        }
        _session = session;
        media = Media(session.url, start: _startOrNull());
      }
      await player.open(media, play: false);
      if (_disposed) return;

      await _applyAudioFilters();
      if (_speed != 1.0) await _tryAsync(() => player.setRate(_speed));
      if (_currentVolume != 100) await _tryAsync(() => player.setVolume(_currentVolume.toDouble()));
      if (_audioOnly) await _tryAsync(() => player.setVideoTrack(VideoTrack.no()));
      if (_looping) await _tryAsync(() => player.setPlaylistMode(PlaylistMode.single));

      final startNow = (autoPlay || _playOnInit) && !_disposed;
      _initFinished = true;
      if (startNow) await play();
    } on Object catch (e) {
      if (_disposed) return;
      value = NativeVideoValue(hasError: true, errorDescription: _describeInitError(e));
    }
  }

  Duration? _startOrNull() => initialPositionMs > 0 ? Duration(milliseconds: initialPositionMs) : null;

  /// Turns off everything of media_kit's / mpv's that could persist decrypted data, and checks it took.
  /// media_kit enables `cache-on-disk` by default, which would spool the (decrypted) stream into a temp file.
  Future<void> _lockDownPlayer(Player player) async {
    final native = player.platform;
    if (native is! NativePlayer) {
      throw StateError('Unsupported player backend');
    }
    await native.setProperty('cache-on-disk', 'no');
    final confirmed = await native.getProperty('cache-on-disk');
    if (confirmed != 'no') {
      throw StateError('Refusing to play: could not disable the on-disk media cache');
    }
    // No sidecar discovery, and nothing remembered about what was watched.
    await native.setProperty('sub-auto', 'no');
    await native.setProperty('audio-file-auto', 'no');
    await native.setProperty('save-position-on-quit', 'no');
  }

  Future<void> _applyHwdec(Player player) async {
    final native = player.platform;
    if (native is! NativePlayer) return;
    final mode = switch (_videoDecoderMode) {
      MediaDecoderMode.auto => 'auto-safe',
      MediaDecoderMode.hardware => 'auto',
      MediaDecoderMode.software || MediaDecoderMode.ffmpeg => 'no',
    };
    await _tryAsync(() => native.setProperty('hwdec', mode));
  }

  String _describeInitError(Object error) {
    final text = error.toString();
    final lower = text.toLowerCase();
    final missingLibrary = lower.contains('libmpv') ||
        lower.contains('mpv-2') ||
        lower.contains('mpv-1') ||
        lower.contains('cannot open shared object') ||
        lower.contains('failed to load dynamic library') ||
        lower.contains('could not be located');
    if (missingLibrary) {
      return Platform.isLinux
          ? 'Video playback needs libmpv. Install your distribution\'s libmpv package (e.g. libmpv2) and restart.'
          : 'Video playback library (libmpv) is missing from this installation.';
    }
    return text;
  }

  // ── events ──────────────────────────────────────────────────────────────

  void _listen(Player player) {
    final s = player.stream;
    void sub<T>(Stream<T> stream, void Function(T) onData) {
      _subscriptions.add(
        stream.listen((v) {
          if (!_disposed) onData(v);
        }, onError: (Object _) {}),
      );
    }

    sub<bool>(s.playing, (playing) {
      value = value.copyWith(isPlaying: playing, isInitialized: value.isInitialized || playing);
    });
    sub<bool>(s.buffering, (b) => value = value.copyWith(isBuffering: b));
    sub<Duration>(s.duration, (d) {
      value = value.copyWith(duration: d, isInitialized: value.isInitialized || d > Duration.zero);
    });
    sub<Duration>(s.position, _onPosition);
    sub<VideoParams>(s.videoParams, (p) {
      final w = (p.dw ?? p.w ?? 0).toDouble();
      final h = (p.dh ?? p.h ?? 0).toDouble();
      if (w > 0 && h > 0) value = value.copyWith(size: Size(w, h), isInitialized: true);
    });
    sub<bool>(s.completed, (done) {
      if (done) {
        _positionTimer?.cancel();
        value = value.copyWith(isPlaying: false, position: value.duration);
      }
    });
    sub<List<String>>(s.subtitle, (lines) {
      final text = lines.where((l) => l.trim().isNotEmpty).join('\n');
      if (text != value.captionText) value = value.copyWith(captionText: text);
    });
    sub<Tracks>(s.tracks, (t) {
      _audioTrackRefs = [for (final a in t.audio) if (_isRealTrack(a.id)) a];
      _subtitleTrackRefs = [for (final x in t.subtitle) if (_isRealTrack(x.id)) x];
      _publishTracks();
    });
    sub<Track>(s.track, (t) {
      _selected = t;
      _publishTracks();
    });
    sub<String>(s.error, (message) {
      if (message.trim().isEmpty) return;
      value = value.copyWith(hasError: true, errorDescription: message);
    });
  }

  static bool _isRealTrack(String id) => id != 'auto' && id != 'no';

  void _onPosition(Duration position) {
    _latestPosition = position;
    final now = DateTime.now();
    if (now.difference(_lastPositionEmit) >= _positionInterval) {
      _emitPosition();
    } else {
      // Trailing emit, so the last position before a pause or a seek is never lost.
      _positionTimer ??= Timer(_positionInterval, () {
        _positionTimer = null;
        if (!_disposed) _emitPosition();
      });
    }
  }

  void _emitPosition() {
    _lastPositionEmit = DateTime.now();
    value = value.copyWith(
      position: _latestPosition,
      hasRenderedFirstFrame: value.hasRenderedFirstFrame || _latestPosition > Duration.zero,
    );
  }

  void _publishTracks() {
    audioTracksNotifier.value = [
      for (var i = 0; i < _audioTrackRefs.length; i++)
        () {
          final t = _audioTrackRefs[i];
          return AudioTrackInfo(
            groupIndex: 0,
            trackIndex: i,
            isSelected: t.id == _selected.audio.id,
            language: t.language ?? '',
            label: _label(t.title, t.language, 'Audio ${i + 1}'),
            mimeType: t.codec ?? '',
            id: t.id,
            channelCount: t.audiochannels ?? t.channelscount,
            sampleRate: t.samplerate,
            bitrate: t.bitrate,
          );
        }(),
    ];
    final subtitleOff = _selected.subtitle.id == 'no';
    subtitleTracksNotifier.value = [
      for (var i = 0; i < _subtitleTrackRefs.length; i++)
        () {
          final t = _subtitleTrackRefs[i];
          return SubtitleTrackInfo(
            groupIndex: 0,
            trackIndex: i,
            isSelected: !subtitleOff && t.id == _selected.subtitle.id,
            language: t.language ?? '',
            label: _label(t.title, t.language, 'Subtitle ${i + 1}'),
            mimeType: t.codec ?? '',
            id: t.id,
          );
        }(),
    ];
  }

  static String _label(String? title, String? language, String fallback) {
    final t = title?.trim();
    if (t != null && t.isNotEmpty) return t;
    final l = language?.trim();
    if (l != null && l.isNotEmpty) return l;
    return fallback;
  }

  // ── transport ───────────────────────────────────────────────────────────

  @override
  Future<void> play() async {
    _pauseRequested = false;
    final p = _player;
    if (!_disposed && p != null) await p.play();
  }

  @override
  Future<void> pause() async {
    _pauseRequested = true;
    final p = _player;
    if (!_disposed && p != null) await p.pause();
  }

  @override
  Future<void> playWhenReady() async {
    if (_disposed) return;
    if (_initFinished) {
      await play();
    } else {
      _pauseRequested = false;
      _playOnInit = true;
    }
  }

  @override
  Future<void> seekTo(Duration position) async {
    final p = _player;
    if (_disposed || p == null) return;
    // Shown at once; mpv's own position events catch up after the seek lands.
    value = value.copyWith(position: position);
    await p.seek(position);
  }

  @override
  Future<void> setVolume(int vol) async {
    _currentVolume = vol.clamp(0, 100);
    final p = _player;
    if (!_disposed && p != null) await p.setVolume(_currentVolume.toDouble());
  }

  @override
  Future<void> setAudioOnly(bool enabled) async {
    _audioOnly = enabled;
    final p = _player;
    if (!_disposed && p != null) await p.setVideoTrack(enabled ? VideoTrack.no() : VideoTrack.auto());
  }

  @override
  Future<void> setPlaybackSpeed(double speed) async {
    _speed = speed;
    final p = _player;
    if (!_disposed && p != null) await _tryAsync(() => p.setRate(speed));
  }

  @override
  Future<void> setLooping(bool loop) async {
    _looping = loop;
    final p = _player;
    if (!_disposed && p != null) await p.setPlaylistMode(loop ? PlaylistMode.single : PlaylistMode.none);
  }

  @override
  Future<Duration?> getExactPosition() async {
    final native = _player?.platform;
    if (_disposed || native is! NativePlayer) return null;
    try {
      final seconds = double.tryParse(await native.getProperty('time-pos'));
      if (seconds == null || seconds < 0) return null;
      return Duration(microseconds: (seconds * Duration.microsecondsPerSecond).round());
    } on Object {
      return null;
    }
  }

  // ── A-B loop (mpv's own, so the jump back happens inside the player) ─────

  String _seconds(Duration d) => (d.inMicroseconds / Duration.microsecondsPerSecond).toStringAsFixed(3);

  Future<void> _setProps(Map<String, String> props) async {
    final native = _player?.platform;
    if (_disposed || native is! NativePlayer) return;
    for (final e in props.entries) {
      await native.setProperty(e.key, e.value);
    }
  }

  @override
  Future<void> setAbLoop(Duration start, Duration end) =>
      _setProps({'ab-loop-a': _seconds(start), 'ab-loop-b': _seconds(end)});

  @override
  Future<void> setAbLoopStart(Duration start) => _setProps({'ab-loop-a': _seconds(start), 'ab-loop-b': 'no'});

  @override
  Future<void> clearAbLoop() => _setProps({'ab-loop-a': 'no', 'ab-loop-b': 'no'});

  // ── tracks ──────────────────────────────────────────────────────────────

  @override
  Future<void> selectAudioTrack(int groupIndex, int trackIndex) async {
    final p = _player;
    if (_disposed || p == null || trackIndex < 0 || trackIndex >= _audioTrackRefs.length) return;
    await p.setAudioTrack(_audioTrackRefs[trackIndex]);
  }

  @override
  Future<void> selectSubtitleTrack(int groupIndex, int trackIndex) async {
    final p = _player;
    if (_disposed || p == null || trackIndex < 0 || trackIndex >= _subtitleTrackRefs.length) return;
    await p.setSubtitleTrack(_subtitleTrackRefs[trackIndex]);
  }

  @override
  Future<void> disableSubtitleTrack() async {
    final p = _player;
    if (!_disposed && p != null) await p.setSubtitleTrack(SubtitleTrack.no());
  }

  // ── audio processing ────────────────────────────────────────────────────

  @override
  Future<void> setVolumeBoost(bool enabled, int gainMb) async {
    _volumeBoostEnabled = enabled;
    _volumeBoostGainMb = gainMb.clamp(0, 2000);
    await _applyAudioFilters();
  }

  @override
  Future<void> setEqualizer(AudioEqualizerSettings settings) async {
    _equalizer = settings;
    await _applyAudioFilters();
  }

  /// The audio filter chain for the current boost and equalizer, in mpv's `lavfi` syntax; empty when neither
  /// does anything. Pure, so it can be checked without a player.
  @visibleForTesting
  static String audioFilterChain({
    required bool boostEnabled,
    required int boostGainMb,
    required AudioEqualizerSettings equalizer,
  }) {
    final filters = <String>[];
    var gainDb = boostEnabled ? boostGainMb / 100.0 : 0.0;
    if (equalizer.enabled) {
      var preamp = equalizer.preampDb;
      if (equalizer.preventClipping) {
        preamp -= math.max(0.0, equalizer.bandGainsDb.fold<double>(0.0, math.max));
      }
      gainDb += preamp;
      for (var i = 0; i < equalizer.bandGainsDb.length && i < kEqualizerBandFrequenciesHz.length; i++) {
        final g = equalizer.bandGainsDb[i];
        if (g == 0) continue;
        filters.add('equalizer=f=${kEqualizerBandFrequenciesHz[i]}:t=o:w=1:g=${g.toStringAsFixed(1)}');
      }
    }
    if (gainDb.abs() >= 0.05) filters.insert(0, 'volume=${gainDb.toStringAsFixed(1)}dB');
    return filters.isEmpty ? '' : 'lavfi=[${filters.join(',')}]';
  }

  Future<void> _applyAudioFilters() async {
    final native = _player?.platform;
    if (_disposed || native is! NativePlayer) return;
    final chain = audioFilterChain(
      boostEnabled: _volumeBoostEnabled,
      boostGainMb: _volumeBoostGainMb,
      equalizer: _equalizer,
    );
    await _tryAsync(() => native.setProperty('af', chain));
  }

  @override
  Future<void> setDecoderModes(MediaDecoderMode videoMode, MediaDecoderMode audioMode) async {
    _videoDecoderMode = videoMode;
    final p = _player;
    if (!_disposed && p != null) await _applyHwdec(p);
  }

  // ── diagnostics ─────────────────────────────────────────────────────────

  @override
  Future<MediaDiagnosticsInfo> fetchDiagnostics() async {
    final native = _player?.platform;
    if (_disposed || native is! NativePlayer) return diagnostics;
    Future<String> prop(String name) async {
      try {
        return await native.getProperty(name);
      } on Object {
        return '';
      }
    }

    final hwdec = await prop('hwdec-current');
    final videoCodec = await prop('video-codec');
    final audioCodec = await prop('audio-codec-name');
    final fps = double.tryParse(await prop('container-fps')) ?? 0.0;
    final dropped = int.tryParse(await prop('frame-drop-count')) ?? 0;
    final matrix = await prop('video-params/colormatrix');
    final gamma = await prop('video-params/gamma');
    final p = _player;
    final bufferedMs = p == null ? 0 : (p.state.buffer - p.state.position).inMilliseconds.clamp(0, 1 << 30);
    final hardware = hwdec.isNotEmpty && hwdec != 'no';
    final info = MediaDiagnosticsInfo(
      videoDecoderName: hardware ? 'mpv ($hwdec)' : 'mpv (software)',
      isVideoHardwareAccelerated: hardware,
      audioDecoderName: audioCodec.isEmpty ? 'Unknown' : audioCodec,
      isAudioHardwareAccelerated: false,
      frameRate: fps,
      videoMimeType: videoCodec,
      audioMimeType: audioCodec,
      droppedFrames: dropped,
      bufferedMs: bufferedMs,
      colorInfo: gamma == 'pq' || gamma == 'hlg' ? 'HDR ($gamma)' : (matrix.isEmpty ? 'SDR' : 'SDR ($matrix)'),
      volId: volId,
      filePath: filePath,
    );
    diagnosticsNotifier.value = info;
    return info;
  }

  // ── scrub preview: not offered on desktop (the viewer hides the preview when this answers false) ──

  @override
  Future<bool> startScrubPreview() async => false;

  @override
  Future<Uint8List?> getScrubPreviewFrame(Duration position, {int maxSize = 200, int quality = 55}) async => null;

  @override
  Future<void> endScrubPreview() async {}

  // ── teardown ────────────────────────────────────────────────────────────

  static Future<void> _tryAsync(Future<void> Function() body) async {
    try {
      await body();
    } on Object {
      // Non-fatal: the setting just does not apply to this player.
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _positionTimer?.cancel();
    value = const NativeVideoValue();
    for (final s in _subscriptions) {
      await s.cancel();
    }
    _subscriptions.clear();
    final session = _session;
    _session = null;
    if (session != null) await _tryAsync(session.close);
    final player = _player;
    _player = null;
    _videoController = null;
    if (player != null) await _tryAsync(player.dispose);
    audioTracksNotifier.dispose();
    subtitleTracksNotifier.dispose();
    super.dispose();
  }
}
