import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/features/browser/viewer/background_playback/background_playback_host.dart';
import 'package:vaultexplorer/features/browser/viewer/native_video_controller.dart';
import 'package:vaultexplorer/features/browser/viewer/pip/picture_in_picture_bridge.dart';
import 'package:vaultexplorer/features/browser/viewer/pip/picture_in_picture_coordinator.dart';
import 'package:vaultexplorer/features/browser/viewer/video_playback_manager.dart';

/// The app's own floating video window: what is left of the viewer when it is
/// closed (back, or swipe down) while a video plays and "floating video player"
/// is on. The video keeps playing in a small window that can be dragged around
/// and parked in any corner, over whatever screen the person is on.
///
/// It is the same live player the viewer had: the viewer handed it to
/// [BackgroundPlaybackHost], and this just shows its texture. Expanding hands
/// it back to a new viewer, whose video grows out of this window (the window
/// stays up until the viewer has drawn the video where it is); closing ends
/// playback. Leaving the app while it plays
/// turns the app into Android's picture-in-picture window (the host arms that
/// through `PictureInPictureCoordinator`), so there is no state to carry over.
///
/// When it comes from the viewer closing, the window does not just appear: it
/// takes off from the rectangle the video was in and shrinks into its corner,
/// so the video itself seems to travel there (the viewer's usual Hero flight
/// back to the file manager's thumbnail is switched off for such a close).
///
/// The window tells [PictureInPictureCoordinator] where its video is, so that
/// when the app is left, Android animates *that* rectangle into the PiP window
/// (the video shrinking and moving into place, still playing) instead of
/// shrinking the whole app.
///
/// Mounted by [PictureInPictureLayer], above the whole navigator. That is also
/// why there are no tooltips here (a tooltip needs an `Overlay`, which lives
/// below this widget): the buttons carry semantic labels instead.
class FloatingVideoPlayer extends StatefulWidget {
  /// Whose video this shows: the viewer's own player while the viewer is still
  /// closing, the session's afterwards (it is the same object).
  final VideoPlaybackManager playbackManager;

  /// Where the video was on screen when the viewer started closing. Given, the
  /// window takes off from there and flies to its corner, instead of simply
  /// appearing in it. Only read when the window is created.
  final Rect? flyFrom;

  /// Reopens the full viewer on the running session.
  final VoidCallback onExpand;

  const FloatingVideoPlayer({
    super.key,
    required this.playbackManager,
    this.flyFrom,
    required this.onExpand,
  });

  @override
  State<FloatingVideoPlayer> createState() => _FloatingVideoPlayerState();
}

class _FloatingVideoPlayerState extends State<FloatingVideoPlayer> {
  static const double _margin = 12;
  static const double _cornerRadius = 14;

  /// The bottom corners rest this far above the bottom edge, clear of the
  /// floating action buttons and bars the screens underneath usually have.
  static const double _bottomLift = 72;
  static const Duration _snapDuration = Duration(milliseconds: 280);
  static const Duration _controlsTimeout = Duration(seconds: 3);

  // Which corner the window rests in; kept across items and across the app
  // being the picture-in-picture window (the widget stays mounted).
  bool _atRight = true;
  bool _atBottom = true;

  /// Top-left of the window while a finger is dragging it, else null.
  Offset? _dragTopLeft;

  bool _controlsVisible = true;
  Timer? _hideTimer;

  /// Where the window sits for its first frame when it flies in from the
  /// viewer; null once it has set off (or when it simply appears).
  Rect? _flightFrom;

