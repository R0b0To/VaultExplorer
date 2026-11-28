import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/core/widgets/desktop_window_frame.dart';
import 'package:vaultexplorer/core/windowing/app_windows.dart';
import 'package:vaultexplorer/core/windowing/desktop_windowing.dart';
import 'package:vaultexplorer/core/windowing/secondary_windows.dart';
import 'package:vaultexplorer/core/windowing/window_caption.dart';
import 'package:vaultexplorer/features/browser/viewer/background_playback/background_playback_host.dart';
import 'package:vaultexplorer/features/browser/viewer/native_video_controller.dart';
import 'package:vaultexplorer/features/browser/viewer/video_playback_manager.dart';

/// The floating video player on Linux and Windows: a native window of its own
/// instead of a small panel drawn over the app.
///
///  * It can be dragged anywhere on any screen, outside the app too: press on
///    the video and move.
///  * Its edges and corners resize it. On Windows the shape of the video is
///    kept while doing so, and the window stays above every other window, as a
///    picture-in-picture player does. (The Linux window manager owns both of
///    those; there the window is an ordinary one that is resized freely.)
///  * On Windows it has no title bar: just the video, with the controls fading
///    in while the pointer is over it.
///
/// It shows the session [BackgroundPlaybackHost] holds for the floating player
/// (what is left of the viewer when it is closed while a video plays). The
/// window opens when there is such a session with its video showing and closes
/// when there is none, or the video turns audio only. Closing the window itself
/// ends playback, as the close button of the in-app panel does.
///
/// Where native windows are not available (see [isAvailable]) nothing here
/// runs, and `FloatingVideoPlayer` is drawn over the app as before.
class DesktopPipWindowController {
  DesktopPipWindowController() {
    final host = BackgroundPlaybackHost.instance;
    host.floatingSession.addListener(_sync);
    host.floatingAudioOnly.addListener(_sync);
    _sync();
  }

  /// Whether the floating player gets a window of its own in this run: Linux
  /// or Windows, with native windows working.
  static bool get isAvailable =>
      DesktopWindowing.isSupportedPlatform && DesktopWindowing.ensureReady();

  static const String windowKey = 'pip-player';

  /// The window's width when it opens (its height follows the video's shape).
  static const double initialWidth = 420;

  static const double minWidth = 240;
  static const double minHeight = 135;

  SecondaryWindowEntry? _entry;
  VideoPlaybackManager? _shownManager;
  bool _opening = false;
  bool _disposed = false;

  VideoPlaybackManager? get _wantedManager {
    final host = BackgroundPlaybackHost.instance;
    if (host.floatingAudioOnly.value) return null;
    return host.floatingSession.value?.playbackManager;
  }

  void _sync() {
    if (_disposed) return;
    final wanted = _wantedManager;
    if (wanted == null) {
      _closeWindow();
      return;
    }
    if (_entry != null && !identical(_shownManager, wanted)) {
      // Another player took over: a fresh window for it.
      _closeWindow();
    }
    if (_entry == null) unawaited(_openWindow(wanted));
  }

  Future<void> _openWindow(VideoPlaybackManager manager) async {
    if (_opening) return;
    _opening = true;
    // A native window must not be created inside a frame, and a notifier
    // that changed may well have been.
    await SecondaryWindows.untilBetweenFrames();
    _opening = false;
    if (_disposed || _entry != null) return;
    // Things may have moved on while waiting.
    if (!identical(_wantedManager, manager)) {
      _sync();
      return;
    }

    final controller = manager.activeController;
    final value = (controller == null || controller.isDisposed)
        ? null
        : controller.value;
    final ratio = value != null && value.size.width > 0 && value.size.height > 0
        ? value.aspectRatio
        : 16 / 9;
    final width = initialWidth;
    final opened = SecondaryWindows.instance.open(
      key: windowKey,
      title: manager.currentFileName ?? '',
      size: Size(width, width / ratio),
      constraints: const BoxConstraints(
        minWidth: minWidth,
        minHeight: minHeight,
      ),
      builder: (_) => DesktopPipPage(playbackManager: manager),
      onCreated: (entry) {
        unawaited(dockWindowBottomRight(entry.viewId));
        unawaited(setWindowAlwaysOnTop(entry.viewId, true));
      },
    );
    if (!opened) return;
    final entry = SecondaryWindows.instance.entryFor(windowKey);
    _entry = entry;
    _shownManager = manager;
    if (entry != null) {
      unawaited(entry.closed.then((_) => _onWindowClosed(entry)));
    }
  }

