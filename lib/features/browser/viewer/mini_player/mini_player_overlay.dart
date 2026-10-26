import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:vaultexplorer/app/app_navigator_key.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_screen.dart';
import 'package:vaultexplorer/features/browser/viewer/mini_player/mini_player_host.dart';
import 'package:vaultexplorer/features/browser/viewer/native_video_controller.dart';

/// Floats the mini player above every page of the app (put it in
/// `MaterialApp.builder`, inside the skin editor host).
///
/// While [MiniPlayerHost] has no session, or a media viewer is open (it has
/// its own controls), this adds nothing but a pass-through around [child].
class MiniPlayerLayer extends StatelessWidget {
  final Widget child;

  const MiniPlayerLayer({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final host = MiniPlayerHost.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([host.sessionNotifier, host.viewerOpen]),
      builder: (context, _) {
        final session = host.sessionNotifier.value;
        return Stack(
          children: [
            Positioned.fill(child: child),
            if (session != null && !host.viewerOpen.value)
              Positioned.fill(
                // Tooltips and ink need an Overlay, which the app's Navigator
                // (normally the provider) is below this.
                child: Overlay.wrap(
                  child: _MiniPlayerPanel(
                    key: ValueKey<MiniPlayerSession>(session),
                    session: session,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Reopens the full media viewer on the item the mini player is playing,
/// handing the live player back to it.
void expandMiniPlayer() {
  final host = MiniPlayerHost.instance;
  final navigator = appNavigatorKey.currentState;
  if (navigator == null) return;
  final session = host.take();
  if (session == null) return;
  navigator.push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.transparent,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, animation, secondaryAnimation) =>
          MediaViewerScreen(
            container: session.container,
            mediaFiles: List<String>.of(session.playlist.playlist),
            initialIndex: session.playlist.currentIndex,
            startingFolder: session.startingFolder,
            thumbnailQuality: session.thumbnailQuality,
            thumbnailCacheMode: session.thumbnailCacheMode,
            mediaFilter: session.mediaFilter,
            sortBy: session.sortBy,
            sortAscending: session.sortAscending,
            pinnedPaths: session.pinnedPaths,
            resumeSession: session,
          ),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          ),
          child: child,
        );
      },
    ),
  );
}

class _MiniPlayerPanel extends StatefulWidget {
  final MiniPlayerSession session;

  const _MiniPlayerPanel({super.key, required this.session});

  @override
  State<_MiniPlayerPanel> createState() => _MiniPlayerPanelState();
}

class _MiniPlayerPanelState extends State<_MiniPlayerPanel> {
  static const double _margin = 8;
  static const double _audioHeight = 64;
  static const double _videoLandscapeWidth = 220;
  static const double _videoPortraitWidth = 140;
  static const double _videoMaxHeight = 300;

  // Where the person last dragged each kind of window to; in memory only.
  static Offset? _lastVideoOffset;
  static Offset? _lastAudioOffset;

  late final Listenable _managerListenable = Listenable.merge([
    widget.session.playbackManager.activeControllerNotifier,
    widget.session.playbackManager.currentFileNotifier,
  ]);

  Offset? _offset;
  bool _isVideoLayout = false;
  bool _controlsVisible = false;
  Timer? _hideTimer;

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _showControls() {
    _hideTimer?.cancel();
    setState(() => _controlsVisible = true);
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _toggleControls() {
    if (_controlsVisible) {
      _hideTimer?.cancel();
      setState(() => _controlsVisible = false);
    } else {
      _showControls();
    }
  }

  Offset _clamp(Offset offset, Size panel, Size screen, EdgeInsets safe) {
    final minX = safe.left + _margin;
    final maxX = math.max(minX, screen.width - safe.right - panel.width - _margin);
    final minY = safe.top + _margin;
    final maxY = math.max(
      minY,
      screen.height - safe.bottom - panel.height - _margin,
    );
    return Offset(
      offset.dx.clamp(minX, maxX).toDouble(),
      offset.dy.clamp(minY, maxY).toDouble(),
    );
  }

  Offset _defaultOffset(Size panel, Size screen, EdgeInsets safe, bool video) {
    final x = video
        ? screen.width - safe.right - panel.width - _margin
        : (screen.width - panel.width) / 2;
    final y = screen.height - safe.bottom - panel.height - (video ? 72 : _margin);
    return Offset(x, y);
  }

  void _onDrag(DragUpdateDetails details, Size panel, Size screen, EdgeInsets safe) {
    final current = _offset ?? _defaultOffset(panel, screen, safe, _isVideoLayout);
    setState(() {
      _offset = _clamp(current + details.delta, panel, screen, safe);
      if (_isVideoLayout) {
        _lastVideoOffset = _offset;
      } else {
        _lastAudioOffset = _offset;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final host = MiniPlayerHost.instance;
    final session = widget.session;
    final screen = MediaQuery.sizeOf(context);
    final safe = MediaQuery.paddingOf(context);

    return ListenableBuilder(
      listenable: _managerListenable,
      builder: (context, _) {
        final controller = session.playbackManager.activeController;
        final file = session.playbackManager.currentFileName;
        if (controller == null || file == null) return const SizedBox.shrink();
        final isVideo = MediaViewerConstants.isVideo(file);
        return ValueListenableBuilder<NativeVideoValue>(
          valueListenable: controller,
          builder: (context, value, _) {
            final Size panel;
            if (isVideo) {
              final aspect = value.aspectRatio.clamp(0.5, 2.4).toDouble();
              final width = aspect >= 1
                  ? _videoLandscapeWidth
                  : _videoPortraitWidth;
              panel = Size(width, math.min(width / aspect, _videoMaxHeight));
            } else {
              panel = Size(math.min(screen.width - 2 * _margin, 420), _audioHeight);
            }
            if (_isVideoLayout != isVideo) {
              _isVideoLayout = isVideo;
              _offset = isVideo ? _lastVideoOffset : _lastAudioOffset;
              _controlsVisible = false;
            }
            final offset = _clamp(
              _offset ?? _defaultOffset(panel, screen, safe, isVideo),
              panel,
              screen,
              safe,
            );
            return Stack(
              children: [
                Positioned(
                  left: offset.dx,
                  top: offset.dy,
                  width: panel.width,
                  height: panel.height,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (details) =>
                        _onDrag(details, panel, screen, safe),
                    child: isVideo
                        ? _VideoWindow(
                            controller: controller,
                            value: value,
                            host: host,
                            controlsVisible: _controlsVisible,
                            onToggleControls: _toggleControls,
                            onInteract: _showControls,
                          )
                        : _AudioBar(
                            file: file,
                            value: value,
                            host: host,
                          ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

double _progressOf(NativeVideoValue value) {
  final total = value.duration.inMilliseconds;
  if (total <= 0) return 0;
  return (value.position.inMilliseconds / total).clamp(0.0, 1.0).toDouble();
}

class _AudioBar extends StatelessWidget {
  final String file;
  final NativeVideoValue value;
  final MiniPlayerHost host;

  const _AudioBar({
    required this.file,
    required this.value,
    required this.host,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    return Material(
      color: cs.surfaceContainerHigh,
      elevation: 6,
      shadowColor: Colors.black,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: expandMiniPlayer,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Row(
                        children: [
                          Icon(Icons.music_note_rounded, color: cs.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              p.basename(file),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: l10n.previousTooltip,
                  onPressed: host.hasPrevious
                      ? () => unawaited(host.previous())
                      : null,
                  icon: const Icon(Icons.skip_previous_rounded),
                ),
                IconButton(
                  tooltip: value.isPlaying ? l10n.pauseLabel : l10n.playLabel,
                  onPressed: host.togglePlayPause,
                  icon: Icon(
                    value.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                  ),
                ),
                IconButton(
                  tooltip: l10n.nextTooltip,
                  onPressed: host.hasNext ? () => unawaited(host.next()) : null,
                  icon: const Icon(Icons.skip_next_rounded),
                ),
                IconButton(
                  tooltip: l10n.closeTooltip,
                  onPressed: () => unawaited(host.closeAndWait()),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          LinearProgressIndicator(value: _progressOf(value), minHeight: 3),
        ],
      ),
    );
  }
}

class _VideoWindow extends StatelessWidget {
  final NativeVideoController controller;
  final NativeVideoValue value;
  final MiniPlayerHost host;
  final bool controlsVisible;
  final VoidCallback onToggleControls;
  final VoidCallback onInteract;

  const _VideoWindow({
    required this.controller,
    required this.value,
    required this.host,
    required this.controlsVisible,
    required this.onToggleControls,
    required this.onInteract,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Material(
      color: Colors.black,
      elevation: 8,
      shadowColor: Colors.black,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          NativeVideoPlayerView(controller: controller),
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: onToggleControls,
          ),
          if (controlsVisible) ...[
            const ColoredBox(color: Color(0x73000000)),
            Align(
              alignment: Alignment.topLeft,
              child: _WindowButton(
                icon: Icons.open_in_full_rounded,
                tooltip: l10n.miniPlayerOpenTooltip,
                onPressed: expandMiniPlayer,
              ),
            ),
            Align(
              alignment: Alignment.topRight,
              child: _WindowButton(
                icon: Icons.close_rounded,
                tooltip: l10n.closeTooltip,
                onPressed: () => unawaited(host.closeAndWait()),
              ),
            ),
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _WindowButton(
                    icon: Icons.skip_previous_rounded,
                    tooltip: l10n.previousTooltip,
                    onPressed: host.hasPrevious
                        ? () {
                            onInteract();
                            unawaited(host.previous());
                          }
                        : null,
                  ),
                  _WindowButton(
                    icon: value.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    tooltip: value.isPlaying ? l10n.pauseLabel : l10n.playLabel,
                    size: 32,
                    onPressed: () {
                      onInteract();
                      host.togglePlayPause();
                    },
                  ),
                  _WindowButton(
                    icon: Icons.skip_next_rounded,
                    tooltip: l10n.nextTooltip,
                    onPressed: host.hasNext
                        ? () {
                            onInteract();
                            unawaited(host.next());
                          }
                        : null,
                  ),
                ],
              ),
            ),
          ],
          Align(
            alignment: Alignment.bottomCenter,
            child: LinearProgressIndicator(
              value: _progressOf(value),
              minHeight: 3,
              backgroundColor: Colors.white24,
            ),
          ),
        ],
      ),
    );
  }
}

class _WindowButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;

  const _WindowButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 22,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      iconSize: size,
      visualDensity: VisualDensity.compact,
      color: Colors.white,
      disabledColor: Colors.white38,
      icon: Icon(icon),
    );
  }
}
