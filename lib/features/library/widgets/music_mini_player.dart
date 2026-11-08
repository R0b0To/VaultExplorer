import 'dart:async' show unawaited;
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/widgets/full_screen_drag_drawer.dart';
import 'package:vaultexplorer/features/browser/viewer/background_playback/background_playback_host.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';
import 'package:vaultexplorer/features/browser/viewer/native_video_controller.dart';
import 'package:vaultexplorer/features/library/controllers/music_hub.dart';
import 'package:vaultexplorer/features/library/widgets/library_cover.dart';
import 'package:vaultexplorer/features/library/widgets/music_covers.dart';
import 'package:vaultexplorer/features/library/widgets/now_playing_info.dart';
import 'package:vaultexplorer/features/library/widgets/now_playing_panel.dart';
import 'package:vaultexplorer/features/library/widgets/smooth_playback_position.dart';

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

class _MiniBarState extends State<_MiniBar> with TickerProviderStateMixin {
  /// How far down (in pixels) a drag has to go for the bar to be fully
  /// squished, which is also where letting go closes it.
  static const double _squishExtent = 72;

  final GlobalKey _barKey = GlobalKey();

  /// 0 normal, 1 fully squished. Follows a downward drag so the bar shows it
  /// is about to close, and springs back when the drag is given up.
  late final AnimationController _squish = AnimationController(
    vsync: this,
    lowerBound: 0,
    upperBound: 1,
    value: 0,
  );

  /// Played fraction for the progress line, glided between the player's
  /// position reports.
  final ValueNotifier<double> _progress = ValueNotifier<double>(0);
  late final SmoothPlaybackPosition _smooth = SmoothPlaybackPosition(
    vsync: this,
    onFrame: _onFrame,
  );
  NativeVideoController? _bound;

  double _dragDy = 0;
  NowPlayingHandle? _handle;
  double _trackSlide = 1;
  bool _pendingTrackSlide = false;

  @override
  void initState() {
    super.initState();
    _bind(widget.controller);
  }

