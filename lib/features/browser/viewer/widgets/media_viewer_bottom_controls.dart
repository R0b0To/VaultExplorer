import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_screen.dart';
import 'package:vaultexplorer/features/browser/viewer/playlist_controller.dart';
import 'package:vaultexplorer/features/browser/viewer/video_playback_manager.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/media_player_widget.dart';

/// A sleek bottom controls overlay for the media viewer built with
/// Android 16/17 (Material 3 Expressive) native design guidelines.
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
            const SizedBox(height: 12),
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

  /// Builds the M3 Expressive video progress bar
  Widget _buildProgressBar(BuildContext context, ColorScheme cs) {
    return SizedBox(
      height: 36,
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          activeTrackColor: cs.primary,
          inactiveTrackColor: Colors.white24,
          trackHeight: 3,
          thumbColor: cs.primary,
          thumbShape: const RoundSliderThumbShape(
            enabledThumbRadius: 7,
          ),
          overlayShape: const RoundSliderOverlayShape(
            overlayRadius: 14,
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
                    fontWeight: FontWeight.bold,
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
                            videoProgressNotifier.value =
                                videoProgressNotifier.value.copyWith(isDragging: false);
                            onStartHideTimer();
                          }).catchError((_) {
                            videoProgressNotifier.value =
                                videoProgressNotifier.value.copyWith(isDragging: false);
                            onStartHideTimer();
                          });
                        } else {
                          videoProgressNotifier.value =
                              videoProgressNotifier.value.copyWith(isDragging: false);
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
                    fontWeight: FontWeight.bold,
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
        if (isPlaylistMode && onToggleCarousel != null) ...[
          Semantics(
            label: 'Toggle thumbnail carousel',
            button: true,
            child: _CircleOverlayButton(
              icon: Icons.view_carousel_rounded,
              iconColor: isCarouselVisible ? cs.primary : Colors.white,
              tooltip: 'Thumbnail Carousel',
              onPressed: () {
                HapticFeedback.lightImpact();
                onToggleCarousel?.call();
              },
            ),
          ),
          const SizedBox(width: 8),
        ],
        Semantics(
          label: 'Advanced settings',
          button: true,
          child: _CircleOverlayButton(
            icon: Icons.tune_rounded,
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
        label: autoAdvance
            ? 'Slideshow mode active with $slideshowDelaySeconds seconds delay'
            : 'Static image mode',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(100),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                autoAdvance ? Icons.slideshow_rounded : Icons.image_rounded,
                color: autoAdvance ? cs.primary : Colors.white70,
                size: 18,
              ),
              const SizedBox(width: 6),
              Text(
                autoAdvance ? '${slideshowDelaySeconds}s' : 'Static',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
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
          modeColor = Colors.white54;
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
            child: _CircleOverlayButton(
              icon: isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              iconColor: isMuted ? cs.error : Colors.white,
              tooltip: isMuted ? 'Unmute' : 'Mute',
              onPressed: onToggleMute,
            ),
          ),
          const SizedBox(width: 8),
          Semantics(
            label: 'Video playback mode: $modeTooltip',
            button: true,
            child: _CircleOverlayButton(
              icon: modeIcon,
              iconColor: modeColor,
              tooltip: modeTooltip,
              onPressed: () {
                HapticFeedback.lightImpact();
                VideoPlaybackMode nextMode;
                if (!isPlaylistMode) {
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
                child: _CircleOverlayButton(
                  icon: Icons.skip_previous_rounded,
                  iconSize: 22,
                  containerSize: 44,
                  tooltip: 'Previous',
                  onPressed: isFirst
                      ? null
                      : () {
                          HapticFeedback.lightImpact();
                          onNavigateToPrev();
                        },
                ),
              ),
              const SizedBox(width: 12),
            ],
            // Hero Play / Pause Pill
            Semantics(
              label: isPlayingState ? 'Pause' : 'Play',
              button: true,
              child: SizedBox(
                width: 56,
                height: 56,
                child: Material(
                  color: cs.primaryContainer,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      onShowUIChanged(true);
                      onTogglePlayPause(isPlayingState);
                    },
                    child: Center(
                      child: Icon(
                        isPlayingState ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        size: 32,
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (isPlaylistMode) ...[
              const SizedBox(width: 12),
              Semantics(
                label: 'Next file',
                button: true,
                child: _CircleOverlayButton(
                  icon: Icons.skip_next_rounded,
                  iconSize: 22,
                  containerSize: 44,
                  tooltip: 'Next',
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

// ── Translucent M3 Media Overlay Button ──────────────────────────────────────

class _CircleOverlayButton extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String tooltip;
  final VoidCallback? onPressed;
  final double iconSize;
  final double containerSize;

  const _CircleOverlayButton({
    required this.icon,
    this.iconColor,
    required this.tooltip,
    this.onPressed,
    this.iconSize = 20,
    this.containerSize = 40,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;

    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: containerSize,
        height: containerSize,
        child: Material(
          color: enabled
              ? Colors.white.withValues(alpha: 0.14)
              : Colors.white.withValues(alpha: 0.05),
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: Center(
              child: Icon(
                icon,
                size: iconSize,
                color: iconColor ?? (enabled ? Colors.white : Colors.white30),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
