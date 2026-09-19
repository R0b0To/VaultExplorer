import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/data/models/video_aspect_ratio_mode.dart';
import 'package:vaultexplorer/features/browser/viewer/native_video_controller.dart';

part 'advanced_settings_controller.g.dart';

@immutable
class AdvancedSettingsParams {
  final int initialRotation;
  final BoxFit initialImageFit;
  final int initialSlideshowDelaySeconds;
  final double initialPlaybackSpeed;
  final VideoAspectRatioMode initialAspectRatioMode;
  final bool initialSubtitlesEnabled;
  final double initialSubtitleFontSize;
  final double initialSubtitleVerticalPosition;

  const AdvancedSettingsParams({
    required this.initialRotation,
    required this.initialImageFit,
    required this.initialSlideshowDelaySeconds,
    required this.initialPlaybackSpeed,
    this.initialAspectRatioMode = VideoAspectRatioMode.bestFit,
    required this.initialSubtitlesEnabled,
    this.initialSubtitleFontSize = 15.0,
    this.initialSubtitleVerticalPosition = 0.0,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdvancedSettingsParams &&
          other.initialRotation == initialRotation &&
          other.initialImageFit == initialImageFit &&
          other.initialSlideshowDelaySeconds == initialSlideshowDelaySeconds &&
          other.initialPlaybackSpeed == initialPlaybackSpeed &&
          other.initialAspectRatioMode == initialAspectRatioMode &&
          other.initialSubtitlesEnabled == initialSubtitlesEnabled &&
          other.initialSubtitleFontSize == initialSubtitleFontSize &&
          other.initialSubtitleVerticalPosition == initialSubtitleVerticalPosition;

  @override
  int get hashCode => Object.hash(
        initialRotation,
        initialImageFit,
        initialSlideshowDelaySeconds,
        initialPlaybackSpeed,
        initialAspectRatioMode,
        initialSubtitlesEnabled,
        initialSubtitleFontSize,
        initialSubtitleVerticalPosition,
      );
}

class AdvancedSettingsState {
  final String sheetPage;
  final int rotation;
  final BoxFit imageFit;
  final int slideshowDelaySeconds;
  final double playbackSpeed;
  final VideoAspectRatioMode aspectRatioMode;
  final bool subtitlesEnabled;
  final double subtitleFontSize;
  final double subtitleVerticalPosition;

  const AdvancedSettingsState({
    this.sheetPage = 'main',
    required this.rotation,
    required this.imageFit,
    required this.slideshowDelaySeconds,
    required this.playbackSpeed,
    this.aspectRatioMode = VideoAspectRatioMode.bestFit,
    required this.subtitlesEnabled,
    required this.subtitleFontSize,
    required this.subtitleVerticalPosition,
  });

  AdvancedSettingsState _copy({
    String? sheetPage,
    int? rotation,
    BoxFit? imageFit,
    int? slideshowDelaySeconds,
    double? playbackSpeed,
    VideoAspectRatioMode? aspectRatioMode,
    bool? subtitlesEnabled,
    double? subtitleFontSize,
    double? subtitleVerticalPosition,
  }) => AdvancedSettingsState(
    sheetPage: sheetPage ?? this.sheetPage,
    rotation: rotation ?? this.rotation,
    imageFit: imageFit ?? this.imageFit,
    slideshowDelaySeconds: slideshowDelaySeconds ?? this.slideshowDelaySeconds,
    playbackSpeed: playbackSpeed ?? this.playbackSpeed,
    aspectRatioMode: aspectRatioMode ?? this.aspectRatioMode,
    subtitlesEnabled: subtitlesEnabled ?? this.subtitlesEnabled,
    subtitleFontSize: subtitleFontSize ?? this.subtitleFontSize,
    subtitleVerticalPosition: subtitleVerticalPosition ?? this.subtitleVerticalPosition,
  );
}

@riverpod
class AdvancedSettingsController extends _$AdvancedSettingsController {
  @override
  AdvancedSettingsState build(AdvancedSettingsParams params) {
    return AdvancedSettingsState(
      rotation: params.initialRotation,
      imageFit: params.initialImageFit,
      slideshowDelaySeconds: params.initialSlideshowDelaySeconds,
      playbackSpeed: params.initialPlaybackSpeed,
      aspectRatioMode: params.initialAspectRatioMode,
      subtitlesEnabled: params.initialSubtitlesEnabled,
      subtitleFontSize: params.initialSubtitleFontSize,
      subtitleVerticalPosition: params.initialSubtitleVerticalPosition,
    );
  }

  void setSheetPage(String page) => state = state._copy(sheetPage: page);

  void rotate(ValueChanged<int> onRotationChanged) {
    final nextRotation = (state.rotation + 1) % 4;
    state = state._copy(rotation: nextRotation);
    onRotationChanged(nextRotation);
  }

  void setImageFit(BoxFit fit, ValueChanged<BoxFit> onImageFitChanged) {
    state = state._copy(imageFit: fit);
    onImageFitChanged(fit);
  }

  void setSlideshowDelay(int delay, ValueChanged<int> onSlideshowDelayChanged) {
    state = state._copy(slideshowDelaySeconds: delay);
    onSlideshowDelayChanged(delay);
  }

  void setPlaybackSpeed(double speed, ValueChanged<double> onPlaybackSpeedChanged) {
    state = state._copy(playbackSpeed: speed);
    onPlaybackSpeedChanged(speed);
  }

  void setAspectRatioMode(
    VideoAspectRatioMode mode,
    ValueChanged<VideoAspectRatioMode> onAspectRatioModeChanged,
  ) {
    state = state._copy(aspectRatioMode: mode);
    onAspectRatioModeChanged(mode);
  }

  void setSubtitlesEnabled(bool enabled, ValueChanged<bool> onSubtitlesEnabledChanged) {
    state = state._copy(subtitlesEnabled: enabled);
    onSubtitlesEnabledChanged(enabled);
  }

  void disableSubtitles(
    NativeVideoController? videoController,
    ValueChanged<bool> onSubtitlesEnabledChanged,
  ) {
    videoController?.disableSubtitleTrack();
    state = state._copy(subtitlesEnabled: false, sheetPage: 'main');
    onSubtitlesEnabledChanged(false);
  }

  void enableExternalSubtitles(
    NativeVideoController? videoController,
    ValueChanged<bool> onSubtitlesEnabledChanged,
  ) {
    videoController?.disableSubtitleTrack();
    state = state._copy(subtitlesEnabled: true, sheetPage: 'main');
    onSubtitlesEnabledChanged(true);
  }

  void selectSubtitleTrack(
    NativeVideoController? videoController,
    int groupIndex,
    int trackIndex,
    ValueChanged<bool> onSubtitlesEnabledChanged,
  ) {
    videoController?.selectSubtitleTrack(groupIndex, trackIndex);
    state = state._copy(subtitlesEnabled: true, sheetPage: 'main');
    onSubtitlesEnabledChanged(true);
  }

  void setSubtitleFontSize(double size, ValueChanged<double> onSubtitleFontSizeChanged) {
    state = state._copy(subtitleFontSize: size);
    onSubtitleFontSizeChanged(size);
  }

  void setSubtitleVerticalPosition(double pos, ValueChanged<double> onSubtitleVerticalPositionChanged) {
    state = state._copy(subtitleVerticalPosition: pos);
    onSubtitleVerticalPositionChanged(pos);
  }
}