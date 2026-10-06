import 'dart:async';
import 'dart:convert';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/data/services/app_secure_storage.dart';
import 'package:vaultexplorer/core/api/vault_engine_types.dart' show logSwallowed;

part 'camera_capture_controls_controller.g.dart';

class CameraCaptureControlsState {
  const CameraCaptureControlsState({
    this.isVideoMode = false,
    this.flashMode = 'auto',
    this.videoQuality = 'fhd',
    this.photoResolution = 'max',
    this.timerDelaySeconds = 0,
    this.aspectRatio = 4 / 3,
    this.preferredFacing = 'back',
  });

  final bool isVideoMode;
  final String flashMode;
  final String videoQuality;
  final String photoResolution;
  final int timerDelaySeconds;
  final double aspectRatio;
  final String preferredFacing;

  CameraCaptureControlsState copyWith({
    bool? isVideoMode,
    String? flashMode,
    String? videoQuality,
    String? photoResolution,
    int? timerDelaySeconds,
    double? aspectRatio,
    String? preferredFacing,
  }) => CameraCaptureControlsState(
    isVideoMode: isVideoMode ?? this.isVideoMode,
    flashMode: flashMode ?? this.flashMode,
    videoQuality: videoQuality ?? this.videoQuality,
    photoResolution: photoResolution ?? this.photoResolution,
    timerDelaySeconds: timerDelaySeconds ?? this.timerDelaySeconds,
    aspectRatio: aspectRatio ?? this.aspectRatio,
    preferredFacing: preferredFacing ?? this.preferredFacing,
  );

  Map<String, dynamic> toJson() => {
    'isVideoMode': isVideoMode,
    'flashMode': flashMode,
    'videoQuality': videoQuality,
    'photoResolution': photoResolution,
    'timerDelaySeconds': timerDelaySeconds,
    'aspectRatio': aspectRatio,
    'preferredFacing': preferredFacing,
  };

  factory CameraCaptureControlsState.fromJson(Map<String, dynamic> json) =>
      CameraCaptureControlsState(
        isVideoMode: json['isVideoMode'] as bool? ?? false,
        flashMode: json['flashMode'] as String? ?? 'auto',
        videoQuality: json['videoQuality'] as String? ?? 'fhd',
        photoResolution: json['photoResolution'] as String? ?? 'max',
        timerDelaySeconds: (json['timerDelaySeconds'] as num?)?.toInt() ?? 0,
        aspectRatio: (json['aspectRatio'] as num?)?.toDouble() ?? 4 / 3,
        preferredFacing: json['preferredFacing'] as String? ?? 'back',
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CameraCaptureControlsState &&
          runtimeType == other.runtimeType &&
          isVideoMode == other.isVideoMode &&
          flashMode == other.flashMode &&
          videoQuality == other.videoQuality &&
          photoResolution == other.photoResolution &&
          timerDelaySeconds == other.timerDelaySeconds &&
          aspectRatio == other.aspectRatio &&
          preferredFacing == other.preferredFacing;

  @override
  int get hashCode => Object.hash(
    isVideoMode,
    flashMode,
    videoQuality,
    photoResolution,
    timerDelaySeconds,
    aspectRatio,
    preferredFacing,
  );
}

@Riverpod(keepAlive: true)
class CameraCaptureControls extends _$CameraCaptureControls {
  static const String storageKeyPrefix = 'camera_capture_controls_';
  static final Map<String, CameraCaptureControlsState> cachedStates = {};

  /// Overrides for testing without platform channels
  static Future<String?> Function(String key)? storageReadOverride;
  static Future<void> Function(String key, String value)? storageWriteOverride;

  @override
  CameraCaptureControlsState build(String sessionKey) {
    final initial = cachedStates[sessionKey] ?? const CameraCaptureControlsState();
    unawaited(_loadFromStorage(sessionKey));
    return initial;
  }

  Future<void> loadPersisted() async {
    await _loadFromStorage(sessionKey);
  }

  Future<void> _loadFromStorage(String key) async {
    try {
      final String? raw;
      if (storageReadOverride != null) {
        raw = await storageReadOverride!('$storageKeyPrefix$key');
      } else {
        raw = await AppSecureStorage.instance.read(key: '$storageKeyPrefix$key');
      }
      if (raw != null && raw.isNotEmpty) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        final loaded = CameraCaptureControlsState.fromJson(map);
        cachedStates[key] = loaded;
        state = loaded;
      }
    } catch (e) {
      logSwallowed('_loadFromStorage', e);
    }
  }

  Future<void> _persistState() async {
    cachedStates[sessionKey] = state;
    try {
      final jsonStr = jsonEncode(state.toJson());
      if (storageWriteOverride != null) {
        await storageWriteOverride!('$storageKeyPrefix$sessionKey', jsonStr);
      } else {
        await AppSecureStorage.instance.write(
          key: '$storageKeyPrefix$sessionKey',
          value: jsonStr,
        );
      }
    } catch (e) {
      logSwallowed('_persistState', e);
    }
  }

  void selectVideoQuality(String value) {
    if (state.videoQuality == value) return;
    state = state.copyWith(videoQuality: value);
    _persistState();
  }

  void selectPhotoResolution(String value) {
    if (state.photoResolution == value) return;
    state = state.copyWith(photoResolution: value);
    _persistState();
  }

  void setVideoMode(bool value) {
    if (state.isVideoMode == value) return;
    state = state.copyWith(
      isVideoMode: value,
      flashMode: value ? 'off' : 'auto',
    );
    _persistState();
  }

  void cycleTimerDelay() {
    final next = switch (state.timerDelaySeconds) {
      0 => 3,
      3 => 10,
      _ => 0,
    };
    state = state.copyWith(timerDelaySeconds: next);
    _persistState();
  }

  String cyclePhotoFlashMode() {
    final next = switch (state.flashMode) {
      'auto' => 'on',
      'on' => 'off',
      _ => 'auto',
    };
    state = state.copyWith(flashMode: next);
    _persistState();
    return next;
  }

  void selectAspectRatio(double value) {
    if ((state.aspectRatio - value).abs() < 0.001) return;
    state = state.copyWith(aspectRatio: value);
    _persistState();
  }

  void setPreferredFacing(String value) {
    if (state.preferredFacing == value) return;
    state = state.copyWith(preferredFacing: value);
    _persistState();
  }
}