  final GlobalKey _windowKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // So the host can tell the viewer where this window's video is when the
    // viewer takes the player back, and the viewer grows out of that spot.
    BackgroundPlaybackHost.instance.registerFloatingRect(this, _measureVideo);
    _flightFrom = widget.flyFrom;
    if (_flightFrom != null) {
      // A clean picture while it travels; a tap brings the controls up.
      _controlsVisible = false;
      // The first frame is drawn at the starting rectangle; the next one asks
      // for the corner, and the window animates there.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _flightFrom = null);
      });
    } else {
      _scheduleHide();
    }
  }

  @override
  void dispose() {
    BackgroundPlaybackHost.instance.unregisterFloatingRect(this);
    _hideTimer?.cancel();
    super.dispose();
  }

  /// Where the video is on screen right now, wherever the window is in a drag
  /// or an animation (logical pixels of the app's view); null when it cannot
  /// be told (not laid out, or the app is the PiP window).
  Rect? _measureVideo() {
    if (!mounted || PictureInPictureBridge.isInPictureInPicture.value) {
      return null;
    }
    final box = _windowKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    final window = MatrixUtils.transformRect(
      box.getTransformTo(null),
      Offset.zero & box.size,
    );
    final controller = widget.playbackManager.activeController;
    if (controller == null || controller.isDisposed) return window;
    return _fitVideo(window, controller.value.aspectRatio);
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_controlsTimeout, () {
      if (!mounted || !_controlsVisible) return;
      final controller = widget.playbackManager.activeController;
      final playing =
          controller != null &&
          !controller.isDisposed &&
          controller.value.isPlaying;
      // Paused: the controls stay, they are what resumes it.
      if (playing) setState(() => _controlsVisible = false);
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHide();
  }

  void _togglePlayPause(NativeVideoController controller) {
    if (controller.isDisposed) return;
    if (controller.value.isPlaying) {
      unawaited(controller.pause());
    } else {
      unawaited(controller.play());
    }
    _scheduleHide();
  }

  void _close() {
    unawaited(BackgroundPlaybackHost.instance.closeAndWait());
  }

  /// Tells the PiP coordinator where the video is (not the window: the bars
  /// around a video that does not fit the window's shape are not part of it).
  /// Reported after every layout, not only when it changes: the coordinator
  /// forgets the rectangle whenever the next item rebinds, and ignores a
  /// value it already has.
  void _reportVideoRect(BuildContext context, Rect window, double ratio) {
    final video = _fitVideo(window, ratio);
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      PictureInPictureCoordinator.instance.setSourceRect(
        BackgroundPlaybackHost.instance,
        video,
        devicePixelRatio: devicePixelRatio,
      );
    });
  }

  static Rect _fitVideo(Rect window, double ratio) {
    final windowRatio = window.width / window.height;
    if ((windowRatio - ratio).abs() < 0.001) return window;
    if (ratio > windowRatio) {
      final height = window.width / ratio;
      return Rect.fromLTWH(
        window.left,
        window.top + (window.height - height) / 2,
        window.width,
        height,
      );
    }
    final width = window.height * ratio;
    return Rect.fromLTWH(
      window.left + (window.width - width) / 2,
      window.top,
      width,
      window.height,
    );
  }

  /// Lets go of the window: it settles in the corner nearest to where it would
  /// have ended up, counting a little of the fling.
  void _snap({
    required Offset velocity,
    required Offset topLeft,
    required Size window,
    required Size screen,
  }) {
    final center =
        topLeft +
        Offset(window.width / 2, window.height / 2) +
        velocity * 0.12;
    setState(() {
      _atRight = center.dx > screen.width / 2;
      _atBottom = center.dy > screen.height / 2;
      _dragTopLeft = null;
    });
    _scheduleHide();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screen = constraints.biggest;
        return ValueListenableBuilder<NativeVideoController?>(
          valueListenable: widget.playbackManager.activeControllerNotifier,
          builder: (context, controller, _) {
            if (controller == null || controller.isDisposed) {
              return const SizedBox.shrink();
            }
            return ValueListenableBuilder<NativeVideoValue>(
              valueListenable: controller,
              builder: (context, value, _) =>
                  _buildWindow(context, screen, controller, value),
            );
          },
        );
      },
    );
  }

  Widget _buildWindow(
    BuildContext context,
    Size screen,
    NativeVideoController controller,
    NativeVideoValue value,
  ) {
    final media = MediaQuery.of(context);
    final padding = media.padding;
    final landscape = screen.width > screen.height;

    // The window's own shape stays within a sensible range (a tall phone clip
    // does not become a tower); the video is letterboxed inside it.
    final shape = value.aspectRatio.clamp(0.75, 2.2).toDouble();
    var width = landscape
        ? math.min(screen.width * 0.32, 320.0)
        : math.min(screen.width * 0.56, 280.0);
    width = math.max(width, 150.0);
    var height = width / shape;
    final maxHeight = screen.height * 0.5;
    if (height > maxHeight) {
      height = maxHeight;
      width = height * shape;
    }

    final minX = padding.left + _margin;
    final maxX = math.max(minX, screen.width - padding.right - _margin - width);
    final minY = padding.top + _margin;
    final bottomInset = math.max(padding.bottom, media.viewInsets.bottom);
    final maxY = math.max(minY, screen.height - bottomInset - _margin - height);

    final restX = _atRight ? maxX : minX;
    final restY = _atBottom ? math.max(minY, maxY - _bottomLift) : minY;
    final dragging = _dragTopLeft;
    final flight = _flightFrom;
    var left = dragging == null
        ? restX
        : dragging.dx.clamp(minX, maxX).toDouble();
    var top = dragging == null
        ? restY
        : dragging.dy.clamp(minY, maxY).toDouble();
    // First frame of a flight: exactly where the viewer's video is, at its
    // size; the frame after, the corner.
    if (flight != null) {
      left = flight.left;
      top = flight.top;
      width = flight.width;
      height = flight.height;
    }

    final showControls = _controlsVisible || !value.isPlaying;
    final windowSize = Size(width, height);

    // While a finger moves the window nothing is settled; the position it is
    // let go in is reported then.
    if (dragging == null && flight == null) {
      _reportVideoRect(
        context,
        Rect.fromLTWH(left, top, width, height),
        value.aspectRatio,
      );
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        AnimatedPositioned(
          duration: dragging == null ? _snapDuration : Duration.zero,
          curve: Curves.easeInOutCubic,
          left: left,
          top: top,
          width: width,
          height: height,
          // Square while it is still the full video, rounding as it shrinks.
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(end: flight != null ? 0.0 : _cornerRadius),
            duration: _snapDuration,
            curve: Curves.easeInOutCubic,
            builder: (context, radius, child) => Material(
              key: _windowKey,
              color: Colors.black,
              elevation: 10,
              shadowColor: Colors.black,
              borderRadius: BorderRadius.circular(radius),
              clipBehavior: Clip.antiAlias,
              child: child,
            ),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleControls,
              onPanStart: (_) {
                _hideTimer?.cancel();
                setState(() => _dragTopLeft = Offset(left, top));
              },
              onPanUpdate: (details) => setState(
                () => _dragTopLeft =
                    (_dragTopLeft ?? Offset(left, top)) + details.delta,
              ),
              onPanEnd: (details) => _snap(
                velocity: details.velocity.pixelsPerSecond,
                topLeft: Offset(left, top),
                window: windowSize,
                screen: screen,
              ),
              onPanCancel: () => setState(() => _dragTopLeft = null),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Center(
                    child: AspectRatio(
                      aspectRatio: value.aspectRatio,
                      child: NativeVideoPlayerView(controller: controller),
                    ),
                  ),
                  IgnorePointer(
                    ignoring: !showControls,
                    child: AnimatedOpacity(
                      opacity: showControls ? 1 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: _buildControls(context, controller, value),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _buildProgress(context, value),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildControls(
    BuildContext context,
    NativeVideoController controller,
    NativeVideoValue value,
  ) {
    final l10n = context.l10n;
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Color(0x66000000)),
        Positioned(
          top: 4,
          left: 4,
          child: _RoundButton(
            icon: Icons.open_in_full_rounded,
            label: l10n.floatingPlayerExpandTooltip,
            onPressed: widget.onExpand,
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: _RoundButton(
            icon: Icons.close_rounded,
            label: l10n.closeTooltip,
            onPressed: _close,
          ),
        ),
        Center(
          child: value.isBuffering
              ? const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : _RoundButton(
                  icon: value.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  label: value.isPlaying ? l10n.pauseLabel : l10n.playLabel,
                  size: 34,
                  onPressed: () => _togglePlayPause(controller),
                ),
        ),
      ],
    );
  }

  /// A thin bar along the bottom edge, drawn by hand: the stock linear
  /// indicator adds a track gap and an end dot that look wrong at this size.
  Widget _buildProgress(BuildContext context, NativeVideoValue value) {
    final total = value.duration.inMilliseconds;
    final fraction = total <= 0
        ? 0.0
        : (value.position.inMilliseconds / total).clamp(0.0, 1.0).toDouble();
    return SizedBox(
      height: 3,
      child: ColoredBox(
        color: const Color(0x40FFFFFF),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: FractionallySizedBox(
            widthFactor: fraction,
            heightFactor: 1,
            child: ColoredBox(color: Theme.of(context).colorScheme.primary),
          ),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final double size;

  const _RoundButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.size = 20,
  });

  @override
  Widget build(BuildContext context) {
    // No tooltip (there is no Overlay above this widget); the icon's semantic
    // label is what a screen reader announces for the button.
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, semanticLabel: label),
      iconSize: size,
      color: Colors.white,
      style: IconButton.styleFrom(
        backgroundColor: Colors.black45,
        padding: const EdgeInsets.all(6),
        minimumSize: const Size(32, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}
