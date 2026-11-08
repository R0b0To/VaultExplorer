import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/features/browser/viewer/background_playback/background_playback_host.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';
import 'package:vaultexplorer/features/browser/viewer/native_video_controller.dart';
import 'package:vaultexplorer/features/library/controllers/music_hub.dart';
import 'package:vaultexplorer/features/library/widgets/library_cover.dart';
import 'package:vaultexplorer/features/library/widgets/music_covers.dart';
import 'package:vaultexplorer/features/library/widgets/now_playing_info.dart';
import 'package:vaultexplorer/features/library/widgets/now_playing_panel.dart';

/// Playback controls for music that keeps playing after its viewer is closed:
/// what is playing, previous, play or pause, next, stop. Tapping the bar
/// opens the full player.
///
/// It follows [BackgroundPlaybackHost.activeSession], so it appears only while
/// a session (not a viewer) owns audio playback, and disappears the moment the
/// music stops or a viewer takes over. Tapping it or dragging it up opens the
/// music player ([NowPlayingPanel]), which grows out of this bar and follows the
/// finger; dragging it down stops playback, and a sideways swipe skips a track.
/// It shows tags from the library when the file is in it and falls back to the
/// file name.
class MusicMiniPlayer extends StatelessWidget {
  final MusicHub hub;
  final MusicCovers covers;

  const MusicMiniPlayer({super.key, required this.hub, required this.covers});

  @override
  Widget build(BuildContext context) {
    final host = BackgroundPlaybackHost.instance;
    return ValueListenableBuilder<BackgroundPlaybackSession?>(
      valueListenable: host.activeSession,
      builder: (context, session, _) {
        if (session == null) return const SizedBox.shrink();
        final manager = session.playbackManager;
        return ValueListenableBuilder<String?>(
          valueListenable: manager.currentFileNotifier,
          builder: (context, file, _) {
            final path = session.playlist.currentFile.isNotEmpty
                ? session.playlist.currentFile
                : (file ?? '');
            // Video sessions have their own floating window; this is for music.
            if (path.isEmpty || !MediaViewerConstants.isAudio(path)) {
              return const SizedBox.shrink();
            }
            return ValueListenableBuilder<NativeVideoController?>(
              valueListenable: manager.activeControllerNotifier,
              builder: (context, controller, _) => _MiniBar(
                host: host,
                session: session,
                controller: controller,
                path: path,
                hub: hub,
                covers: covers,
              ),
            );
          },
        );
      },
    );
  }
}

class _MiniBar extends StatefulWidget {
  final BackgroundPlaybackHost host;
  final BackgroundPlaybackSession session;
  final NativeVideoController? controller;
  final String path;
  final MusicHub hub;
  final MusicCovers covers;

  const _MiniBar({
    required this.host,
    required this.session,
    required this.controller,
    required this.path,
    required this.hub,
    required this.covers,
  });

  @override
  State<_MiniBar> createState() => _MiniBarState();
}

class _MiniBarState extends State<_MiniBar> {
  final GlobalKey _barKey = GlobalKey();

  double _dragDy = 0;
  NowPlayingHandle? _handle;

