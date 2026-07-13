import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../media_viewer_constants.dart';
import '../media_viewer_screen.dart'; // Imports VideoPlaybackMode enum
import '../playlist_controller.dart';
import '../video_playback_manager.dart';
import 'media_player_widget.dart'; // Imports VideoPlaybackProgress class

/// A sleek bottom controls overlay for the media viewer.
/// Handles playback progress, transport controls (play, pause, next, prev),
/// and advanced setting options with performance optimizations and semantic accessibility.
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
    super.key,
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
  });

  /// Formats the given duration safely to a string representation (e.g., 'hh:mm:ss' or 'mm:ss').
  /// Handles edge cases such as negative or overflow durations gracefully.
  String _formatDuration(Duration d) {
    final Duration absoluteDuration = d.isNegative ? -d : d;
    final String minutes = absoluteDuration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final String seconds = absoluteDuration.inSeconds.remainder(60).toString().padLeft(2, '0');
    final String sign = d.isNegative ? '-' : '';

    if (absoluteDuration.inHours > 0) {
      final String hours = absoluteDuration.inHours.toString().padLeft(2, '0');
      return '$sign$hours:$minutes:$seconds';
    }
    return '$sign$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    
    // Performance Optimization: Use MediaQuery.paddingOf(context) instead of MediaQuery.of(context).
    // This avoids rebuilding this entire widget if other unrelated properties of MediaQuery change (such as keyboard, textScaleFactor).
    final bottomPadding = MediaQuery.paddingOf(context).bottom;

    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: bottomPadding + 16,
        top: 32,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.9),
            Colors.black.withValues(alpha: 0.5),
            Colors.transparent,
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isImage) ...[
            _buildProgressBar(context, cs),
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

  /// Builds the progress bar and timer indicators with performance optimization.
  /// The [SliderTheme] decoration is placed OUTSIDE of [ValueListenableBuilder]
  /// to avoid recreating the decoration objects on every playback tick.
  Widget _buildProgressBar(BuildContext context, ColorScheme cs) {
    return SizedBox(
      height: 36,
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
                  child: Semantics(
                    label: 'Video playback position slider',
                    value: '${(progress.sliderValue * 100).toStringAsFixed(0)}%',
                    child: Slider(
                      value: progress.sliderValue.clamp(0.0, 1.0),
                      onChanged: (value) {
                        onShowUIChanged(true);
                        videoProgressNotifier.value = progress.copyWith(
                          isDragging: true,
                          sliderValue: value,
                        );
                        final controller = playbackManager.activeController;
                        // Error handling: Check if controller is initialized and has a valid duration
                        if (controller != null && controller.value.isInitialized) {
                          final durationMs = progress.duration.inMilliseconds;
                          if (durationMs > 0) {
                            final targetMs = (value * durationMs).toInt().clamp(0, durationMs);
                            controller.seekTo(Duration(milliseconds: targetMs));
                          }
                        }
                      },
                      onChangeEnd: (value) {
                        final controller = playbackManager.activeController;
                        if (controller != null && controller.value.isInitialized) {
                          final durationMs = progress.duration.inMilliseconds;
                          final targetMs = durationMs > 0
                              ? (value * durationMs).toInt().clamp(0, durationMs)
                              : 0;
                          
                          controller.seekTo(Duration(milliseconds: targetMs)).then((_) {
                            videoProgressNotifier.value = videoProgressNotifier.value.copyWith(isDragging: false);
                            onStartHideTimer();
                          }).catchError((_) {
                            // Recover gracefully if seeking fails
                            videoProgressNotifier.value = videoProgressNotifier.value.copyWith(isDragging: false);
                            onStartHideTimer();
                          });
                        } else {
                          // Safe fallback
                          videoProgressNotifier.value = videoProgressNotifier.value.copyWith(isDragging: false);
                          onStartHideTimer();
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
    );
  }

  Widget _buildRightControls(ColorScheme cs) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isPlaylistMode && onToggleCarousel != null)
          Semantics(
            label: 'Toggle thumbnail carousel',
            button: true,
            child: IconButton(
              iconSize: 22,
              icon: Icon(
                Icons.view_carousel_rounded,
                color: isCarouselVisible ? cs.primary : Colors.white,
              ),
              tooltip: 'Thumbnail Carousel',
              onPressed: () {
                HapticFeedback.lightImpact();
                onToggleCarousel?.call();
              },
            ),
          ),
        Semantics(
          label: 'Advanced settings',
          button: true,
          child: IconButton(
            iconSize: 24,
            icon: const Icon(Icons.tune_rounded, color: Colors.white),
            tooltip: 'Advanced Settings',
            onPressed: () {
              HapticFeedback.lightImpact();
              onAdvancedSettingsPressed();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLeftControls(ColorScheme cs) {
    if (isImage) {
      if (!isPlaylistMode) return const SizedBox.shrink();
      return Semantics(
        label: autoAdvance ? 'Slideshow mode active with $slideshowDelaySeconds seconds delay' : 'Static image mode',
        child: Row(
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
        ),
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
          Semantics(
            label: isMuted ? 'Unmute volume' : 'Mute volume',
            button: true,
            child: IconButton(
              iconSize: 24,
              icon: Icon(
                isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                color: isMuted ? cs.error : Colors.white,
              ),
              tooltip: isMuted ? 'Unmute' : 'Mute',
              onPressed: onToggleMute,
            ),
          ),
          Semantics(
            label: 'Video playback mode: $modeTooltip',
            button: true,
            child: IconButton(
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
              Semantics(
                label: 'Previous file',
                button: true,
                child: IconButton(
                  iconSize: 32,
                  icon: Icon(
                    Icons.skip_previous_rounded,
                    color: isFirst ? Colors.white30 : Colors.white,
                  ),
                  onPressed: isFirst
                      ? null
                      : () {
                          HapticFeedback.lightImpact();
                          onNavigateToPrev();
                        },
                ),
              ),
              const SizedBox(width: 8),
            ],
            Semantics(
              label: isPlayingState ? 'Pause' : 'Play',
              button: true,
              child: IconButton(
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
            ),
            if (isPlaylistMode) ...[
              const SizedBox(width: 8),
              Semantics(
                label: 'Next file',
                button: true,
                child: IconButton(
                  iconSize: 32,
                  icon: Icon(
                    Icons.skip_next_rounded,
                    color: isLast ? Colors.white30 : Colors.white,
                  ),
                  onPressed: isLast
                      ? null
                      : () {
                          HapticFeedback.lightImpact();
                          onNavigateToNext();
                        },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
