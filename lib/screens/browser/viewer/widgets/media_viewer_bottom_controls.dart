import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../media_viewer_constants.dart';
import '../media_viewer_screen.dart'; // Imports VideoPlaybackMode enum
import '../playlist_controller.dart';
import '../video_playback_manager.dart';
import 'media_player_widget.dart'; // Imports VideoPlaybackProgress class

class MediaViewerBottomControls extends StatelessWidget {
  final PlaylistController playlistController;
  final VideoPlaybackManager playbackManager;
  final ValueNotifier<VideoPlaybackProgress> videoProgressNotifier;
  final bool isImage;
  final bool showUI;
  final bool isPlaylistMode;
  final bool autoAdvance;
  final int slideshowDelaySeconds;
  final bool isMuted;
  final VideoPlaybackMode videoPlaybackMode;
  final VoidCallback onNavigateToPrev;
  final VoidCallback onNavigateToNext;
  final ValueChanged<bool> onTogglePlayPause;
  final ValueChanged<VideoPlaybackMode> onPlaybackModeChanged;
  final VoidCallback onToggleMute;
  final VoidCallback onAdvancedSettingsPressed;
  final VoidCallback onStartHideTimer;
  final ValueChanged<bool> onShowUIChanged;
  final bool isCarouselVisible;
  final VoidCallback? onToggleCarousel;

  const MediaViewerBottomControls({
    Key? key,
    required this.playlistController,
    required this.playbackManager,
    required this.videoProgressNotifier,
    required this.isImage,
    required this.showUI,
    required this.isPlaylistMode,
    required this.autoAdvance,
    required this.slideshowDelaySeconds,
    required this.isMuted,
    required this.videoPlaybackMode,
    required this.onNavigateToPrev,
    required this.onNavigateToNext,
    required this.onTogglePlayPause,
    required this.onPlaybackModeChanged,
    required this.onToggleMute,
    required this.onAdvancedSettingsPressed,
    required this.onStartHideTimer,
    required this.onShowUIChanged,
    this.isCarouselVisible = false,
    this.onToggleCarousel,
  }) : super(key: key);