  void _closeWindow() {
    final entry = _entry;
    if (entry == null) return;
    // Forget it first, so this is not taken for the person closing it.
    _entry = null;
    _shownManager = null;
    SecondaryWindows.instance.close(windowKey);
  }

  /// The person closed the window (its own close button, the taskbar, Alt+F4):
  /// the video must not carry on behind their back.
  void _onWindowClosed(SecondaryWindowEntry entry) {
    if (!identical(entry, _entry)) return;
    _entry = null;
    _shownManager = null;
    if (_disposed) return;
    unawaited(BackgroundPlaybackHost.instance.closeAndWait());
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final host = BackgroundPlaybackHost.instance;
    host.floatingSession.removeListener(_sync);
    host.floatingAudioOnly.removeListener(_sync);
    if (_entry != null) {
      _entry = null;
      SecondaryWindows.instance.close(windowKey);
    }
  }
}

/// The content of the picture-in-picture window: the video edge to edge, and
/// over it, while the pointer is on the window (or the video is paused), the
/// controls:
///
///  * audio only, expand and close at the top;
///  * back 10 seconds, play / pause and forward 10 seconds in the middle;
///  * at the bottom a timeline to click or drag (the mouse wheel over it moves
///    the video too), the clock ("1:04:32 / 1:18:50"), previous / next item
///    where there are some, and mute.
///
/// Pressing the video and moving drags the whole window; a click on it plays
/// or pauses.
class DesktopPipPage extends StatefulWidget {
  const DesktopPipPage({super.key, required this.playbackManager});

  final VideoPlaybackManager playbackManager;

  @override
  State<DesktopPipPage> createState() => _DesktopPipPageState();
}

class _DesktopPipPageState extends State<DesktopPipPage> {
  static const Duration _fade = Duration(milliseconds: 150);
  static const Duration _skipStep = Duration(seconds: 10);

  bool _hovering = false;
  bool _stepping = false;

