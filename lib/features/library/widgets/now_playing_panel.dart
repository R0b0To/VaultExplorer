import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/features/browser/viewer/background_playback/background_playback_host.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';
import 'package:vaultexplorer/features/browser/viewer/models/ab_loop_state.dart';
import 'package:vaultexplorer/features/browser/viewer/native_video_controller.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/media_player_widget.dart'
    show VideoPlaybackProgress;
import 'package:vaultexplorer/features/library/controllers/music_hub.dart';
import 'package:vaultexplorer/features/library/widgets/audio_waveform_seek_bar.dart';
import 'package:vaultexplorer/features/library/widgets/library_cover.dart';
import 'package:vaultexplorer/features/library/widgets/now_playing_info.dart';
import 'package:vaultexplorer/features/library/widgets/music_covers.dart';
import 'package:vaultexplorer/features/library/widgets/music_queue_sheet.dart';
import 'package:vaultexplorer/features/library/widgets/smooth_playback_position.dart';

double _lerp(double a, double b, double t) => a + (b - a) * t;

Rect _lerpRect(Rect a, Rect b, double t) => Rect.fromLTRB(
  _lerp(a.left, b.left, t),
  _lerp(a.top, b.top, t),
  _lerp(a.right, b.right, t),
  _lerp(a.bottom, b.bottom, t),
);

/// 0 until [a], 1 from [b] on, linear in between.
double _seg(double p, double a, double b) =>
    ((p - a) / (b - a)).clamp(0.0, 1.0);

/// Lets the mini bar steer the player while its finger is still down: the
/// drag starts on the bar, the player opens underneath it, and the rest of the
/// drag (and its release) is forwarded here.
class NowPlayingHandle {
  NowPlayingHandle._({
    required this.expand,
    required this.hub,
    required this.covers,
    required this.miniRect,
    required this.navigator,
  });

  /// Open all the way by itself (a tap, or a drag that was let go of upwards)
  /// instead of following a drag.
  bool expand;

  final MusicHub hub;
  final MusicCovers covers;
  final Rect miniRect;
  final NavigatorState navigator;

  /// While a drag is being followed the player lives in the overlay, not on a
  /// route: pushing a route would cancel the gesture the finger is making.
  OverlayEntry? _entry;
  bool _handedOff = false;

  _NowPlayingPageState? _page;
  double _pendingDy = 0;
  double? _pendingVelocity;

  /// Moves the player with the finger; [dy] is the vertical movement in
  /// pixels, negative going up.
  void dragBy(double dy) {
    final page = _page;
    if (page == null) {
      _pendingDy += dy;
    } else {
      page._dragBy(dy);
    }
  }

  /// The finger lifted at [velocityY] pixels per second (negative going up).
  void release(double velocityY) {
    final page = _page;
    if (page == null) {
      _pendingVelocity = velocityY;
    } else {
      page._release(velocityY);
    }
  }

  void _attach(_NowPlayingPageState page) {
    _page = page;
    if (_pendingDy != 0) page._dragBy(_pendingDy);
    _pendingDy = 0;
    final velocity = _pendingVelocity;
    _pendingVelocity = null;
    if (velocity != null) {
      page._release(velocity);
    } else if (expand) {
      page._settleTo(1.0);
    }
  }

  void _detach(_NowPlayingPageState page) {
    if (identical(_page, page)) _page = null;
  }
}

/// Entry point of the music player that grows out of the mini bar.
///
/// One animation value drives the whole thing: the cover grows
/// from the bar's thumbnail to the big cover, the play, previous and next
/// buttons travel to their places, the title and the waveform fade in, and the
/// panel itself rises from the bar to the full screen, tracking the finger
/// while it is dragged. Dragging it back down (or Back) returns it to the bar.
class NowPlayingPanel {
  NowPlayingPanel._();

  /// True while the player is up. The mini bars hide themselves meanwhile: the
  /// panel starts exactly on top of the bar and takes its place.
  static final ValueNotifier<bool> isOpen = ValueNotifier<bool>(false);

  static NowPlayingHandle? _current;