  /// The bar's rectangle on screen, which the player grows out of.
  Rect? _measure() {
    final box = _barKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  NowPlayingHandle? _open({required bool expand}) {
    final rect = _measure();
    if (rect == null) return null;
    return NowPlayingPanel.open(
      context,
      hub: widget.hub,
      covers: widget.covers,
      miniRect: rect,
      expand: expand,
    );
  }

  void _onDragStart() {
    _dragDy = 0;
    _handle = null;
  }

  void _onDragUpdate(double dy) {
    _dragDy += dy;
    final handle = _handle;
    if (handle != null) {
      handle.dragBy(dy);
    } else if (_dragDy < -6) {
      // The player opens underneath the finger and takes over the drag.
      final opened = _open(expand: false);
      _handle = opened;
      opened?.dragBy(_dragDy);
    }
  }

  void _onDragEnd(double velocityY) {
    final handle = _handle;
    _handle = null;
    if (handle != null) {
      handle.release(velocityY);
    } else if (_dragDy > 24 || velocityY > 300) {
      widget.host.closeAndWait();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final text = context.typography;
    final l10n = context.l10n;
    final host = widget.host;
    final session = widget.session;
    final controller = widget.controller;
    final info = NowPlayingInfo.resolve(widget.hub, session, widget.path);

    final listenable = Listenable.merge([
      if (controller != null) controller,
      session.playlist,
    ]);

    // The player takes the bar's place while it is open.
    return ValueListenableBuilder<bool>(
      valueListenable: NowPlayingPanel.isOpen,
      builder: (context, open, child) => IgnorePointer(
        ignoring: open,
        child: Opacity(opacity: open ? 0 : 1, child: child),
      ),
      child: Material(
        key: _barKey,
        color: cs.surfaceContainerHigh,
        elevation: 2,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: (_) => _onDragStart(),
          onVerticalDragUpdate: (d) => _onDragUpdate(d.delta.dy),
          onVerticalDragEnd: (d) => _onDragEnd(d.primaryVelocity ?? 0),
          onHorizontalDragEnd: (d) {
            final v = d.primaryVelocity ?? 0;
            if (v < -300 && host.canStepNext) {
              host.stepItem(1);
            } else if (v > 300 && host.canStepPrevious) {
              host.stepItem(-1);
            }
          },
          child: InkWell(
            onTap: () => _open(expand: true),
            child: ListenableBuilder(
              listenable: listenable,
              builder: (context, _) {
                final value = controller?.value;
                final playing = value?.isPlaying ?? false;
                final total = value?.duration.inMilliseconds ?? 0;
                final done = value?.position.inMilliseconds ?? 0;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LinearProgressIndicator(
                      minHeight: 2,
                      value: total > 0 ? (done / total).clamp(0.0, 1.0) : 0,
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        6,
                        AppSpacing.xs,
                        6,
                      ),
                      child: Row(
                        children: [
                          Hero(
                            tag: 'media_hero_${session.container.volId}_${widget.path}',
                            createRectTween: (begin, end) =>
                                MaterialRectArcTween(begin: begin, end: end),
                            child: Material(
                              color: Colors.transparent,
                              child: LibraryCover(
                                covers: widget.covers,
                                track: info.coverTrack,
                                groupKey: info.coverKey,
                                size: 44,
                                borderRadius: 6,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md - 4),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  info.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: text.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (info.artist.isNotEmpty)
                                  Text(
                                    info.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: text.bodySmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          IconButton(
                            tooltip: l10n.musicMiniPrevious,
                            icon: const Icon(Icons.skip_previous_rounded),
                            onPressed: host.canStepPrevious
                                ? () => host.stepItem(-1)
                                : null,
                          ),
                          // Same 48 px slot and 40 px circle the player's
                          // play button starts from when it opens.
                          SizedBox(
                            width: 48,
                            height: 48,
                            child: Center(
                              child: Material(
                                color: cs.primary,
                                shape: const CircleBorder(),
                                clipBehavior: Clip.antiAlias,
                                child: InkWell(
                                  onTap: controller == null
                                      ? null
                                      : () => playing
                                            ? controller.pause()
                                            : controller.play(),
                                  child: SizedBox(
                                    width: 40,
                                    height: 40,
                                    child: Tooltip(
                                      message: playing
                                          ? l10n.musicMiniPause
                                          : l10n.musicMiniPlay,
                                      child: Icon(
                                        playing
                                            ? Icons.pause_rounded
                                            : Icons.play_arrow_rounded,
                                        size: 24,
                                        color: cs.onPrimary,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: l10n.musicMiniNext,
                            icon: const Icon(Icons.skip_next_rounded),
                            onPressed: host.canStepNext
                                ? () => host.stepItem(1)
                                : null,
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
