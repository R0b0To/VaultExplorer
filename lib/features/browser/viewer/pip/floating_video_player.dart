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
/// Gestures: drag to move (it settles in the nearest corner), pinch to resize
/// (the size is remembered), tap to show or hide the controls, double-tap the
/// left or right edge to skip back or forward 10 seconds.
///
/// Controls, the same as the picture-in-picture window's plus the window's own:
/// previous / play-pause / next, audio only, expand and close. Audio only stops
/// the video being decoded or drawn while the sound carries on, and leaves a
/// small chip in the corner that brings the video back.
///
/// It is the same live player the viewer had: the viewer handed it to
/// [BackgroundPlaybackHost], and this just shows its texture. Expanding hands
/// it back to a new viewer, whose video grows out of this window (the window
/// stays up until the viewer has drawn the video where it is); closing ends
/// playback. Leaving the app while it plays turns the app into Android's
/// picture-in-picture window (the host arms that through
/// `PictureInPictureCoordinator`), so there is no state to carry over.
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
  static const double _chipSize = 48;

  // Pinch limits. The window is also kept inside the screen and its width never
  // goes under [_minWidth], whatever the factor says.
  static const double _minWidth = 130;
  static const double _minSizeFactor = 0.6;
  static const double _maxSizeFactor = 2.2;

  /// Below this height there is no room for previous / next between the row of
  /// buttons at the top and the progress bar; play / pause alone remains.
  static const double _compactHeight = 100;

  static const Duration _snapDuration = Duration(milliseconds: 280);
  static const Duration _controlsTimeout = Duration(seconds: 3);
  static const Duration _skipStep = Duration(seconds: 10);

  // What the person chose, kept for the next window too (a session ends, the
  // next video floats in the same corner at the same size).
  static bool _lastAtRight = true;
  static bool _lastAtBottom = true;
  static double _lastSizeFactor = 1.0;

  // Which corner the window rests in, and how big it is relative to the
  // default; kept across items and across the app being the PiP window (the
  // widget stays mounted).
  bool _atRight = _lastAtRight;
  bool _atBottom = _lastAtBottom;
  double _sizeFactor = _lastSizeFactor;

  /// While a finger is on the window: its centre, and the size factor the
  /// pinch started from. Null centre when nothing is touching it.
  Offset? _dragCenter;
  double _scaleStartFactor = 1.0;

  bool _controlsVisible = true;
  Timer? _hideTimer;

  /// A double-tap skip being acknowledged on screen: -1 back, 1 forward, 0
  /// none; and how many seconds the quick taps have added up to.
  int _skipDirection = 0;
  int _skipSeconds = 0;
  Timer? _skipTimer;

  bool _stepping = false;

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
    _skipTimer?.cancel();
    super.dispose();
  }

  /// Where the video is on screen right now, wherever the window is in a drag
  /// or an animation (logical pixels of the app's view); null when it cannot
  /// be told (not laid out, only the audio-only chip showing, or the app is
  /// the PiP window).
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

  /// Previous / next video. One step at a time: a second tap while the first
  /// is still switching would only queue another switch behind it.
  Future<void> _step(int direction) async {
    if (_stepping) return;
    _stepping = true;
    try {
      await BackgroundPlaybackHost.instance.stepItem(direction);
    } finally {
      _stepping = false;
    }
    if (mounted) _scheduleHide();
  }

  /// Double-tap on the left / right edge: [direction] -1 / 1 moves the video
  /// by [_skipStep], and the number on screen adds up while the taps keep
  /// coming.
  void _skip(NativeVideoController controller, int direction) {
    if (controller.isDisposed) return;
    final value = controller.value;
    if (!value.isInitialized) return;
    var target = value.position + _skipStep * direction;
    if (target < Duration.zero) target = Duration.zero;
    if (value.duration > Duration.zero && target > value.duration) {
      target = value.duration;
    }
    unawaited(controller.seekTo(target));
    setState(() {
      _skipSeconds = _skipDirection == direction
          ? _skipSeconds + _skipStep.inSeconds
          : _skipStep.inSeconds;
      _skipDirection = direction;
    });
    _skipTimer?.cancel();
    _skipTimer = Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      setState(() {
        _skipDirection = 0;
        _skipSeconds = 0;
      });
    });
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

  /// Fingers off: the window settles in the corner nearest to where it would
  /// have ended up, counting a little of the fling, at the size the pinch left
  /// it, and both are remembered.
  void _finishGesture({
    required Offset velocity,
    required Size screen,
    required double sizeFactor,
  }) {
    final center = (_dragCenter ?? screen.center(Offset.zero)) + velocity * 0.12;
    setState(() {
      _atRight = center.dx > screen.width / 2;
      _atBottom = center.dy > screen.height / 2;
      _sizeFactor = sizeFactor.clamp(_minSizeFactor, _maxSizeFactor).toDouble();
      _dragCenter = null;
    });
    _lastAtRight = _atRight;
    _lastAtBottom = _atBottom;
    _lastSizeFactor = _sizeFactor;
    _scheduleHide();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screen = constraints.biggest;
        return ValueListenableBuilder<bool>(
          valueListenable: BackgroundPlaybackHost.instance.floatingAudioOnly,
          builder: (context, audioOnly, _) {
            if (audioOnly) return _buildAudioOnlyChip(context, screen);
            return ValueListenableBuilder<NativeVideoController?>(
              valueListenable: widget.playbackManager.activeControllerNotifier,
              builder: (context, controller, _) {
                if (controller == null || controller.isDisposed) {
                  return const SizedBox.shrink();
                }
                // Asked once per item, not per frame of the video: the
                // answer only changes when the item does.
                final host = BackgroundPlaybackHost.instance;
                final canPrevious = host.canStepPrevious;
                final canNext = host.canStepNext;
                return ValueListenableBuilder<NativeVideoValue>(
                  valueListenable: controller,
                  builder: (context, value, _) => _buildWindow(
                    context,
                    screen,
                    controller,
                    value,
                    canPrevious: canPrevious,
                    canNext: canNext,
                  ),
                );
              },
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
    NativeVideoValue value, {
    required bool canPrevious,
    required bool canNext,
  }) {
    final media = MediaQuery.of(context);
    final padding = media.padding;
    final landscape = screen.width > screen.height;

    // The window's own shape stays within a sensible range (a tall phone clip
    // does not become a tower); the video is letterboxed inside it.
    final shape = value.aspectRatio.clamp(0.75, 2.2).toDouble();
    var baseWidth = landscape
        ? math.min(screen.width * 0.32, 320.0)
        : math.min(screen.width * 0.56, 280.0);
    baseWidth = math.max(baseWidth, 150.0);
    final widest = math.max(
      _minWidth,
      math.min(screen.width - padding.horizontal - 2 * _margin, 560.0),
    );
    var width = (baseWidth * _sizeFactor).clamp(_minWidth, widest).toDouble();
    var height = width / shape;
    final maxHeight = screen.height * 0.6;
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
    final dragCenter = _dragCenter;
    final flight = _flightFrom;
    var left = dragCenter == null
        ? restX
        : (dragCenter.dx - width / 2).clamp(minX, maxX).toDouble();
    var top = dragCenter == null
        ? restY
        : (dragCenter.dy - height / 2).clamp(minY, maxY).toDouble();
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
    // What the size is, as a factor of the default, once the screen has had its
    // say: what a pinch is measured from and leaves behind.
    final effectiveFactor = width / baseWidth;

    // While a finger moves the window nothing is settled; the position it is
    // let go in is reported then.
    if (dragCenter == null && flight == null) {
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
          duration: dragCenter == null ? _snapDuration : Duration.zero,
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
            // One recogniser for both moving and pinching; taps and double
            // taps are the zones' (below), and they only win when nothing
            // moves.
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onScaleStart: (_) {
                _hideTimer?.cancel();
                setState(() {
                  _sizeFactor = effectiveFactor;
                  _scaleStartFactor = effectiveFactor;
                  _dragCenter = Offset(left + width / 2, top + height / 2);
                });
              },
              onScaleUpdate: (details) => setState(() {
                _dragCenter =
                    (_dragCenter ?? Offset(left + width / 2, top + height / 2)) +
                    details.focalPointDelta;
                _sizeFactor = (_scaleStartFactor * details.scale)
                    .clamp(_minSizeFactor, _maxSizeFactor)
                    .toDouble();
              }),
              onScaleEnd: (details) {
                // One finger lifting while another stays down ends this
                // gesture and starts the next straight away.
                if (details.pointerCount > 0) return;
                _finishGesture(
                  velocity: details.velocity.pixelsPerSecond,
                  screen: screen,
                  sizeFactor: effectiveFactor,
                );
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Center(
                    child: AspectRatio(
                      aspectRatio: value.aspectRatio,
                      child: NativeVideoPlayerView(controller: controller),
                    ),
                  ),
                  _buildTapZones(controller),
                  IgnorePointer(
                    ignoring: !showControls,
                    child: AnimatedOpacity(
                      opacity: showControls ? 1 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: _buildControls(
                        context,
                        controller,
                        value,
                        windowSize,
                        canPrevious: canPrevious,
                        canNext: canNext,
                      ),
                    ),
                  ),
                  _buildSkipFeedback(),
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

  /// Three vertical zones over the video. A tap anywhere shows or hides the
  /// controls; a double tap in the outer two skips back / forward. The middle
  /// has no double tap, so a tap there answers at once (a zone with a double
  /// tap has to wait out the second tap before it knows it was a single one).
  Widget _buildTapZones(NativeVideoController controller) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 3,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleControls,
            onDoubleTap: () => _skip(controller, -1),
          ),
        ),
        Expanded(
          flex: 4,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleControls,
          ),
        ),
        Expanded(
          flex: 3,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleControls,
            onDoubleTap: () => _skip(controller, 1),
          ),
        ),
      ],
    );
  }

  Widget _buildControls(
    BuildContext context,
    NativeVideoController controller,
    NativeVideoValue value,
    Size windowSize, {
    required bool canPrevious,
    required bool canNext,
  }) {
    final l10n = context.l10n;
    final host = BackgroundPlaybackHost.instance;
    final compact = windowSize.height < _compactHeight;

    Widget slot(Widget? child) => SizedBox(width: 30, height: 30, child: child);

    return Stack(
      fit: StackFit.expand,
      children: [
        // The scrim only darkens; it must not take the taps meant for the
        // zones under it.
        const IgnorePointer(child: ColoredBox(color: Color(0x66000000))),
        Positioned(
          top: 3,
          left: 3,
          child: _RoundButton(
            icon: Icons.open_in_full_rounded,
            label: l10n.floatingPlayerExpandTooltip,
            onPressed: widget.onExpand,
          ),
        ),
        Positioned(
          top: 3,
          right: 3,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _RoundButton(
                icon: Icons.headphones_rounded,
                label: l10n.floatingPlayerAudioOnly,
                onPressed: () => host.setAudioOnly(true),
              ),
              const SizedBox(width: 3),
              _RoundButton(
                icon: Icons.close_rounded,
                label: l10n.closeTooltip,
                onPressed: _close,
              ),
            ],
          ),
        ),
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!compact) ...[
                slot(
                  canPrevious
                      ? _RoundButton(
                          icon: Icons.skip_previous_rounded,
                          label: l10n.previousTooltip,
                          size: 20,
                          box: 30,
                          onPressed: () => unawaited(_step(-1)),
                        )
                      : null,
                ),
                const SizedBox(width: 4),
              ],
              value.isBuffering
                  ? const SizedBox(
                      width: 40,
                      height: 40,
                      child: Center(
                        child: SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    )
                  : _RoundButton(
                      icon: value.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      label: value.isPlaying ? l10n.pauseLabel : l10n.playLabel,
                      size: 28,
                      box: 40,
                      onPressed: () => _togglePlayPause(controller),
                    ),
              if (!compact) ...[
                const SizedBox(width: 4),
                slot(
                  canNext
                      ? _RoundButton(
                          icon: Icons.skip_next_rounded,
                          label: l10n.nextTooltip,
                          size: 20,
                          box: 30,
                          onPressed: () => unawaited(_step(1)),
                        )
                      : null,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// The "10" that shows on the side that was double-tapped.
  Widget _buildSkipFeedback() {
    if (_skipDirection == 0) return const SizedBox.shrink();
    final forward = _skipDirection > 0;
    const shadows = <Shadow>[Shadow(blurRadius: 6, color: Colors.black87)];
    return IgnorePointer(
      child: Align(
        alignment: Alignment(forward ? 0.62 : -0.62, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              forward ? Icons.fast_forward_rounded : Icons.fast_rewind_rounded,
              color: Colors.white,
              size: 28,
              shadows: shadows,
            ),
            Text(
              '$_skipSeconds',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                shadows: shadows,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Audio only: no video to show, so just a small chip where the window was,
  /// which brings the video back.
  Widget _buildAudioOnlyChip(BuildContext context, Size screen) {
    final media = MediaQuery.of(context);
    final padding = media.padding;
    final scheme = Theme.of(context).colorScheme;
    final minX = padding.left + _margin;
    final maxX = math.max(
      minX,
      screen.width - padding.right - _margin - _chipSize,
    );
    final minY = padding.top + _margin;
    final bottomInset = math.max(padding.bottom, media.viewInsets.bottom);
    final maxY = math.max(
      minY,
      screen.height - bottomInset - _margin - _chipSize,
    );
    final left = _atRight ? maxX : minX;
    final top = _atBottom ? math.max(minY, maxY - _bottomLift) : minY;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        AnimatedPositioned(
          duration: _snapDuration,
          curve: Curves.easeInOutCubic,
          left: left,
          top: top,
          width: _chipSize,
          height: _chipSize,
          child: Material(
            color: scheme.primaryContainer,
            elevation: 8,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => BackgroundPlaybackHost.instance.setAudioOnly(false),
              child: Center(
                child: Icon(
                  Icons.headphones_rounded,
                  color: scheme.onPrimaryContainer,
                  semanticLabel: context.l10n.floatingPlayerShowVideo,
                ),
              ),
            ),
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

  /// The icon's size, and the side of the round button around it.
  final double size;
  final double box;

  const _RoundButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.size = 17,
    this.box = 26,
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
        padding: EdgeInsets.zero,
        fixedSize: Size(box, box),
        minimumSize: Size(box, box),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}
