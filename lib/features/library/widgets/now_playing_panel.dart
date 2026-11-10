import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/scheduler.dart' show SchedulerPhase;
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

/// The mini player is a floating rounded card. The player grows
/// out of it, so the card and the panel draw the same corners and shadow.
const double kMiniPlayerRadius = 16;
const EdgeInsets kMiniPlayerMargin = EdgeInsets.fromLTRB(8, 4, 8, 6);

/// The card's shadow, faded out with [strength] (1 at rest, 0 once the player
/// is half open) as the panel stops looking like a card.
List<BoxShadow> miniPlayerShadows(double strength) => [
  if (strength > 0)
    BoxShadow(
      blurRadius: 10 * strength,
      offset: Offset(0, 2 * strength),
      color: Colors.black.withValues(alpha: 0.22 * strength),
    ),
];

/// How far (in pixels) the card dips below its resting place when it bounces
/// into the minimized state.
const double _kMinimizeDip = 120;

/// bouncing curve: overshoots its target a little, then settles.
const Curve _kBounce = Cubic(0.175, 0.885, 0.32, 1.125);

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
    lowerBound: -0.2,
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
  bool _ready = false;
  String? _lastTrackPath;
  double _trackSlide = 1;
  bool _pendingTrackSlide = false;
  bool _dragActive = false;
  int _dragDirection = 0;

  /// The queue: a sheet that rises from the bottom of the full player, dragged
  /// up from anywhere on it (see [_dragBy]) or from its own handle.
  final DraggableScrollableController _sheet = DraggableScrollableController();
  ScrollController? _queueScroll;
  double _screenHeight = 800;
  double _padBottom = 0;
  double _sheetMin = 0.0;
  double _sheetMax = 0.9;
  bool _sheetClosed = true;

  /// This drag moved the queue sheet (so its release settles the sheet).
  bool _sheetDragged = false;

  /// Fingers currently down on the panel (see [_onPointerEnd]).
  int _pointersDown = 0;

  /// How far the queue is open, 0 down to 1 up: what the cover, title and
  /// transport buttons follow on their way to the top.
  final ValueNotifier<double> _queueP = ValueNotifier<double>(0);

  double get _travel => math.max(widget.handle.miniRect.top, 1.0);

  @override
  void initState() {
    super.initState();
    _host.activeSession.addListener(_syncSession);
    _sheet.addListener(_onSheetChanged);
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
    _sheet.removeListener(_onSheetChanged);
    _sheet.dispose();
    _queueP.dispose();
    _host.activeSession.removeListener(_syncSession);
    _unbindSession();
    _c.dispose();
    _progress.dispose();
    _noLoop.dispose();
    _smooth.dispose();
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

  void _onSmoothFrame(Duration position, Duration duration) {
    final current = _progress.value;
    if (current.isDragging) return;
    _progress.value = current.copyWith(position: position, duration: duration);
  }

  void _removeSelf() {
    _removalRequested = true;
    _tryRemove();
  }

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
    scheduleMicrotask(() {
      if (route.isActive) navigator.removeRoute(route);
    });
  }

  // ── Dragging ─────────────────────────────────────────────────────────────

  void _beginDrag() {
    _dragActive = true;
    _dragDirection = 0;
    _sheetDragged = false;
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

  bool get _sheetReady => _sheet.isAttached;
  bool get _queueOpen => _sheetReady && _sheet.size > _sheetMin + 0.01;

  void _dragBy(double dy) {
    if (_removed) return;
    if (dy != 0) _dragDirection = dy > 0 ? 1 : -1;
    _c.stop();
    var rest = dy;
    if (_sheetReady && _screenHeight > 0) {
      final s = _sheet.size;
      if (rest < 0 && _c.value >= 0.999 && s < _sheetMax) {
        _sheet.jumpTo((s - rest / _screenHeight).clamp(_sheetMin, _sheetMax));
        _sheetDragged = true;
        rest = 0;
      } else if (rest > 0 && s > _sheetMin + 0.0005) {
        final room = (s - _sheetMin) * _screenHeight;
        final used = math.min(rest, room);
        _sheet.jumpTo((s - used / _screenHeight).clamp(_sheetMin, _sheetMax));
        _sheetDragged = true;
        rest -= used;
      }
    }
    if (rest != 0) {
      _c.value = (_c.value - rest / _travel).clamp(0.0, 1.0);
    }
  }

  void _release(double velocityY) {
    if (_removed) return;
    final upwards = _dragDirection < 0;

    if (_sheetDragged && _sheetReady && _c.value >= 0.999) {
      _sheetDragged = false;
      final span = math.max(_sheetMax - _sheetMin, 0.001);
      final progress = (_sheet.size - _sheetMin) / span;
      final bool open;
      if (velocityY.abs() > 350) {
        open = velocityY < 0;
      } else {
        open = upwards ? progress >= 0.2 : progress > 0.8;
      }
      _sheetTo(open ? _sheetMax : _sheetMin);
      return;
    }
    _sheetDragged = false;
    if (_sheetReady && _sheet.size > _sheetMin + 0.0005) _sheetTo(_sheetMin);

    final double target;
    if (velocityY.abs() > 350) {
      target = velocityY < 0 ? 1.0 : 0.0;
    } else if (upwards) {
      target = _c.value >= 0.2 ? 1.0 : 0.0;
    } else if (_dragDirection > 0) {
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
    final duration = Duration(
      milliseconds: (distance < 0.02 ? 120 : 220 + 140 * distance).round(),
    );
    if (distance > 0.2) HapticFeedback.selectionClick();
    _c
        .animateTo(
          target,
          duration: duration,
          curve: target == 1.0 ? Curves.fastEaseInToSlowEaseOut : _kBounce,
        )
        .then((_) {
          if (target == 0.0 && mounted && _c.value <= 0.001) _finishCollapse();
        });
  }

  void _onPointerEnd(Object? _) {
    if (_pointersDown > 0) _pointersDown--;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _removed || _pointersDown > 0 || _c.isAnimating) return;
      if (_dragActive) {
        _dragActive = false;
        _release(0);
        return;
      }
      final v = _c.value;
      if (v > 0.001 && v < 0.999) {
        _dragDirection = 0;
        _release(0);
      } else if (v <= 0.001) {
        _finishCollapse();
      }
    });
  }

  // ── The queue ────────────────────────────────────────────────────────────

  void _resetQueueScroll() {
    final c = _queueScroll;
    if (c != null && c.hasClients && c.position.pixels > 0.5) c.jumpTo(0);
  }

  void _setQueueProgress(double v) {
    if (v == _queueP.value) return;
    if (WidgetsBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _queueP.value = v;
      });
    } else {
      _queueP.value = v;
    }
  }

  void _sheetTo(double target) {
    if (!_sheetReady) return;
    if (target <= _sheetMin + 0.001) _resetQueueScroll();
    if (((target - _sheet.size) * _screenHeight).abs() > 60) {
      HapticFeedback.selectionClick();
    }
    unawaited(
      _sheet.animateTo(
        target,
        duration: const Duration(milliseconds: 300),
        curve: Curves.fastEaseInToSlowEaseOut,
      ),
    );
  }

  void _toggleQueue() => _sheetTo(_queueOpen ? _sheetMin : _sheetMax);

  void _onSheetChanged() {
    if (!_sheetReady) return;
    final span = math.max(_sheetMax - _sheetMin, 0.001);
    _setQueueProgress(((_sheet.size - _sheetMin) / span).clamp(0.0, 1.0));
    final open = _sheet.size > _sheetMin + 0.01;
    if (open && _sheetClosed) {
      _sheetClosed = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _queueToCurrent());
    } else if (!open) {
      _sheetClosed = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _resetQueueScroll());
    }
  }

  void _queueToCurrent() {
    final controller = _queueScroll;
    final session = _session;
    if (!mounted || controller == null || !controller.hasClients) return;
    if (session == null) return;
    final current = session.playlist.currentIndex;
    if (current <= 1) return;
    final header = kMusicQueuePeekHeight;
    final target = header + (current - 1) * kMusicQueueRowHeight;
    controller.jumpTo(
      math.min(target, controller.position.maxScrollExtent),
    );
  }

  void _collapse() {
    if (_sheetReady && _sheet.size > _sheetMin + 0.001) {
      _sheetTo(_sheetMin);
    }
    _settleTo(0.0);
  }

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

  Future<void> _onMenu(_PanelMenu item) async {
    switch (item) {
      case _PanelMenu.openViewer:
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

    final size = media.size;
    _screenHeight = size.height;
    _padBottom = media.padding.bottom;
    _sheetMin = 0.0;
    _sheetMax =
        ((size.height -
                    media.padding.top -
                    8 -
                    widget.handle.miniRect.height -
                    8) /
                size.height)
            .clamp(0.4, 0.95)
            .toDouble();

    final content = Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _pointersDown++,
      onPointerUp: _onPointerEnd,
      onPointerCancel: _onPointerEnd,
      child: Material(
        type: MaterialType.transparency,
        child: SizedBox.expand(
          child: info == null
              ? const SizedBox.shrink()
              : Stack(
                  children: [
                    Positioned.fill(
                      child: AnimatedBuilder(
                        animation: Listenable.merge([_c, _queueP]),
                        builder: (context, _) => _layers(
                          context,
                          media.size,
                          media.padding,
                          info,
                          session!,
                        ),
                      ),
                    ),
                    Positioned.fill(child: _queueLayer()),
                  ],
                ),
        ),
      ),
    );

    if (widget.inOverlay) return content;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_queueOpen) {
          _sheetTo(_sheetMin);
        } else {
          _collapse();
        }
      },
      child: content,
    );
  }

  Widget _queueLayer() {
    return AnimatedBuilder(
      animation: Listenable.merge([_c, _queueP]),
      child: DraggableScrollableSheet(
        controller: _sheet,
        initialChildSize: _sheetMin,
        minChildSize: _sheetMin,
        maxChildSize: _sheetMax,
        snap: true,
        shouldCloseOnMinExtent: false,
        snapSizes: [_sheetMin, _sheetMax],
        builder: (context, scroll) {
          _queueScroll = scroll;
          return MusicInlineQueue(
            hub: widget.handle.hub,
            covers: widget.handle.covers,
            scrollController: scroll,
            bottomInset: _padBottom,
            openness: _queueP,
            onHeaderTap: _toggleQueue,
          );
        },
      ),
      builder: (context, child) {
        final opacity = _seg(_c.value.clamp(0.0, 1.0), 0.55, 1.0);
        final isOffstage = opacity <= 0.001;
        if (isOffstage) {
          _sheetClosed = true;
          if (_queueP.value != 0 ||
              (_sheetReady && _sheet.size > _sheetMin + 0.001)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              if (_sheetReady && _sheet.size > _sheetMin + 0.001) {
                _sheet.reset();
              }
              if (_queueP.value != 0) {
                _queueP.value = 0;
              }
            });
          }
        }
        final isSheetOpen = _sheetReady && _sheet.size > _sheetMin + 0.001;
        return Offstage(
          offstage: isOffstage,
          child: IgnorePointer(
            ignoring: opacity < 0.95 || !isSheetOpen,
            child: Opacity(opacity: opacity.clamp(0.0, 1.0), child: child),
          ),
        );
      },
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
    final p = _c.value.clamp(0.0, 1.0).toDouble();
    final dip = (-_c.value).clamp(0.0, 0.2).toDouble();
    final mini = widget.handle.miniRect;
    final screen = Offset.zero & size;
    final panel = _lerpRect(mini, screen, p);

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
    const titleHeight = 68.0;
    const bottomBarHeight = 48.0;
    const gapCoverToTitle = 20.0;
    const gapTitleToSeek = 16.0;
    const gapSeekToControls = 20.0;
    const gapControlsToBottom = 16.0;

    final fixedBelow = gapCoverToTitle +
        titleHeight +
        gapTitleToSeek +
        52.0 +
        gapSeekToControls +
        _expandedPlay +
        gapControlsToBottom +
        bottomBarHeight +
        pad.bottom +
        8.0;

    final topBarBottom = pad.top + _topBar;
    final availForCover = math.max(0.0, size.height - topBarBottom - fixedBelow);
    final coverSize = math
        .min(size.width - 64, availForCover - 28)
        .clamp(96.0, 380.0)
        .toDouble();

    final topGap = math.max(24.0, (availForCover - coverSize) * 0.45);
    final coverTop = topBarBottom + topGap;
    final expCoverRect = Rect.fromLTWH(
      (size.width - coverSize) / 2,
      coverTop,
      coverSize,
      coverSize,
    );
    final titleTop = coverTop + coverSize + gapCoverToTitle;
    final seekTop = titleTop + titleHeight + gapTitleToSeek;
    final controlsTop = seekTop + 52 + gapSeekToControls;
    final bottomBarTop = controlsTop + _expandedPlay + gapControlsToBottom;
    final expPlayCenter = Offset(
      size.width / 2,
      controlsTop + _expandedPlay / 2,
    );

    // The queue state layout at the top.
    final q = p >= 0.999 ? _queueP.value : 0.0;
    final qBar = Rect.fromLTWH(0, pad.top + 8, size.width, mini.height);
    final qCoverRect = Rect.fromLTWH(
      qBar.left + AppSpacing.md,
      qBar.top + (qBar.height - _miniCover) / 2 + 1,
      _miniCover,
      _miniCover,
    );
    final qPlayCenter = Offset(
      qBar.right - AppSpacing.xs - _miniButton * 1.5,
      qBar.top + 1 + (qBar.height - 1) / 2,
    );
    final qTextLeft = qCoverRect.right + AppSpacing.md - 4;
    final qTextRight =
        qBar.right - AppSpacing.xs - _miniButton * 3 - AppSpacing.sm;

    final e = p;
    final coverRect = _lerpRect(
      _lerpRect(miniCoverRect.shift(Offset(0, miniDy)), expCoverRect, e),
      qCoverRect,
      q,
    );
    final coverScale = coverRect.width / coverSize;
    final coverRadius = _lerp(_lerp(6, 20, e), 6, q);
    final playSize = _lerp(_lerp(40, _expandedPlay, e), 40, q);
    final playCenter = Offset(
      _lerp(_lerp(miniPlayCenter.dx, expPlayCenter.dx, e), qPlayCenter.dx, q),
      _lerp(_lerp(miniPlayCenter.dy, expPlayCenter.dy, e), qPlayCenter.dy, q),
    );

    final step = (size.width * 0.22).clamp(72.0, 96.0).toDouble();
    Offset sideCenter(int direction) => Offset(
      _lerp(
        _lerp(
          miniPlayCenter.dx + direction * _miniButton,
          expPlayCenter.dx + direction * step,
          e,
        ),
        qPlayCenter.dx + direction * _miniButton,
        q,
      ),
      playCenter.dy,
    );
    final prevCenter = sideCenter(-1);
    final nextCenter = sideCenter(1);
    final sideBox = _lerp(_lerp(_miniButton, 56, e), _miniButton, q);
    final sideIcon = _lerp(_lerp(24, 36, e), 24, q);

    final miniOpacity = 1 - _seg(p, 0.0, 0.35);
    final fullOpacity = _seg(p, 0.55, 1.0);
    final fullFade = fullOpacity * (1 - q);
    final shadow = 1 - _seg(p, 0.0, 0.5);
    final panelRadius = BorderRadius.circular(
      _lerp(kMiniPlayerRadius, 0, _seg(p, 0.0, 0.85)),
    );

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
    final eT = e * (1 - q);
    final titleStyle = TextStyle.lerp(
      text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      eT,
    );
    final artistStyle = TextStyle.lerp(
      text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
      text.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
      eT,
    );
    final titleLeft = _lerp(_lerp(miniTextLeft, 32, e), qTextLeft, q);
    final titleRight = _lerp(
      _lerp(miniTextRight, size.width - 32, e),
      qTextRight,
      q,
    );
    final titleAreaTop = _lerp(
      _lerp(mini.top + miniDy + 1, titleTop, e),
      qBar.top + 1,
      q,
    );
    final titleAreaHeight = _lerp(
      _lerp(mini.height - 1, titleHeight, e),
      qBar.height - 1,
      q,
    );
    final titleAlignment = Alignment.lerp(
      Alignment.lerp(Alignment.centerLeft, Alignment.topCenter, e)!,
      Alignment.centerLeft,
      q,
    )!;

    return Transform.translate(
      offset: Offset(0, dip * _kMinimizeDip),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Background panel.
          Positioned.fromRect(
            rect: panel,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color.lerp(cs.surfaceContainerHigh, cs.surface, e),
                borderRadius: panelRadius,
                boxShadow: miniPlayerShadows(shadow),
              ),
            ),
          ),

          // Thin mini progress indicator.
          Positioned.fromRect(
            key: const ValueKey<String>('mini-progress'),
            rect: panel,
            child: miniOpacity > 0.001
                ? IgnorePointer(
                    child: ClipRRect(
                      borderRadius: panelRadius,
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: Opacity(
                          opacity: miniOpacity,
                          child: SizedBox(
                            height: 2,
                            child:
                                ValueListenableBuilder<VideoPlaybackProgress>(
                              valueListenable: _progress,
                              builder: (context, progress, _) =>
                                  LinearProgressIndicator(
                                minHeight: 2,
                                value: progress.duration.inMilliseconds > 0
                                    ? progress.sliderValue
                                    : 0,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),

          // Title and artist.
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
                      ?currentChild,
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
                          padding: EdgeInsets.only(top: 2 * eT),
                          child: Text(
                            info.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: artistStyle,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Subtle lower container card behind controls.
          Positioned(
            left: 0,
            right: 0,
            top: titleTop - 20,
            bottom: 0,
            child: fade(
              fullFade,
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: cs.surfaceContainer.withValues(alpha: 0.45),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Top bar: collapse, queue position & album name, menu.
          Positioned(
            left: 0,
            right: 0,
            top: pad.top,
            height: _topBar,
            child: fade(
              fullFade,
              Row(
                children: [
                  const SizedBox(width: AppSpacing.xs),
                  IconButton(
                    tooltip: l10n.nowPlayingCollapse,
                    icon: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 28,
                    ),
                    onPressed: _collapse,
                  ),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (session.playlist.playlist.isNotEmpty)
                          Text(
                            '${session.playlist.currentIndex + 1}/${session.playlist.playlist.length}',
                            style: text.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              letterSpacing: 0.5,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        if (info.album.isNotEmpty)
                          Text(
                            info.album,
                            style: text.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  PopupMenuButton<_PanelMenu>(
                    icon: const Icon(Icons.more_horiz_rounded),
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

          // Big cover.
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

          // Waveform seek bar.
          Positioned(
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            top: seekTop,
            height: 52,
            child: fade(
              fullFade,
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

          // Bottom bar: audio device/viewer, shuffle, repeat, queue toggle.
          Positioned(
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            top: bottomBarTop,
            height: bottomBarHeight,
            child: fade(
              fullFade,
              Row(
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => _onMenu(_PanelMenu.openViewer),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.headphones_rounded,
                            size: 20,
                            color: cs.onSurfaceVariant,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Audio',
                            style: text.labelMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  ListenableBuilder(
                    listenable: Listenable.merge([
                      _host.repeat,
                      _host.libraryShuffled,
                    ]),
                    builder: (context, _) {
                      final repeat = _host.repeat.value;
                      final shuffled = _host.libraryShuffled.value;
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: l10n.nowPlayingShuffle,
                            icon: Icon(
                              Icons.shuffle_rounded,
                              color: shuffled
                                  ? cs.primary
                                  : cs.onSurfaceVariant,
                            ),
                            onPressed: _host.toggleLibraryShuffle,
                          ),
                          IconButton(
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
                          IconButton(
                            tooltip: l10n.nowPlayingQueue,
                            icon: Icon(
                              Icons.queue_music_rounded,
                              color: cs.onSurfaceVariant,
                            ),
                            onPressed: _toggleQueue,
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          // Previous and next buttons.
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

          // Play/pause button.
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
                    message:
                        playing ? l10n.musicMiniPause : l10n.musicMiniPlay,
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

          // Panel vertical drag detector.
          Positioned.fromRect(
            key: const ValueKey<String>('panel-drag'),
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
      ),
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