  String _formatDuration(Duration d) {
    final String minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final String seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');

    if (d.inHours > 0) {
      final String hours = d.inHours.toString().padLeft(2, '0');
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).padding.bottom + 16,
        top: 32,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withOpacity(0.9),
            Colors.black.withOpacity(0.5),
            Colors.transparent,
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isImage) ...[
            SizedBox(
              height: 36,
              child: ValueListenableBuilder<VideoPlaybackProgress>(
                valueListenable: videoProgressNotifier,
                builder: (context, progress, child) {
                  final positionStr = _formatDuration(progress.position);
                  final durationStr = _formatDuration(progress.duration);
                  return Row(
                    children: [
                      Text(
                        positionStr,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: cs.primary,
                            inactiveTrackColor: Colors.white24,
                            trackHeight: 2,
                            thumbColor: cs.primary,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 6,
                            ),
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 12,
                            ),
                            trackShape: const RectangularSliderTrackShape(),
                          ),
                          child: Slider(
                            value: progress.sliderValue.clamp(0.0, 1.0),
                            onChanged: (value) {
                              onShowUIChanged(true);
                              videoProgressNotifier.value = progress.copyWith(
                                isDragging: true,
                                sliderValue: value,
                              );
                              final controller = playbackManager.activeController;
                              if (controller != null) {
                                final targetMs = (value * progress.duration.inMilliseconds).toInt();
                                controller.seekTo(Duration(milliseconds: targetMs));
                              }
                            },
                            onChangeEnd: (value) {
                              final controller = playbackManager.activeController;
                              if (controller != null) {
                                final targetMs = (value * progress.duration.inMilliseconds).toInt();
                                controller.seekTo(Duration(milliseconds: targetMs)).then((_) {
                                  videoProgressNotifier.value = videoProgressNotifier.value.copyWith(isDragging: false);
                                  onStartHideTimer();
                                });
                              }
                            },
                          ),
                        ),
                      ),
                      Text(
                        durationStr,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                flex: 1,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _buildLeftControls(cs),
                ),
              ),
              _buildBottomTransportControls(cs),
              Flexible(
                flex: 1,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _buildRightControls(cs),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRightControls(ColorScheme cs) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isPlaylistMode && onToggleCarousel != null)
          IconButton(
            iconSize: 22,
            icon: Icon(
              Icons.view_carousel_rounded,
              color: isCarouselVisible ? cs.primary : Colors.white,
            ),
            tooltip: 'Thumbnail Carousel',
            onPressed: onToggleCarousel,
          ),
        IconButton(
          iconSize: 24,
          icon: const Icon(Icons.tune_rounded, color: Colors.white),
          tooltip: 'Advanced Settings',
          onPressed: onAdvancedSettingsPressed,
        ),
      ],
    );
  }

  Widget _buildLeftControls(ColorScheme cs) {
    if (isImage) {
      if (!isPlaylistMode) return const SizedBox.shrink();
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            autoAdvance ? Icons.slideshow_rounded : Icons.image_rounded,
            color: autoAdvance ? cs.primary : Colors.white70,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            autoAdvance ? '${slideshowDelaySeconds}s delay' : 'Static',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      );
    } else {
      IconData modeIcon;
      String modeTooltip;
      Color modeColor;

      switch (videoPlaybackMode) {
        case VideoPlaybackMode.playOnce:
          modeIcon = Icons.repeat_rounded;
          modeTooltip = 'Play Once (Auto-Advance Disabled)';
          modeColor = const Color.fromARGB(66, 255, 255, 255);
          break;
        case VideoPlaybackMode.playAndAdvance:
          modeIcon = Icons.queue_play_next_rounded;
          modeTooltip = 'Play & Advance to Next';
          modeColor = cs.primary;
          break;
        case VideoPlaybackMode.loop:
          modeIcon = Icons.repeat_rounded;
          modeTooltip = 'Loop Current Video';
          modeColor = cs.primary;
          break;
      }

      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            iconSize: 24,
            icon: Icon(
              isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              color: isMuted ? cs.error : Colors.white,
            ),
            tooltip: 'Mute',
            onPressed: onToggleMute,
          ),
          IconButton(
            iconSize: 24,
            icon: Icon(
              modeIcon,
              color: modeColor,
            ),
            tooltip: modeTooltip,
            onPressed: () {
              HapticFeedback.lightImpact();
              VideoPlaybackMode nextMode;
              if (!isPlaylistMode) {
                // Nothing to advance to outside a playlist, so just toggle looping.
                nextMode = videoPlaybackMode == VideoPlaybackMode.loop
                    ? VideoPlaybackMode.playOnce
                    : VideoPlaybackMode.loop;
              } else {
                switch (videoPlaybackMode) {
                  case VideoPlaybackMode.playOnce:
                    nextMode = VideoPlaybackMode.loop;
                    break;
                  case VideoPlaybackMode.loop:
                    nextMode = VideoPlaybackMode.playAndAdvance;
                    break;
                  case VideoPlaybackMode.playAndAdvance:
                    nextMode = VideoPlaybackMode.playOnce;
                    break;
                }
              }
              onPlaybackModeChanged(nextMode);
            },
          ),
        ],
      );
    }
  }

  Widget _buildBottomTransportControls(ColorScheme cs) {
    // A single static image has no play/pause or navigation to offer.
    if (isImage && !isPlaylistMode) return const SizedBox.shrink();

    final bool isFirst = playlistController.currentIndex == 0;
    final bool isLast =
        playlistController.currentIndex == playlistController.playlist.length - 1;
    bool isPlayingState = autoAdvance;

    if (!isImage) {
      isPlayingState = playbackManager.activeController?.value.isPlaying ?? false;
    }

    return IgnorePointer(
      ignoring: !showUI,
      child: AnimatedOpacity(
        duration: MediaViewerConstants.animationDuration,
        curve: Curves.easeInOut,
        opacity: showUI ? 1.0 : 0.0,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isPlaylistMode) ...[
              IconButton(
                iconSize: 32,
                icon: Icon(
                  Icons.skip_previous_rounded,
                  color: isFirst ? Colors.white30 : Colors.white,
                ),
                onPressed: isFirst ? null : onNavigateToPrev,
              ),
              const SizedBox(width: 8),
            ],
            IconButton(
              iconSize: 48,
              icon: Icon(
                isPlayingState ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
                color: Colors.white,
              ),
              onPressed: () {
                HapticFeedback.mediumImpact();
                onShowUIChanged(true);
                onTogglePlayPause(isPlayingState);
              },
            ),
            if (isPlaylistMode) ...[
              const SizedBox(width: 8),
              IconButton(
                iconSize: 32,
                icon: Icon(
                  Icons.skip_next_rounded,
                  color: isLast ? Colors.white30 : Colors.white,
                ),
                onPressed: isLast ? null : onNavigateToNext,
              ),
            ],
          ],
        ),
      ),
    );
  }
}