  /// Opens the player over [miniRect], the bar's rectangle on screen. With
  /// [expand] it opens by itself (on a route, so Back works); otherwise the
  /// caller feeds it the drag through the returned handle (in the overlay, so
  /// the gesture survives) and it moves onto a route once it is let go open.
  /// Null when there is nothing to open on.
  static NowPlayingHandle? open(
    BuildContext context, {
    required MusicHub hub,
    required MusicCovers covers,
    required Rect miniRect,
    bool expand = false,
  }) {
    final existing = _current;
    if (existing != null) return existing;
    final navigator = Navigator.maybeOf(context, rootNavigator: true);
    if (navigator == null) return null;
    final handle = NowPlayingHandle._(
      expand: expand,
      hub: hub,
      covers: covers,
      miniRect: miniRect,
      navigator: navigator,
    );
    if (expand) {
      _current = handle;
      isOpen.value = true;
      _pushRoute(handle, initialP: 0);
      return handle;
    }
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return null;
    _current = handle;
    isOpen.value = true;
    final entry = OverlayEntry(
      builder: (context) =>
          _NowPlayingPage(handle: handle, inOverlay: true, initialP: 0),
    );
    handle._entry = entry;
    overlay.insert(entry);
    return handle;
  }

  static void _pushRoute(NowPlayingHandle handle, {required double initialP}) {
    handle.navigator.push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.transparent,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (context, _, _) => _NowPlayingPage(
          handle: handle,
          inOverlay: false,
          initialP: initialP,
        ),
        transitionsBuilder: (_, _, _, child) => child,
      ),
    );
  }

  /// The finger let go with the player open enough to stay: carry on from the
  /// same spot on a real route (which Back understands) and drop the overlay
  /// copy, in the same frame so nothing blinks.
  static void _handOff(NowPlayingHandle handle, double p) {
    final entry = handle._entry;
    if (entry == null) return;
    handle._handedOff = true;
    handle._entry = null;
    handle.expand = true;
    _pushRoute(handle, initialP: p);
    entry.remove();
    entry.dispose();
  }

  /// Takes the overlay copy away (collapsed, or playback ended).
  static void _dismissOverlay(NowPlayingHandle handle) {
    final entry = handle._entry;
    handle._entry = null;
    if (entry != null) {
      entry.remove();
      entry.dispose();
    }
  }

  static void _closed(NowPlayingHandle handle) {
    if (identical(_current, handle)) _current = null;
    // Listeners are widgets, and this runs while the tree is being torn down.
    scheduleMicrotask(() {
      if (_current == null) isOpen.value = false;
    });
  }
}

enum _PanelMenu { openViewer, stop }

class _NowPlayingPage extends StatefulWidget {
  final NowPlayingHandle handle;

  /// Shown in the overlay while a drag is followed (see [NowPlayingHandle]),
  /// not on a route.
  final bool inOverlay;

  /// How far open the panel starts: 0 out of the bar, or where the finger let
  /// go when carrying on from the overlay copy.
  final double initialP;

  const _NowPlayingPage({
    required this.handle,
    required this.inOverlay,
    required this.initialP,
  });

  @override
  State<_NowPlayingPage> createState() => _NowPlayingPageState();
}

