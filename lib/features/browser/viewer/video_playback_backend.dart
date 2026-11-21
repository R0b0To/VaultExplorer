import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:vaultexplorer/data/models/audio_equalizer_settings.dart';
import 'package:vaultexplorer/data/models/media_decoder_mode.dart';
import 'package:vaultexplorer/features/browser/viewer/native_media3_controller.dart';
import 'package:vaultexplorer/features/browser/viewer/native_video_controller.dart';

/// What [NativeVideoController] needs from whatever actually plays the video.
///
/// Two implementations exist: [NativeMedia3Controller] (Android: Media3 ExoPlayer behind a method channel)
/// and `DesktopVideoBackend` (Linux / Windows: libmpv through media_kit, fed by the loopback range server in
/// `desktop_media_server.dart`). The viewer only ever talks to [NativeVideoController], which forwards here,
/// so neither side leaks into the viewer's code.
abstract interface class VideoPlaybackBackend implements ValueListenable<NativeVideoValue> {
  int get initialPositionMs;

  /// The last volume level (0-100) applied via [setVolume].
  int get currentVolume;

  ValueNotifier<List<AudioTrackInfo>> get audioTracksNotifier;
  ValueNotifier<List<SubtitleTrackInfo>> get subtitleTracksNotifier;
  ValueNotifier<MediaDiagnosticsInfo> get diagnosticsNotifier;
  List<AudioTrackInfo> get audioTracks;
  List<SubtitleTrackInfo> get subtitleTracks;
  MediaDiagnosticsInfo get diagnostics;
  Future<MediaDiagnosticsInfo> fetchDiagnostics();

  Future<void> initialize();
  Future<void> play();
  Future<void> pause();
  Future<void> seekTo(Duration position);
  Future<void> setVolume(int vol);
  Future<void> setAudioOnly(bool enabled);

  /// Whether the last thing asked of the player was to pause it.
  bool get pauseRequested;

  /// Plays as soon as the player can: at once when initialized, otherwise right after it is.
  Future<void> playWhenReady();

  Future<void> setVolumeBoost(bool enabled, int gainMb);
  Future<void> setEqualizer(AudioEqualizerSettings settings);
  Future<void> setDecoderModes(MediaDecoderMode videoMode, MediaDecoderMode audioMode);
  Future<void> setPlaybackSpeed(double speed);
  Future<void> setLooping(bool loop);

  /// The player's exact position right now; null when it cannot be read.
  Future<Duration?> getExactPosition();

  Future<void> setAbLoop(Duration start, Duration end);
  Future<void> setAbLoopStart(Duration start);
  Future<void> clearAbLoop();

  Future<void> selectAudioTrack(int groupIndex, int trackIndex);
  Future<void> selectSubtitleTrack(int groupIndex, int trackIndex);
  Future<void> disableSubtitleTrack();

  Future<bool> startScrubPreview();
  Future<Uint8List?> getScrubPreviewFrame(Duration position, {int maxSize = 200, int quality = 55});
  Future<void> endScrubPreview();

  bool get isDisposed;
  Future<void> dispose();
}
