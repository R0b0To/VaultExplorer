import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

enum MediaViewerAction {
  playPause,
  previous,
  next,
  playbackSpeed,
  rotate90,
  screenOrientation,
  mute,
  playbackMode,
  thumbnailCarousel,
  subtitles,
  audioTrack,
  imageFit,
  aspectRatio,
  slideshowDelay,
  bookmark,
  fileInfo,
  openWithApp,
  editImage,
  rename,
  delete,
  playlistMenu,
  advancedSettings,
  diagnostics;

  IconData get icon => switch (this) {
        MediaViewerAction.playPause => Icons.play_arrow_rounded,
        MediaViewerAction.previous => Icons.skip_previous_rounded,
        MediaViewerAction.next => Icons.skip_next_rounded,
        MediaViewerAction.playbackSpeed => Icons.slow_motion_video_rounded,
        MediaViewerAction.rotate90 => Icons.rotate_right_rounded,
        MediaViewerAction.screenOrientation => Icons.screen_rotation_rounded,
        MediaViewerAction.mute => Icons.volume_up_rounded,
        MediaViewerAction.playbackMode => Icons.repeat_rounded,
        MediaViewerAction.thumbnailCarousel => Icons.view_carousel_rounded,
        MediaViewerAction.subtitles => Icons.subtitles_rounded,
        MediaViewerAction.audioTrack => Icons.audiotrack_rounded,
        MediaViewerAction.imageFit => Icons.aspect_ratio_rounded,
        MediaViewerAction.aspectRatio => Icons.aspect_ratio_rounded,
        MediaViewerAction.slideshowDelay => Icons.timer_outlined,
        MediaViewerAction.bookmark => Icons.star_rounded,
        MediaViewerAction.fileInfo => Icons.info_outline_rounded,
        MediaViewerAction.openWithApp => Icons.open_in_new_rounded,
        MediaViewerAction.editImage => Icons.edit_outlined,
        MediaViewerAction.rename => Icons.drive_file_rename_outline_rounded,
        MediaViewerAction.delete => Icons.delete_outline_rounded,
        MediaViewerAction.playlistMenu => Icons.playlist_play_rounded,
        MediaViewerAction.advancedSettings => Icons.tune_rounded,
        MediaViewerAction.diagnostics => Icons.analytics_outlined,
      };

  String getLocalizedLabel(AppLocalizations l10n) => switch (this) {
        MediaViewerAction.playPause => l10n.mediaViewerActionPlayPause,
        MediaViewerAction.previous => l10n.previousTooltip,
        MediaViewerAction.next => l10n.nextTooltip,
        MediaViewerAction.playbackSpeed => l10n.playbackSpeedLabel,
        MediaViewerAction.rotate90 => l10n.rotate90Label,
        MediaViewerAction.screenOrientation => l10n.screenOrientationMenu,
        MediaViewerAction.mute => l10n.muteTooltip,
        MediaViewerAction.playbackMode => l10n.mediaViewerActionPlaybackMode,
        MediaViewerAction.thumbnailCarousel => l10n.thumbnailCarouselTooltip,
        MediaViewerAction.subtitles => l10n.subtitlesLabel,
        MediaViewerAction.audioTrack => l10n.audioTrackTitle,
        MediaViewerAction.imageFit => l10n.imageFitModeLabel,
        MediaViewerAction.aspectRatio => l10n.aspectRatioModeLabel,
        MediaViewerAction.slideshowDelay => l10n.slideshowDelayLabel,
        MediaViewerAction.bookmark => l10n.mediaViewerActionBookmark,
        MediaViewerAction.fileInfo => l10n.fileInfoAction,
        MediaViewerAction.openWithApp => l10n.openWithAppAction,
        MediaViewerAction.editImage => l10n.editImageAction,
        MediaViewerAction.rename => l10n.renameFileMenu,
        MediaViewerAction.delete => l10n.deleteFileMenu,
        MediaViewerAction.playlistMenu => l10n.playlistOptionsTooltip,
        MediaViewerAction.advancedSettings => l10n.advancedSettingsTooltip,
        MediaViewerAction.diagnostics => l10n.mediaViewerActionDiagnostics,
      };

  bool isApplicable({required bool isImage, required bool isAudio, required bool isPlaylistMode}) {
    if (isImage) {
      if (this == MediaViewerAction.mute ||
          this == MediaViewerAction.playbackSpeed ||
          this == MediaViewerAction.subtitles ||
          this == MediaViewerAction.audioTrack ||
          this == MediaViewerAction.aspectRatio ||
          this == MediaViewerAction.diagnostics) {
        return false;
      }
      if (!isPlaylistMode &&
          (this == MediaViewerAction.slideshowDelay ||
              this == MediaViewerAction.previous ||
              this == MediaViewerAction.next)) {
        return false;
      }
      return true;
    }

    if (this == MediaViewerAction.editImage ||
        this == MediaViewerAction.imageFit ||
        this == MediaViewerAction.slideshowDelay) {
      return false;
    }
    if (isAudio &&
        (this == MediaViewerAction.subtitles ||
            this == MediaViewerAction.rotate90 ||
            this == MediaViewerAction.screenOrientation ||
            this == MediaViewerAction.aspectRatio)) {
      return false;
    }
    if (!isPlaylistMode &&
        (this == MediaViewerAction.previous ||
            this == MediaViewerAction.next)) {
      return false;
    }
    return true;
  }

  String toJson() => name;

  static MediaViewerAction? fromJson(String? value) {
    if (value == null) return null;
    for (final action in MediaViewerAction.values) {
      if (action.name == value) return action;
    }
    return null;
  }
}