  /// The volume to go back to when the sound is switched on again; null while
  /// the sound is on.
  int? _volumeBeforeMute;
  double _lastAspectRatio = 16 / 9;
  double? _appliedRatio;
  String? _lastTitle;
  int? _viewId;
  Map<String, Object?>? _windowArgs;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _viewId = View.maybeOf(context)?.viewId;
    _windowArgs = windowChannelArgsFor(context);
  }

  void _syncWindow(NativeVideoValue value) {
    if (!mounted) return;
    if (value.size.width > 0 && value.size.height > 0) {
      _lastAspectRatio = value.aspectRatio;
    }
    final ratio = _lastAspectRatio;
    final viewId = _viewId;
    if (viewId != null && _appliedRatio != ratio) {
      // The window takes the shape of the video (the next item may differ),
      // and keeps it while it is resized.
      _appliedRatio = ratio;
      unawaited(setWindowAspectRatio(viewId, ratio, reshape: true));
    }
    final title = widget.playbackManager.currentFileName ?? '';
    if (title != _lastTitle) {
      _lastTitle = title;
      SecondaryWindowScope.maybeOf(context)?.setTitle(title);
    }
  }

  Future<void> _startDragging() async {
    try {
      await kWindowChannel.invokeMethod<void>('startDragging', _windowArgs);
    } on MissingPluginException {
      // A host with a native title bar: the title bar drags the window.
    } on PlatformException {
      // The window may be gone already.
    }
  }

  void _togglePlayPause(NativeVideoController controller) {
    if (controller.isDisposed) return;
    if (controller.value.isPlaying) {
      unawaited(controller.pause());
    } else {
      unawaited(controller.play());
    }
  }

  Future<void> _step(int direction) async {
    if (_stepping) return;
    _stepping = true;
    try {
      await BackgroundPlaybackHost.instance.stepItem(direction);
    } finally {
      _stepping = false;
    }
  }

  /// The clock buttons: [direction] -1 / 1 moves the video by [_skipStep].
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
  }

  void _toggleMute(NativeVideoController controller) {
    if (controller.isDisposed) return;
    final before = _volumeBeforeMute;
    if (before == null) {
      _volumeBeforeMute = controller.currentVolume > 0
          ? controller.currentVolume
          : 100;
      unawaited(controller.setVolume(0));
    } else {
      _volumeBeforeMute = null;
      unawaited(controller.setVolume(before));
    }
    setState(() {});
  }

  void _expand() {
    BackgroundPlaybackHost.instance.expand();
    final main = AppWindows.instance.mainViewId;
    if (main != null) unawaited(bringWindowForward(main));
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black,
      // The window has no caption row of its own: the video fills it. (Where
      // the window keeps its native title bar there is nothing to hide.)
      child: DesktopCaptionHider(
        hidden: true,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovering = true),
          onExit: (_) => setState(() => _hovering = false),
          child: ValueListenableBuilder<NativeVideoController?>(
            valueListenable: widget.playbackManager.activeControllerNotifier,
            builder: (context, controller, _) {
              if (controller == null || controller.isDisposed) {
                return const SizedBox.expand();
              }
              return ValueListenableBuilder<NativeVideoValue>(
                valueListenable: controller,
                builder: (context, value, _) {
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => _syncWindow(value),
                  );
                  return _buildContent(context, controller, value);
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    NativeVideoController controller,
    NativeVideoValue value,
  ) {
    final host = BackgroundPlaybackHost.instance;
    final showControls = _hovering || !value.isPlaying;
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: AspectRatio(
            aspectRatio: _lastAspectRatio,
            child: NativeVideoPlayerView(controller: controller),
          ),
        ),
        // Press and move drags the window; a click plays or pauses.
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) => unawaited(_startDragging()),
          onTap: () => _togglePlayPause(controller),
          onDoubleTap: _expand,
        ),
        IgnorePointer(
          ignoring: !showControls,
          child: AnimatedOpacity(
            opacity: showControls ? 1 : 0,
            duration: _fade,
            child: _buildControls(
              context,
              controller,
              value,
              canPrevious: host.canStepPrevious,
              canNext: host.canStepNext,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildControls(
    BuildContext context,
    NativeVideoController controller,
    NativeVideoValue value, {
    required bool canPrevious,
    required bool canNext,
  }) {
    final l10n = context.l10n;
    final host = BackgroundPlaybackHost.instance;
    final loading = value.isBuffering || !value.isInitialized;
    final muted = _volumeBeforeMute != null;
    const timeStyle = TextStyle(
      color: Colors.white,
      fontSize: 12,
      fontWeight: FontWeight.w500,
      fontFeatures: [FontFeature.tabularFigures()],
      shadows: [Shadow(blurRadius: 4, color: Colors.black87)],
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        // The scrims only darken; they must not take the clicks meant for the
        // video under them.
        const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x99000000), Color(0x00000000), Color(0xB3000000)],
                stops: [0.0, 0.45, 1.0],
              ),
            ),
          ),
        ),
        Positioned(
          top: 6,
          left: 8,
          right: 8,
          child: Row(
            children: [
              _PipButton(
                icon: Icons.headphones_rounded,
                tooltip: l10n.floatingPlayerAudioOnly,
                onPressed: () => host.setAudioOnly(true),
              ),
              const Spacer(),
              _PipButton(
                icon: Icons.open_in_full_rounded,
                tooltip: l10n.floatingPlayerExpandTooltip,
                onPressed: _expand,
              ),
              const SizedBox(width: 4),
              _PipButton(
                icon: Icons.close_rounded,
                tooltip: l10n.closeTooltip,
                onPressed: () => unawaited(host.closeAndWait()),
              ),
            ],
          ),
        ),
        // Middle: back 10 seconds, play / pause, forward 10 seconds.
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PipButton(
                icon: Icons.replay_10_rounded,
                tooltip: '-${_skipStep.inSeconds}s',
                onPressed: () => _skip(controller, -1),
                iconSize: 24,
                box: 38,
              ),
              const SizedBox(width: 12),
              loading
                  ? const SizedBox(
                      width: 48,
                      height: 48,
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
                  : _PipButton(
                      icon: value.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      tooltip: value.isPlaying ? l10n.pauseLabel : l10n.playLabel,
                      onPressed: () => _togglePlayPause(controller),
                      iconSize: 30,
                      box: 48,
                    ),
              const SizedBox(width: 12),
              _PipButton(
                icon: Icons.forward_10_rounded,
                tooltip: '+${_skipStep.inSeconds}s',
                onPressed: () => _skip(controller, 1),
                iconSize: 24,
                box: 38,
              ),
            ],
          ),
        ),
        // Bottom: the timeline, and under it the clock and the small buttons.
        Positioned(
          left: 12,
          right: 12,
          bottom: 6,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Timeline(controller: controller, value: value),
              Row(
                children: [
                  Expanded(
                    child: _Clock(value: value, style: timeStyle),
                  ),
                  if (canPrevious)
                    _PipButton(
                      icon: Icons.skip_previous_rounded,
                      tooltip: l10n.previousTooltip,
                      onPressed: () => unawaited(_step(-1)),
                      iconSize: 18,
                      box: 28,
                      plain: true,
                    ),
                  if (canNext)
                    _PipButton(
                      icon: Icons.skip_next_rounded,
                      tooltip: l10n.nextTooltip,
                      onPressed: () => unawaited(_step(1)),
                      iconSize: 18,
                      box: 28,
                      plain: true,
                    ),
                  _PipButton(
                    icon: muted
                        ? Icons.volume_off_rounded
                        : Icons.volume_up_rounded,
                    tooltip: muted ? l10n.unmuteTooltip : l10n.muteTooltip,
                    onPressed: () => _toggleMute(controller),
                    iconSize: 18,
                    box: 28,
                    plain: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A small round button over the video.
class _PipButton extends StatelessWidget {
  const _PipButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.iconSize = 18,
    this.box = 34,
    this.plain = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final double iconSize;
  final double box;

  /// No round backdrop: a bare icon (the small buttons under the timeline).
  final bool plain;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon),
      iconSize: iconSize,
      color: Colors.white,
      style: IconButton.styleFrom(
        backgroundColor: plain ? Colors.transparent : Colors.black45,
        padding: EdgeInsets.zero,
        fixedSize: Size(box, box),
        minimumSize: Size(box, box),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

/// "1:04:32 / 1:18:50".
class _Clock extends StatelessWidget {
  const _Clock({required this.value, required this.style});

  final NativeVideoValue value;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final position = formatClockDuration(value.position);
    final total = value.duration > Duration.zero
        ? formatClockDuration(value.duration)
        : '--:--';
    return Text(
      '$position / $total',
      style: style,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// The timeline: a slim bar with a thumb that is dragged (or clicked) to seek.
/// The mouse wheel over it moves the video too (scroll up forward, down
/// back, [wheelStep] a notch).
///
/// While the thumb is held the video follows it (seeks are throttled, so the
/// player is not asked for every pixel), and the final position is applied
/// when it is let go.
class _Timeline extends StatefulWidget {
  const _Timeline({required this.controller, required this.value});

  final NativeVideoController controller;
  final NativeVideoValue value;

  static const Duration wheelStep = Duration(seconds: 5);

  @override
  State<_Timeline> createState() => _TimelineState();
}

class _TimelineState extends State<_Timeline> {
  static const Duration _seekEvery = Duration(milliseconds: 150);

  double? _dragFraction;
  DateTime _lastSeekAt = DateTime.fromMillisecondsSinceEpoch(0);

  Duration get _total => widget.value.duration;

  void _seek(double fraction) {
    final controller = widget.controller;
    if (controller.isDisposed || _total <= Duration.zero) return;
    unawaited(controller.seekTo(_total * fraction.clamp(0.0, 1.0)));
  }

  void _onWheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || _total <= Duration.zero) return;
    final forward = event.scrollDelta.dy < 0;
    final step = _Timeline.wheelStep * (forward ? 1 : -1);
    var target = widget.value.position + step;
    if (target < Duration.zero) target = Duration.zero;
    if (target > _total) target = _total;
    unawaited(widget.controller.seekTo(target));
  }

  @override
  Widget build(BuildContext context) {
    final total = _total.inMilliseconds;
    final playing = total <= 0
        ? 0.0
        : (widget.value.position.inMilliseconds / total)
              .clamp(0.0, 1.0)
              .toDouble();
    final shown = _dragFraction ?? playing;
    final primary = Theme.of(context).colorScheme.primary;
    return Listener(
      onPointerSignal: _onWheel,
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 3,
          activeTrackColor: primary,
          inactiveTrackColor: const Color(0x59FFFFFF),
          thumbColor: primary,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
          overlayShape: SliderComponentShape.noOverlay,
          trackShape: const RoundedRectSliderTrackShape(),
        ),
        child: SizedBox(
          height: 22,
          child: Slider(
            value: shown,
            onChangeStart: (_) => setState(() => _dragFraction = shown),
            onChanged: total <= 0
                ? null
                : (fraction) {
                    setState(() => _dragFraction = fraction);
                    final now = DateTime.now();
                    if (now.difference(_lastSeekAt) >= _seekEvery) {
                      _lastSeekAt = now;
                      _seek(fraction);
                    }
                  },
            onChangeEnd: (fraction) {
              _seek(fraction);
              setState(() => _dragFraction = null);
            },
          ),
        ),
      ),
    );
  }
}