class _NowPlayingPageState extends State<_NowPlayingPage>
    with TickerProviderStateMixin {
  static const double _miniCover = 44;
  static const double _miniButton = 48;
  static const double _expandedPlay = 72;
  static const double _topBar = 56;

  final BackgroundPlaybackHost _host = BackgroundPlaybackHost.instance;
  late final AnimationController _c = AnimationController(
    vsync: this,
    lowerBound: 0,
    upperBound: 1,
    value: widget.initialP,
  );

  /// Glides the progress between the player's position reports.
  late final SmoothPlaybackPosition _smooth = SmoothPlaybackPosition(
    vsync: this,
    onFrame: _onSmoothFrame,
  );

  final ValueNotifier<VideoPlaybackProgress> _progress =
      ValueNotifier<VideoPlaybackProgress>(const VideoPlaybackProgress());
  final ValueNotifier<AbLoopState> _noLoop = ValueNotifier<AbLoopState>(
    AbLoopState.empty,
  );

  BackgroundPlaybackSession? _session;
  NativeVideoController? _controller;
  ModalRoute<dynamic>? _route;
  bool _removalRequested = false;
  bool _removed = false;
  bool _closing = false;
  bool _ready = false;
  String? _lastTrackPath;
  double _trackSlide = 1;
  bool _pendingTrackSlide = false;
  bool _dragActive = false;
  int _dragDirection = 0;

  double get _travel => math.max(widget.handle.miniRect.top, 1.0);

  @override
  void initState() {
    super.initState();
    _host.activeSession.addListener(_syncSession);
    _syncSession();
    _ready = true;
    widget.handle._attach(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route ??= ModalRoute.of(context);
    _tryRemove();
  }

  @override
  void dispose() {
    widget.handle._detach(this);
    _host.activeSession.removeListener(_syncSession);
    _unbindSession();
    _c.dispose();
    _progress.dispose();
    _noLoop.dispose();
    _smooth.dispose();
    // Handing over from the overlay copy to the route is not a closing.
    if (!(widget.inOverlay && widget.handle._handedOff)) {
      NowPlayingPanel._closed(widget.handle);
    }
    super.dispose();
  }

  // ── Session ──────────────────────────────────────────────────────────────

  void _syncSession() {
    final next = _host.activeSession.value;
    if (identical(next, _session)) return;
    _unbindSession();
    _session = next;
    _lastTrackPath = next?.playlist.currentFile;
    _pendingTrackSlide = false;
    if (next == null) {
      _removeSelf();
      return;
    }
    next.playlist.addListener(_onPlaylistChanged);
    next.playbackManager.activeControllerNotifier.addListener(_bindController);
    _bindController();
    if (!_isMusic(next)) {
      _removeSelf();
      return;
    }
    if (mounted && _ready) setState(() {});
  }

  void _unbindSession() {
    final session = _session;
    _session = null;
    _unbindController();
    if (session == null) return;
    try {
      session.playlist.removeListener(_onPlaylistChanged);
      session.playbackManager.activeControllerNotifier.removeListener(
        _bindController,
      );
    } catch (_) {
      // The session may already be torn down along with its notifiers.
    }
  }

  bool _isMusic(BackgroundPlaybackSession session) {
    final path = session.playlist.currentFile;
    return path.isNotEmpty && MediaViewerConstants.isAudio(path);
  }

  void _onPlaylistChanged() {
    final session = _session;
    if (session == null || _removed) return;
    if (!_isMusic(session)) {
      _removeSelf();
      return;
    }
    final path = session.playlist.currentFile;
    if (path != _lastTrackPath) {
      if (!_pendingTrackSlide) _trackSlide = 1;
      _pendingTrackSlide = false;
      _lastTrackPath = path;
    }
    if (mounted) setState(() {});
  }

  void _bindController() {
    final session = _session;
    final next = session?.playbackManager.activeController;
    if (identical(next, _controller)) return;
    _unbindController();
    _controller = next;
    if (next == null) return;
    next.addListener(_onTick);
    _onTick();
  }

  void _unbindController() {
    final controller = _controller;
    _controller = null;
    if (controller == null) return;
    try {
      controller.removeListener(_onTick);
    } catch (_) {
      // Disposed along with the player.
    }
  }

  void _onTick() {
    final controller = _controller;
    if (controller == null || controller.isDisposed) return;
    _smooth.report(controller.value, speed: _session?.playbackSpeed ?? 1.0);
  }

  /// Called every frame while playing (and on each report): the position as
  /// it is estimated now, so the seek bar glides.
  void _onSmoothFrame(Duration position, Duration duration) {
    final current = _progress.value;
    if (current.isDragging) return;
    _progress.value = current.copyWith(position: position, duration: duration);
  }

  /// Takes this page off the stack wherever it is in it, so a viewer pushed
  /// on top of it (see "Open in media player") is left alone.
  void _removeSelf() {
    _removalRequested = true;
    _tryRemove();
  }

  /// Does the removal once the route is known (it is not yet in `initState`).
  void _tryRemove() {
    if (!_removalRequested || _removed) return;
    if (widget.inOverlay) {
      _removed = true;
      scheduleMicrotask(() {
        NowPlayingPanel._dismissOverlay(widget.handle);
        NowPlayingPanel._closed(widget.handle);
      });
      return;
    }
    final route = _route;
    final navigator = route?.navigator;
    if (route == null || navigator == null) return;
    _removed = true;
    // A removal while the tree is being built or torn down is not allowed.
    scheduleMicrotask(() {
      if (route.isActive) navigator.removeRoute(route);
    });
  }

  // ── Dragging ─────────────────────────────────────────────────────────────

  void _beginDrag() {
    _dragActive = true;
    _closing = false;
    _dragDirection = 0;
    _c.stop();
  }

  void _endDrag(double velocityY) {
    if (!_dragActive) return;
    _dragActive = false;
    _release(velocityY);
  }

  void _cancelDrag() {
    if (!_dragActive) return;
    _dragActive = false;
    _release(0);
  }

  void _dragBy(double dy) {
    if (dy != 0) _dragDirection = dy > 0 ? 1 : -1;
    _closing = false;
    _c.stop();
    _c.value = (_c.value - dy / _travel).clamp(0.0, 1.0);
  }

  void _release(double velocityY) {
    if (_closing) return;
    final double target;
    if (velocityY.abs() > 350) {
      target = velocityY < 0 ? 1.0 : 0.0;
    } else if (_dragDirection < 0) {
      // Let a deliberate slow upward drag open without needing half the
      // screen's travel.
      target = _c.value >= 0.2 ? 1.0 : 0.0;
    } else if (_dragDirection > 0) {
      // Use a matching threshold when dragging the full player down.
      target = _c.value <= 0.8 ? 0.0 : 1.0;
    } else {
      target = _c.value > 0.5 ? 1.0 : 0.0;
    }
    if (widget.inOverlay && target == 1.0) {
      NowPlayingPanel._handOff(widget.handle, _c.value);
      return;
    }
    _settleTo(target);
  }

  void _settleTo(double target) {
    if (_removed) return;
    final distance = (target - _c.value).abs();
    final duration = Duration(milliseconds: (140 + 260 * distance).round());
    if (target == 0.0) _closing = true;
    if (target == 1.0) {
      _closing = false;
      HapticFeedback.selectionClick();
    }
    _c.animateTo(target, duration: duration, curve: Curves.easeOutCubic).then((
      _,
    ) {
      if (target == 0.0 && mounted) _finishCollapse();
    });
  }

  void _collapse() => _settleTo(0.0);

  void _finishCollapse() => _removeSelf();

  // ── Actions ──────────────────────────────────────────────────────────────

  void _step(int direction) {
    final currentPath = _session?.playlist.currentFile;
    _trackSlide = direction > 0 ? 1 : -1;
    _pendingTrackSlide = true;
    unawaited(
      _host.stepItem(direction).then((_) {
        if (mounted && _session?.playlist.currentFile == currentPath) {
          _pendingTrackSlide = false;
        }
      }),
    );
  }

  void _togglePlay() => unawaited(_host.togglePlayback());

  void _cycleRepeat() {
    final next = switch (_host.repeat.value) {
      PlaybackRepeat.off => PlaybackRepeat.all,
      PlaybackRepeat.all => PlaybackRepeat.one,
      PlaybackRepeat.one => PlaybackRepeat.off,
    };
    _host.repeat.value = next;
    HapticFeedback.selectionClick();
  }

  void _openQueue() {
    final session = _session;
    if (session == null) return;
    showMusicQueueSheet(
      context,
      hub: widget.handle.hub,
      covers: widget.handle.covers,
    );
  }

  Future<void> _onMenu(_PanelMenu item) async {
    switch (item) {
      case _PanelMenu.openViewer:
        // The viewer takes the running player back on its own. Open it first,
        // then step aside, so it does not end up under this page.
        _host.expand();
        _removeSelf();
      case _PanelMenu.stop:
        await _host.closeAndWait();
    }
  }

  // ── Layout ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final session = _session;
    final path = session?.playlist.currentFile ?? '';
    final info = session == null || path.isEmpty
        ? null
        : NowPlayingInfo.resolve(widget.handle.hub, session, path);

    final content = Material(
      type: MaterialType.transparency,
      child: SizedBox.expand(
        child: info == null
            ? const SizedBox.shrink()
            : AnimatedBuilder(
                animation: _c,
                builder: (context, _) =>
                    _layers(context, media.size, media.padding, info, session!),
              ),
      ),
    );
    // The overlay copy lives only while a finger is down: Back has nothing to
    // do there. The route copy turns Back into "minimize".
    if (widget.inOverlay) return content;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _collapse();
      },
      child: content,
    );
  }

  Widget _layers(
    BuildContext context,
    Size size,
    EdgeInsets pad,
    NowPlayingInfo info,
    BackgroundPlaybackSession session,
  ) {
    final cs = context.colors;
    final text = context.typography;
    final l10n = context.l10n;
    final p = _c.value;
    final mini = widget.handle.miniRect;
    final screen = Offset.zero & size;
    final panel = _lerpRect(mini, screen, p);

    // The mini bar's own content sits at the same offsets inside the panel as
    // it did inside the bar, and rises with the panel's top edge.
    final miniDy = panel.top - mini.top;
    final miniCoverTop = mini.top + (mini.height - _miniCover) / 2 + 1;
    final miniCoverRect = Rect.fromLTWH(
      mini.left + AppSpacing.md,
      miniCoverTop,
      _miniCover,
      _miniCover,
    );
    final miniPlayCenter = Offset(
      mini.right - AppSpacing.xs - _miniButton * 1.5,
      mini.top + 1 + (mini.height - 1) / 2,
    );

    // Expanded geometry.
    const titleHeight = 84.0;
    final below =
        24 + titleHeight + 8 + 52 + 12 + _expandedPlay + 24 + pad.bottom;
    final coverSize = math
        .min(size.width - 64, size.height - pad.top - _topBar - 8 - below)
        .clamp(96.0, 440.0)
        .toDouble();
    final coverTop = pad.top + _topBar + 8;
    final expCoverRect = Rect.fromLTWH(
      (size.width - coverSize) / 2,
      coverTop,
      coverSize,
      coverSize,
    );
    final titleTop = coverTop + coverSize + 24;
    final seekTop = titleTop + titleHeight + 8;
    final controlsTop = seekTop + 52 + 12;
    final expPlayCenter = Offset(
      size.width / 2,
      controlsTop + _expandedPlay / 2,
    );

    // Shared elements. They move linearly with the panel, so they follow the
    // finger going up exactly as they do going down.
    final e = p;
    // The cover follows the panel's rising edge; the controls take the direct
    // path from their mini-player positions to their full-player positions.
    final coverRect = _lerpRect(
      miniCoverRect.shift(Offset(0, miniDy)),
      expCoverRect,
      e,
    );
    final coverScale = coverRect.width / coverSize;
    final coverRadius = _lerp(6, 20, e);
    final playSize = _lerp(40, _expandedPlay, e);
    final playCenter = Offset(
      _lerp(miniPlayCenter.dx, expPlayCenter.dx, e),
      _lerp(miniPlayCenter.dy, expPlayCenter.dy, e),
    );

    // Previous and next are shared too: they sit either side of the play
    // button in the bar and in the full player, and travel between the two.
    final step = ((size.width - 48) / 5).clamp(64.0, 84.0).toDouble();
    Offset sideCenter(int direction) => Offset(
      _lerp(
        miniPlayCenter.dx + direction * _miniButton,
        expPlayCenter.dx + direction * step,
        e,
      ),
      playCenter.dy,
    );
    final prevCenter = sideCenter(-1);
    final nextCenter = sideCenter(1);
    final sideBox = _lerp(_miniButton, 56, e);
    final sideIcon = _lerp(24, 36, e);

    final miniOpacity = 1 - _seg(p, 0.0, 0.35);
    final fullOpacity = _seg(p, 0.55, 1.0);
    final shadow = 1 - _seg(p, 0.0, 0.5);

    Widget fade(double opacity, Widget child) {
      if (opacity <= 0.001) return const SizedBox.shrink();
      return IgnorePointer(
        ignoring: opacity < 0.6,
        child: Opacity(opacity: opacity, child: child),
      );
    }

    final miniTextLeft = miniCoverRect.right + AppSpacing.md - 4;
    final miniTextRight =
        mini.right - AppSpacing.xs - _miniButton * 3 - AppSpacing.sm;
    final titleStyle = TextStyle.lerp(
      text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      e,
    );
    final artistStyle = TextStyle.lerp(
      text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
      text.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
      e,
    );
    final titleLeft = _lerp(miniTextLeft, 32, e);
    final titleRight = _lerp(miniTextRight, size.width - 32, e);
    final titleAreaTop = _lerp(mini.top + miniDy + 1, titleTop, e);
    final titleAreaHeight = _lerp(mini.height - 1, titleHeight, e);
    final titleAlignment = Alignment.lerp(
      Alignment.centerLeft,
      Alignment.topCenter,
      e,
    )!;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // The panel itself: the bar's colour on its way to the page colour.
        Positioned.fromRect(
          rect: panel,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Color.lerp(cs.surfaceContainerHigh, cs.surface, e),
              boxShadow: [
                if (shadow > 0)
                  BoxShadow(
                    blurRadius: 6 * shadow,
                    offset: Offset(0, -1 * shadow),
                    color: Colors.black.withValues(alpha: 0.18 * shadow),
                  ),
              ],
            ),
          ),
        ),

        // Thin progress line of the bar.
        if (miniOpacity > 0.001)
          Positioned(
            left: panel.left,
            top: panel.top,
            width: panel.width,
            height: 2,
            child: Opacity(
              opacity: miniOpacity,
              child: ValueListenableBuilder<VideoPlaybackProgress>(
                valueListenable: _progress,
                builder: (context, progress, _) => LinearProgressIndicator(
                  minHeight: 2,
                  value: progress.duration.inMilliseconds > 0
                      ? progress.sliderValue
                      : 0,
                ),
              ),
            ),
          ),

        // The title and artist travel between the bar and full-player layouts.
        Positioned(
          left: titleLeft,
          width: math.max(0.0, titleRight - titleLeft),
          top: titleAreaTop,
          height: titleAreaHeight,
          child: Align(
            alignment: titleAlignment,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: math.max(0.0, titleRight - titleLeft),
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                layoutBuilder: (currentChild, previousChildren) => Stack(
                  alignment: titleAlignment,
                  clipBehavior: Clip.none,
                  children: [
                    ...previousChildren,
                    if (currentChild != null) currentChild,
                  ],
                ),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: Offset(_trackSlide * 0.16, 0),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: Column(
                  key: ValueKey<String>('t${info.path}'),
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      info.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: titleStyle,
                    ),
                    if (info.artist.isNotEmpty)
                      Padding(
                        padding: EdgeInsets.only(top: 2 * e),
                        child: Text(
                          info.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: artistStyle,
                        ),
                      ),
                    if (info.album.isNotEmpty)
                      ClipRect(
                        child: Align(
                          alignment: Alignment.topCenter,
                          heightFactor: fullOpacity,
                          child: Opacity(
                            opacity: fullOpacity,
                            child: Text(
                              info.album,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.bodyMedium?.copyWith(
                                color: cs.onSurfaceVariant.withValues(
                                  alpha: 0.8,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // Top bar of the full player.
        Positioned(
          left: 0,
          right: 0,
          top: pad.top,
          height: _topBar,
          child: fade(
            fullOpacity,
            Row(
              children: [
                const SizedBox(width: AppSpacing.xs),
                IconButton(
                  tooltip: l10n.nowPlayingCollapse,
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
                  onPressed: _collapse,
                ),
                const Spacer(),
                IconButton(
                  tooltip: l10n.nowPlayingQueue,
                  icon: const Icon(Icons.queue_music_rounded),
                  onPressed: _openQueue,
                ),
                PopupMenuButton<_PanelMenu>(
                  onSelected: _onMenu,
                  itemBuilder: (context) => [
                    PopupMenuItem<_PanelMenu>(
                      value: _PanelMenu.openViewer,
                      child: Text(l10n.nowPlayingOpenViewer),
                    ),
                    PopupMenuItem<_PanelMenu>(
                      value: _PanelMenu.stop,
                      child: Text(l10n.musicMiniStop),
                    ),
                  ],
                ),
                const SizedBox(width: AppSpacing.xs),
              ],
            ),
          ),
        ),

        // The big cover: the bar's thumbnail, scaled up. Swiping it skips.
        // No width or height on the Positioned: the cover is laid out at its
        // full size and scaled, and tight constraints would shrink it first.
        Positioned(
          left: coverRect.left,
          top: coverRect.top,
          child: GestureDetector(
            onHorizontalDragEnd: (details) {
              final v = details.primaryVelocity ?? 0;
              if (v < -300) {
                _step(1);
              } else if (v > 300) {
                _step(-1);
              }
            },
            child: Transform.scale(
              scale: coverScale,
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: coverSize,
                height: coverSize,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: Offset(_trackSlide * 0.12, 0),
                        end: Offset.zero,
                      ).animate(animation),
                      child: ScaleTransition(
                        scale: Tween<double>(
                          begin: 0.94,
                          end: 1,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                  ),
                  child: KeyedSubtree(
                    key: ValueKey<String>(info.path),
                    child: LibraryCover(
                      covers: widget.handle.covers,
                      track: info.coverTrack,
                      groupKey: info.coverKey,
                      size: coverSize,
                      borderRadius: coverRadius / math.max(coverScale, 0.01),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),

        // The waveform seek bar of the full player.
        Positioned(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          top: seekTop,
          height: 52,
          child: fade(
            fullOpacity,
            AudioWaveformSeekBar(
              playbackManager: session.playbackManager,
              videoProgressNotifier: _progress,
              abLoopNotifier: _noLoop,
              onShowUIChanged: (_) {},
              onStartHideTimer: () {},
              timeColor: cs.onSurface,
              restColor: cs.onSurface.withValues(alpha: 0.2),
              fallback: _PlainSeek(
                progress: _progress,
                controller: () => _controller,
              ),
            ),
          ),
        ),

        // Shuffle and repeat of the full player, either side of the transport
        // buttons. They only exist in the full player, so they fade in.
        Positioned(
          left: 0,
          right: 0,
          top: controlsTop,
          height: _expandedPlay,
          child: fade(
            fullOpacity,
            ListenableBuilder(
              listenable: Listenable.merge([
                _host.repeat,
                _host.libraryShuffled,
              ]),
              builder: (context, _) {
                final repeat = _host.repeat.value;
                final shuffled = _host.libraryShuffled.value;
                return Stack(
                  children: [
                    Positioned(
                      left: size.width / 2 - 2 * step - 24,
                      top: (_expandedPlay - 48) / 2,
                      child: IconButton(
                        tooltip: l10n.nowPlayingShuffle,
                        icon: Icon(
                          Icons.shuffle_rounded,
                          color: shuffled ? cs.primary : cs.onSurfaceVariant,
                        ),
                        onPressed: _host.toggleLibraryShuffle,
                      ),
                    ),
                    Positioned(
                      left: size.width / 2 + 2 * step - 24,
                      top: (_expandedPlay - 48) / 2,
                      child: IconButton(
                        tooltip: switch (repeat) {
                          PlaybackRepeat.off => l10n.nowPlayingRepeatOff,
                          PlaybackRepeat.all => l10n.nowPlayingRepeatAll,
                          PlaybackRepeat.one => l10n.nowPlayingRepeatOne,
                        },
                        icon: Icon(
                          repeat == PlaybackRepeat.one
                              ? Icons.repeat_one_rounded
                              : Icons.repeat_rounded,
                          color: repeat == PlaybackRepeat.off
                              ? cs.onSurfaceVariant
                              : cs.primary,
                        ),
                        onPressed: _cycleRepeat,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),

        // Previous and next: the same two buttons in the bar and in the full
        // player, moving from one to the other with the panel.
        for (final side in const [-1, 1])
          Positioned(
            left: (side < 0 ? prevCenter.dx : nextCenter.dx) - sideBox / 2,
            top: (side < 0 ? prevCenter.dy : nextCenter.dy) - sideBox / 2,
            width: sideBox,
            height: sideBox,
            child: ListenableBuilder(
              listenable: Listenable.merge([session.playlist, _host.repeat]),
              builder: (context, _) {
                final can = side < 0
                    ? _host.canStepPrevious
                    : _host.canStepNext;
                return IconButton(
                  tooltip: side < 0
                      ? l10n.musicMiniPrevious
                      : l10n.musicMiniNext,
                  iconSize: sideIcon,
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints.tightFor(
                    width: sideBox,
                    height: sideBox,
                  ),
                  icon: Icon(
                    side < 0
                        ? Icons.skip_previous_rounded
                        : Icons.skip_next_rounded,
                  ),
                  onPressed: can ? () => _step(side) : null,
                );
              },
            ),
          ),

        // The play button: one widget that travels from the bar to the middle
        // of the full player's controls.
        Positioned(
          left: playCenter.dx - playSize / 2,
          top: playCenter.dy - playSize / 2,
          width: playSize,
          height: playSize,
          child: ValueListenableBuilder<bool>(
            valueListenable: _host.playing,
            builder: (context, playing, _) => Material(
              color: cs.primary,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: _togglePlay,
                child: Tooltip(
                  message: playing ? l10n.musicMiniPause : l10n.musicMiniPlay,
                  child: Icon(
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: playSize * 0.6,
                    color: cs.onPrimary,
                  ),
                ),
              ),
            ),
          ),
        ),

        // Dragging anywhere on the panel moves it. Laid over everything but
        // the controls it must not swallow, so it is an opaque strip over the
        // cover-free background only.
        Positioned.fromRect(
          rect: panel,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onVerticalDragStart: (_) => _beginDrag(),
            onVerticalDragUpdate: (d) => _dragBy(d.delta.dy),
            onVerticalDragEnd: (d) => _endDrag(d.primaryVelocity ?? 0),
            onVerticalDragCancel: _cancelDrag,
          ),
        ),
      ],
    );
  }
}

/// The ordinary slider, shown until the waveform is ready (and for files that
/// are too long to decode while they play).
class _PlainSeek extends StatelessWidget {
  final ValueNotifier<VideoPlaybackProgress> progress;
  final NativeVideoController? Function() controller;

  const _PlainSeek({required this.progress, required this.controller});

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return ValueListenableBuilder<VideoPlaybackProgress>(
      valueListenable: progress,
      builder: (context, value, _) {
        final hasDuration = value.duration.inMilliseconds > 0;
        return Row(
          children: [
            Text(
              _clock(value.position),
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            Expanded(
              child: Slider(
                value: hasDuration ? value.sliderValue.clamp(0.0, 1.0) : 0,
                onChangeStart: hasDuration
                    ? (_) => progress.value = progress.value.copyWith(
                        isDragging: true,
                      )
                    : null,
                onChanged: hasDuration
                    ? (v) {
                        final ms = value.duration.inMilliseconds;
                        progress.value = progress.value.copyWith(
                          isDragging: true,
                          sliderValue: v,
                          position: Duration(milliseconds: (v * ms).round()),
                        );
                      }
                    : null,
                onChangeEnd: hasDuration
                    ? (v) async {
                        final ms = progress.value.duration.inMilliseconds;
                        final target = Duration(milliseconds: (v * ms).round());
                        final c = controller();
                        if (c != null &&
                            !c.isDisposed &&
                            c.value.isInitialized) {
                          await c.seekTo(target);
                        }
                        progress.value = progress.value.copyWith(
                          position: target,
                          sliderValue: v,
                          isDragging: false,
                        );
                      }
                    : null,
              ),
            ),
            Text(
              _clock(value.duration),
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.8),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        );
      },
    );
  }

  static String _clock(Duration d) {
    final total = d.inSeconds < 0 ? 0 : d.inSeconds;
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    final mm = h > 0 ? m.toString().padLeft(2, '0') : '$m';
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }
}
