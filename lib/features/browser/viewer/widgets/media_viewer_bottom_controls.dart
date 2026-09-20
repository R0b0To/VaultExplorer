import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/data/models/media_viewer_action.dart';
import 'package:vaultexplorer/data/models/media_viewer_toolbar_config.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_screen.dart';
import 'package:vaultexplorer/features/browser/viewer/native_video_controller.dart';
import 'package:vaultexplorer/features/browser/viewer/playlist_controller.dart';
import 'package:vaultexplorer/features/browser/viewer/video_playback_manager.dart';
import 'package:vaultexplorer/features/browser/viewer/video_scrub_preview_controller.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/media_player_widget.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/media_viewer_action_button.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/video_scrub_progress_bar.dart';

class MediaViewerBottomControls extends StatelessWidget {
  final PlaylistController playlistController;
  final VideoPlaybackManager playbackManager;
  final ValueNotifier<VideoPlaybackProgress> videoProgressNotifier;
  final VideoScrubPreviewHost scrubPreviewHost;
  final MediaViewerToolbarConfig toolbarConfig;
  final bool isImage;
  final bool isAudio;
  final bool showUI;
  final bool isPlaylistMode;
  final bool autoAdvance;
  final int slideshowDelaySeconds;
  final bool isMuted;
  final VideoPlaybackMode videoPlaybackMode;
  final ValueChanged<MediaViewerAction> onExecuteAction;
  final VoidCallback onStartHideTimer;
  final ValueChanged<bool> onShowUIChanged;
  final bool isCarouselVisible;
  final VoidCallback? onMenuOpened;
  final VoidCallback? onMenuClosed;

  const MediaViewerBottomControls({
    super.key,
    required this.playlistController,
    required this.playbackManager,
    required this.videoProgressNotifier,
    required this.scrubPreviewHost,
    required this.toolbarConfig,
    required this.isImage,
    required this.isAudio,
    required this.showUI,
    required this.isPlaylistMode,
    required this.autoAdvance,
    required this.slideshowDelaySeconds,
    required this.isMuted,
    required this.videoPlaybackMode,
    required this.onExecuteAction,
    required this.onStartHideTimer,
    required this.onShowUIChanged,
    this.isCarouselVisible = false,
    this.onMenuOpened,
    this.onMenuClosed,
  });

  Widget _buildActionItem(
    BuildContext context,
    MediaViewerAction action,
    ColorScheme cs,
  ) {
    if (action == MediaViewerAction.playPause) {
      return _buildHeroPlayPause(context, cs);
    }
    if (action == MediaViewerAction.previous) {
      final bool isFirst = playlistController.currentIndex == 0;
      return IconButton(
        icon: const Icon(Icons.skip_previous_rounded,
            color: Colors.white, size: 26),
        onPressed:
            isFirst ? null : () => onExecuteAction(MediaViewerAction.previous),
      );
    }
    if (action == MediaViewerAction.next) {
      final bool isLast = playlistController.currentIndex ==
          playlistController.playlist.length - 1;
      return IconButton(
        icon:
            const Icon(Icons.skip_next_rounded, color: Colors.white, size: 26),
        onPressed: isLast ? null : () => onExecuteAction(MediaViewerAction.next),
      );
    }

    bool isHighlighted = false;
    Color? highlightColor;
    IconData? customIcon;

    if (action == MediaViewerAction.mute) {
      isHighlighted = isMuted;
      highlightColor = cs.error;
      customIcon = isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded;
    } else if (action == MediaViewerAction.playbackMode) {
      isHighlighted = videoPlaybackMode != VideoPlaybackMode.playOnce;
      switch (videoPlaybackMode) {
        case VideoPlaybackMode.playOnce:
          customIcon = Icons.repeat_rounded;
        case VideoPlaybackMode.playAndAdvance:
          customIcon = Icons.queue_play_next_rounded;
          highlightColor = cs.primary;
        case VideoPlaybackMode.loop:
          customIcon = Icons.repeat_one_rounded;
          highlightColor = cs.primary;
      }
    } else if (action == MediaViewerAction.thumbnailCarousel) {
      isHighlighted = isCarouselVisible;
      highlightColor = cs.primary;
    }

    return MediaViewerActionButton(
      action: action,
      isHighlighted: isHighlighted,
      highlightColor: highlightColor,
      customIcon: customIcon,
      onTap: () => onExecuteAction(action),
      onLongPress: action == MediaViewerAction.advancedSettings
          ? () => onExecuteAction(MediaViewerAction.diagnostics)
          : null,
    );
  }

  Widget _buildHeroPlayPause(BuildContext context, ColorScheme cs) {
    return ValueListenableBuilder<NativeVideoController?>(
      valueListenable: playbackManager.activeControllerNotifier,
      builder: (context, activeCtrl, _) {
        if (isImage || activeCtrl == null) {
          final isPlaying = isImage ? autoAdvance : false;
          return _buildPlayPauseCircle(cs, isPlaying);
        }
        return ValueListenableBuilder<NativeVideoValue>(
          valueListenable: activeCtrl,
          builder: (context, playerValue, _) =>
              _buildPlayPauseCircle(cs, playerValue.isPlaying),
        );
      },
    );
  }