  @override
  void didUpdateWidget(_MiniBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      if (!_pendingTrackSlide) _trackSlide = 1;
      _pendingTrackSlide = false;
    }
    if (!identical(oldWidget.controller, widget.controller)) {
      _bind(widget.controller);
    }
  }

  @override
  void dispose() {
    _unbind();
    _smooth.dispose();
    _squish.dispose();
    _progress.dispose();
    super.dispose();
  }

  void _bind(NativeVideoController? controller) {
    _unbind();
    _bound = controller;
    controller?.addListener(_onTick);
    _onTick();
  }

  void _unbind() {
    final controller = _bound;
    _bound = null;
    if (controller == null) return;
    try {
      controller.removeListener(_onTick);
    } catch (_) {
      // Disposed along with the player.
    }
  }

  void _onTick() {
    final controller = _bound;
    if (controller == null || controller.isDisposed) return;
    _smooth.report(controller.value, speed: widget.session.playbackSpeed);
  }

  void _onFrame(Duration position, Duration duration) {
    final total = duration.inMilliseconds;
    _progress.value = total > 0
        ? (position.inMilliseconds / total).clamp(0.0, 1.0)
        : 0.0;
  }

  void _stepTrack(int direction) {
    final currentPath = widget.session.playlist.currentFile;
    _trackSlide = direction > 0 ? 1 : -1;
    _pendingTrackSlide = true;
    unawaited(
      widget.host.stepItem(direction).then((_) {
        if (mounted && widget.session.playlist.currentFile == currentPath) {
          _pendingTrackSlide = false;
        }
      }),
    );
  }

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
    _squish.stop();
  }

  void _onDragUpdate(double dy) {
    _dragDy += dy;
    final handle = _handle;
    if (handle != null) {
      handle.dragBy(dy);
    } else if (_dragDy < -6) {
      // The player opens underneath the finger and takes over the drag.
      if (_squish.value != 0) _squish.value = 0;
      final opened = _open(expand: false);
      _handle = opened;
      opened?.dragBy(_dragDy);
    } else {
      // Going down: squish the bar in step with the finger.
      _squish.value = (_dragDy / _squishExtent).clamp(0.0, 1.0);
    }
  }

  void _onDragEnd(double velocityY) {
    final handle = _handle;
    _handle = null;
    if (handle != null) {
      handle.release(velocityY);
      return;
    }
    final closes = _squish.value >= 0.35 || velocityY > 350;
    if (closes && _dragDy > 0) {
      _squish
          .animateTo(
            1,
            duration: const Duration(milliseconds: 110),
            curve: Curves.easeIn,
          )
          .then((_) {
            if (mounted) widget.host.closeAndWait();
          });
    } else {
      _squish.animateTo(
        0,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutBack,
      );
    }
  }

  void _onDragCancel() {
    final handle = _handle;
    _handle = null;
    if (handle != null) {
      handle.release(0);
    } else {
      _squish.animateTo(
        0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final text = context.typography;
    final l10n = context.l10n;
    final host = widget.host;
    final session = widget.session;
    final info = NowPlayingInfo.resolve(widget.hub, session, widget.path);
    final drawerScope = FullScreenDragDrawerScope.maybeOf(context);

    final bar = Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => drawerScope?.setDrawerDragBlocked(true),
      onPointerUp: (_) => drawerScope?.setDrawerDragBlocked(false),
      onPointerCancel: (_) => drawerScope?.setDrawerDragBlocked(false),
      child: Material(
        key: _barKey,
        color: cs.surfaceContainerHigh,
        elevation: 2,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: (_) => _onDragStart(),
          onVerticalDragUpdate: (d) => _onDragUpdate(d.delta.dy),
          onVerticalDragEnd: (d) => _onDragEnd(d.primaryVelocity ?? 0),
          onVerticalDragCancel: _onDragCancel,
          onHorizontalDragEnd: (d) {
            final v = d.primaryVelocity ?? 0;
            if (v < -300 && host.canStepNext) {
              _stepTrack(1);
            } else if (v > 300 && host.canStepPrevious) {
              _stepTrack(-1);
            }
          },
          child: InkWell(
            onTap: () => _open(expand: true),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ValueListenableBuilder<double>(
                  valueListenable: _progress,
                  builder: (context, value, _) =>
                      LinearProgressIndicator(minHeight: 2, value: value),
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
                        tag:
                            'media_hero_${session.container.volId}_${widget.path}',
                        createRectTween: (begin, end) =>
                            MaterialRectArcTween(begin: begin, end: end),
                        child: Material(
                          color: Colors.transparent,
                          child: SizedBox(
                            width: 44,
                            height: 44,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 240),
                                switchInCurve: Curves.easeOutCubic,
                                switchOutCurve: Curves.easeInCubic,
                                transitionBuilder: (child, animation) =>
                                    FadeTransition(
                                      opacity: animation,
                                      child: SlideTransition(
                                        position: Tween<Offset>(
                                          begin: Offset(_trackSlide * 0.2, 0),
                                          end: Offset.zero,
                                        ).animate(animation),
                                        child: child,
                                      ),
                                    ),
                                child: LibraryCover(
                                  key: ValueKey<String>(widget.path),
                                  covers: widget.covers,
                                  track: info.coverTrack,
                                  groupKey: info.coverKey,
                                  size: 44,
                                  borderRadius: 6,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md - 4),
                      Expanded(
                        child: SizedBox(
                          height: 44,
                          child: ClipRect(
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 240),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              layoutBuilder: (currentChild, previousChildren) =>
                                  Stack(
                                    alignment: Alignment.centerLeft,
                                    children: [
                                      ...previousChildren,
                                      if (currentChild != null) currentChild,
                                    ],
                                  ),
                              transitionBuilder: (child, animation) =>
                                  FadeTransition(
                                    opacity: animation,
                                    child: SlideTransition(
                                      position: Tween<Offset>(
                                        begin: Offset(_trackSlide * 0.18, 0),
                                        end: Offset.zero,
                                      ).animate(animation),
                                      child: child,
                                    ),
                                  ),
                              child: Column(
                                key: ValueKey<String>(widget.path),
                                mainAxisAlignment: MainAxisAlignment.center,
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
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      ListenableBuilder(
                        listenable: Listenable.merge([
                          session.playlist,
                          host.repeat,
                        ]),
                        builder: (context, _) => Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: l10n.musicMiniPrevious,
                              icon: const Icon(Icons.skip_previous_rounded),
                              onPressed: host.canStepPrevious
                                  ? () => _stepTrack(-1)
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
                                    onTap: () => host.togglePlayback(),
                                    child: SizedBox(
                                      width: 40,
                                      height: 40,
                                      child: ValueListenableBuilder<bool>(
                                        valueListenable: host.playing,
                                        builder: (context, playing, _) =>
                                            Tooltip(
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
                            ),
                            IconButton(
                              tooltip: l10n.musicMiniNext,
                              icon: const Icon(Icons.skip_next_rounded),
                              onPressed: host.canStepNext
                                  ? () => _stepTrack(1)
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // The player takes the bar's place while it is open; a downward drag
    // squishes the bar towards the strip below it to say "this closes".
    return ValueListenableBuilder<bool>(
      valueListenable: NowPlayingPanel.isOpen,
      builder: (context, open, child) => IgnorePointer(
        ignoring: open,
        child: Opacity(opacity: open ? 0 : 1, child: child),
      ),
      child: AnimatedBuilder(
        animation: _squish,
        child: bar,
        builder: (context, child) {
          // Always wrapped, even at 0: moving the bar between parents in the
          // middle of a drag would be needless risk for the gesture.
          final squish = _squish.value;
          return Opacity(
            opacity: 1 - 0.5 * squish,
            child: Transform(
              alignment: Alignment.bottomCenter,
              transform: Matrix4.diagonal3Values(
                1 + 0.04 * squish,
                1 - 0.55 * squish,
                1,
              ),
              child: child,
            ),
          );
        },
      ),
    );
  }
}