  Widget _buildPlayPauseCircle(ColorScheme cs, bool isPlaying) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: SizedBox(
        width: 48,
        height: 48,
        child: Material(
          color: cs.primary,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              HapticFeedback.mediumImpact();
              onShowUIChanged(true);
              onExecuteAction(MediaViewerAction.playPause);
            },
            child: Center(
              child: Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 28,
                color: cs.onPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    final pinned = toolbarConfig.bottomBarActions.where((a) {
      if (isImage && !toolbarConfig.showCenterTransportForImages) {
        if (a == MediaViewerAction.playPause ||
            a == MediaViewerAction.previous ||
            a == MediaViewerAction.next) {
          return false;
        }
      }
      // When the status chip is active on photos, it already handles delay configuration
      if (isImage &&
          isPlaylistMode &&
          toolbarConfig.showStatusBadge &&
          a == MediaViewerAction.slideshowDelay) {
        return false;
      }
      return a.isApplicable(
        isImage: isImage,
        isAudio: isAudio,
        isPlaylistMode: isPlaylistMode,
      );
    }).toList();

    return Container(
      padding: EdgeInsets.only(
        left: AppSpacing.sm,
        right: AppSpacing.sm,
        bottom: bottomInset + AppSpacing.md,
        top: isCarouselVisible ? AppSpacing.xs : AppSpacing.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isImage && toolbarConfig.showProgressBar) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: VideoScrubProgressBar(
                playbackManager: playbackManager,
                videoProgressNotifier: videoProgressNotifier,
                onShowUIChanged: onShowUIChanged,
                onStartHideTimer: onStartHideTimer,
                previewStyle: toolbarConfig.scrubPreviewStyle,
                previewHost: scrubPreviewHost,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          if (pinned.isNotEmpty || (isImage && toolbarConfig.showStatusBadge))
            _buildTransparentDock(context, cs, pinned),
        ],
      ),
    );
  }

  Widget _buildTransparentDock(
    BuildContext context,
    ColorScheme cs,
    List<MediaViewerAction> pinned,
  ) {
    return Center(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isImage && isPlaylistMode && toolbarConfig.showStatusBadge) ...[
              _SlideshowStatusChip(
                autoAdvance: autoAdvance,
                slideshowDelaySeconds: slideshowDelaySeconds,
                playlistController: playlistController,
                onTap: () => onExecuteAction(MediaViewerAction.slideshowDelay),
              ),
              const SizedBox(width: 6),
            ],
            for (final action in pinned)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: _buildActionItem(context, action, cs),
              ),
          ],
        ),
      ),
    );
  }
}

class _SlideshowStatusChip extends StatefulWidget {
  final bool autoAdvance;
  final int slideshowDelaySeconds;
  final PlaylistController playlistController;
  final VoidCallback onTap;

  const _SlideshowStatusChip({
    required this.autoAdvance,
    required this.slideshowDelaySeconds,
    required this.playlistController,
    required this.onTap,
  });

  @override
  State<_SlideshowStatusChip> createState() => _SlideshowStatusChipState();
}

class _SlideshowStatusChipState extends State<_SlideshowStatusChip>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  String? _lastFile;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(seconds: widget.slideshowDelaySeconds),
    );
    _lastFile = widget.playlistController.currentFile;
    widget.playlistController.addListener(_onPlaylistChanged);
    if (widget.autoAdvance) {
      _controller.forward(from: 0.0);
    }
  }

  @override
  void didUpdateWidget(covariant _SlideshowStatusChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slideshowDelaySeconds != widget.slideshowDelaySeconds) {
      _controller.duration = Duration(seconds: widget.slideshowDelaySeconds);
    }
    if (oldWidget.autoAdvance != widget.autoAdvance) {
      if (widget.autoAdvance) {
        _controller.forward(from: 0.0);
      } else {
        _controller.stop();
        _controller.reset();
      }
    }
  }

  void _onPlaylistChanged() {
    if (_lastFile != widget.playlistController.currentFile) {
      _lastFile = widget.playlistController.currentFile;
      if (widget.autoAdvance && mounted) {
        _controller.forward(from: 0.0);
      }
    }
  }

  @override
  void dispose() {
    widget.playlistController.removeListener(_onPlaylistChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;

    return Material(
      color: Colors.white.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(AppRadius.full),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          widget.onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (widget.autoAdvance)
                      AnimatedBuilder(
                        animation: _controller,
                        builder: (context, _) => CircularProgressIndicator(
                          value: _controller.value,
                          strokeWidth: 1.4,
                          strokeCap: StrokeCap.round,
                          backgroundColor:
                              Colors.white.withValues(alpha: 0.08),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white.withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                    Icon(
                      widget.autoAdvance
                          ? Icons.slideshow_rounded
                          : Icons.image_rounded,
                      color: widget.autoAdvance
                          ? Colors.white.withValues(alpha: 0.85)
                          : Colors.white60,
                      size: 11,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Text(
                widget.autoAdvance
                    ? context.l10n.slideshowDelaySecondsValue(
                        widget.slideshowDelaySeconds)
                    : context.l10n.staticLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}