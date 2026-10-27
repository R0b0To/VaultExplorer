import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

/// Share of the screen, along the drag axis, that the content has to be pulled
/// before letting go closes the viewer. This matches the distance at which the
/// backdrop and controls finish fading.
const double _kDismissDistanceFraction = 0.05;

/// Release speed (logical px/s along the drag axis) that closes the viewer no
/// matter how far it was pulled.
const double _kDismissFlingVelocity = 700.0;

/// Maximum amount the dragged media surface shrinks while it follows a finger.
const double _kDismissScaleAmount = 0.08;

/// Fade the backdrop and controls over a short initial pull, before the image
/// reaches the distance needed to dismiss.
const double _kFadeDistanceFraction = 0.1;

/// A drag only counts once it has travelled this many times further along its
/// axis than across it, so a diagonal scribble never closes the viewer.
const double _kAxisDominance = 1.15;

/// Recognizes a one-finger drag that starts along [axis], then reports the
/// complete two-dimensional movement so the media can follow the finger.
///
/// This is deliberately a plain [OneSequenceGestureRecognizer]: the viewer
/// needs a direction filter (down only, or either way) that stock recognizers
/// cannot express, and it must give the touch to the playlist pager, zoom/pan
/// handling and brightness/volume strips whenever one of them is the better
/// owner.
class SwipeDismissRecognizer extends OneSequenceGestureRecognizer {
  SwipeDismissRecognizer({required this.canStart, super.debugOwner})
    : super(supportedDevices: const {PointerDeviceKind.touch});

  /// Asked when a finger lands. `false` leaves that touch entirely alone.
  bool Function() canStart;

  /// Axis along which the dismiss gesture has to begin.
  Axis axis = Axis.vertical;

  /// Whether the drag may start in either direction along [axis]. When `false`
  /// only the positive direction (down for a vertical axis) is accepted.
  bool bothDirections = false;

  VoidCallback? onStart;

  /// Full two-dimensional movement since the finger first landed.
  ValueChanged<Offset>? onUpdate;

  /// Fired on release with the velocity along [axis] in logical px/s.
  ValueChanged<double>? onEnd;

  /// Fired when an accepted drag is interrupted (second finger, cancel).
  VoidCallback? onCancel;

  int? _pointer;
  Offset _origin = Offset.zero;
  Offset _moved = Offset.zero;
  bool _claimed = false;
  bool _accepted = false;
  VelocityTracker? _velocity;

  double _primaryOf(Offset o) => axis == Axis.vertical ? o.dy : o.dx;
  double _crossOf(Offset o) => axis == Axis.vertical ? o.dx : o.dy;

  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      canStart() && super.isPointerAllowed(event);

  @override
  void addPointer(PointerDownEvent event) {
    if (_pointer != null && event.pointer != _pointer) {
      // A second finger is a pinch, never a dismiss.
      if (_accepted) {
        _complete(velocity: null);
      } else {
        resolve(GestureDisposition.rejected);
      }
      return;
    }
    super.addPointer(event);
  }

  @override
  void addAllowedPointer(PointerDownEvent event) {
    startTrackingPointer(event.pointer, event.transform);
    _pointer = event.pointer;
    _origin = event.position;
    _moved = Offset.zero;
    _claimed = false;
    _accepted = false;
    _velocity = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.position);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event.pointer != _pointer) return;

    if (event is PointerMoveEvent) {
      _velocity?.addPosition(event.timeStamp, event.position);
      _moved = event.position - _origin;
      if (_accepted) {
        onUpdate?.call(_moved);
      } else {
        _consider();
      }
    } else if (event is PointerUpEvent) {
      _velocity?.addPosition(event.timeStamp, event.position);
      if (_accepted) {
        final velocity =
            _velocity?.getVelocity().pixelsPerSecond ?? Offset.zero;
        _complete(velocity: _primaryOf(velocity));
      } else {
        resolve(GestureDisposition.rejected);
      }
    } else if (event is PointerCancelEvent) {
      if (_accepted) {
        _complete(velocity: null);
      } else {
        resolve(GestureDisposition.rejected);
      }
    }
  }

  /// Decides, before the drag is accepted, whether it is ours, someone
  /// else's, or still undecided.
  void _consider() {
    // The normal touch slop is tuned for broad platform gestures. This one
    // needs to react earlier so it can beat the viewer's scale recognizer.
    final slop =
        computeHitSlop(PointerDeviceKind.touch, gestureSettings) * 0.65;
    final primary = _primaryOf(_moved);
    final cross = _crossOf(_moved).abs();

    // A small initial move in the wrong direction can be hand jitter. Reject
    // only once the finger has clearly committed to that direction.
    if (!bothDirections && primary < -slop && primary.abs() > cross) {
      resolve(GestureDisposition.rejected);
      return;
    }
    // Mostly across the axis: that is the pager's or the seek gesture's.
    if (cross > slop && cross >= primary.abs()) {
      resolve(GestureDisposition.rejected);
      return;
    }
    final startedInDismissDirection = bothDirections || primary > 0;
    if (startedInDismissDirection &&
        primary.abs() >= slop &&
        primary.abs() > cross * _kAxisDominance) {
      _claimed = true;
      resolve(GestureDisposition.accepted);
    }
  }

  @override
  void acceptGesture(int pointer) {
    // The arena also hands the win to the last recognizer standing when a
    // touch ends without anyone claiming it (a plain tap). Only a drag this
    // recognizer claimed itself starts a dismiss.
    if (!_claimed || _pointer == null) return;
    _accepted = true;
    onStart?.call();
    onUpdate?.call(_moved);
  }

  @override
  void rejectGesture(int pointer) {
    stopTrackingPointer(pointer);
  }

  void _complete({required double? velocity}) {
    final pointer = _pointer;
    final wasAccepted = _accepted;
    _reset();
    if (pointer != null) stopTrackingPointer(pointer);
    if (!wasAccepted) return;
    if (velocity == null) {
      onCancel?.call();
    } else {
      onEnd?.call(velocity);
    }
  }

  void _reset() {
    _pointer = null;
    _claimed = false;
    _accepted = false;
    _velocity = null;
  }

  @override
  void didStopTrackingLastPointer(int pointer) => _reset();

  @override
  String get debugDescription => 'swipe to dismiss';
}

/// Lets the person close the media viewer by dragging its content away.
///
/// The media follows the finger in two dimensions (shrinking slightly as it
/// moves) while [progress] reports how far along the dismissal is. The gesture
/// must start along [axis]; returning the media to center cancels the dismiss.
///
/// [axis] is the direction opposite to the one the playlist pages along, so
/// the two gestures never compete.
class MediaSwipeDismissLayer extends StatefulWidget {
  const MediaSwipeDismissLayer({
    super.key,
    required this.enabled,
    required this.axis,
    required this.bothDirections,
    required this.canStart,
    required this.onDismiss,
    required this.child,
    this.progress,
    this.transformChild = true,
  });

  /// Whether the gesture is armed at all.
  final bool enabled;

  /// Direction of the dismissing drag.
  final Axis axis;

  /// `true` lets the drag start either way along [axis]; `false` accepts only
  /// the positive direction (down for a vertical axis).
  final bool bothDirections;

  /// Asked each time a finger lands; `false` leaves that touch alone.
  final bool Function() canStart;

  /// Called once, when a drag is released past the threshold.
  final VoidCallback onDismiss;

  /// Receives 0..1 while the media is pulled away (1 at half a screen).
  final ValueNotifier<double>? progress;

  /// Whether this layer moves [child]. Set to false when only descendants
  /// wrapped in [MediaSwipeDismissTarget] should follow the drag.
  final bool transformChild;

  /// The full viewer subtree. By default it follows the dismiss drag. Set
  /// [transformChild] to false to keep it anchored and move only media targets.
  final Widget child;

  @override
  State<MediaSwipeDismissLayer> createState() => _MediaSwipeDismissLayerState();
}

class _MediaSwipeDismissLayerState extends State<MediaSwipeDismissLayer>
    with SingleTickerProviderStateMixin {
  final ValueNotifier<Offset> _offset = ValueNotifier<Offset>(Offset.zero);
  late final AnimationController _settle;
  Offset _settleFrom = Offset.zero;
  Offset _settleTo = Offset.zero;
  Offset _dragBase = Offset.zero;
  bool _dismissed = false;

  /// Size of the viewer along the drag axis, measured at drag start.
  double _dragExtent = 0.0;

  @override
  void initState() {
    super.initState();
    _settle =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 220),
        )..addListener(() {
          final t = Curves.easeOutCubic.transform(_settle.value);
          _setOffset(Offset.lerp(_settleFrom, _settleTo, t)!);
        });
  }

  @override
  void didUpdateWidget(MediaSwipeDismissLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled && !widget.enabled) {
      _settle.stop();
      _dismissed = false;
      _setOffset(Offset.zero);
    }
  }

  @override
  void dispose() {
    _settle.dispose();
    _offset.dispose();
    super.dispose();
  }

  double _measureExtent() {
    final box = context.findRenderObject();
    if (box is RenderBox && box.hasSize) {
      return widget.axis == Axis.vertical ? box.size.height : box.size.width;
    }
    return 0.0;
  }

  double get _extent => _dragExtent > 0 ? _dragExtent : _measureExtent();

  double _progressFor(Offset offset) {
    final extent = _dragExtent;
    if (extent <= 0) return 0.0;
    final fraction = (offset.distance / (extent * _kFadeDistanceFraction))
        .clamp(0.0, 1.0)
        .toDouble();
    // Fade quickly at the start of the pull while keeping the image itself
    // opaque and in motion until the normal dismiss threshold is reached.
    return Curves.easeOutCubic.transform(fraction);
  }

  double _primaryOffset(Offset value) =>
      widget.axis == Axis.vertical ? value.dy : value.dx;

  void _setOffset(Offset value) {
    _offset.value = value;
    widget.progress?.value = _progressFor(value);
  }

  void _animateTo(Offset target) {
    _settleFrom = _offset.value;
    _settleTo = target;
    _settle.forward(from: 0.0);
  }

  bool _canStart() => widget.enabled && !_dismissed && widget.canStart();

  void _handleStart() {
    if (_dismissed) return;
    _settle.stop();
    _dragExtent = _measureExtent();
    _dragBase = _offset.value;
  }

  void _handleUpdate(Offset delta) {
    if (_dismissed) return;
    _setOffset(_dragBase + delta);
  }

  void _handleEnd(double velocity) {
    if (_dismissed) return;
    final offset = _offset.value;
    final extent = _extent;
    final primary = _primaryOffset(offset);
    final sign = widget.bothDirections
        ? (primary == 0 ? (velocity < 0 ? -1.0 : 1.0) : primary.sign)
        : 1.0;
    final towardsExit = velocity * sign;

    final correctDirection = widget.bothDirections || primary > 0;
    final farEnough =
        extent > 0 &&
        offset.distance >= extent * _kDismissDistanceFraction &&
        correctDirection;
    final flung =
        towardsExit >= _kDismissFlingVelocity && offset.distance > 12.0;
    final flungBack = towardsExit <= -_kDismissFlingVelocity;

    if (correctDirection && !flungBack && (farEnough || flung)) {
      _dismiss(sign);
    } else {
      _animateTo(Offset.zero);
    }
  }

  void _dismiss(double sign) {
    _dismissed = true;
    final current = _offset.value;
    final target = widget.axis == Axis.vertical
        ? Offset(current.dx, sign * _extent)
        : Offset(sign * _extent, current.dy);
    _animateTo(target);
    widget.onDismiss();
    // The viewer normally pops right away and this widget goes with it. If
    // something swallowed the pop, bring the media back instead of leaving it
    // offscreen.
    Future<void>.delayed(const Duration(milliseconds: 800), () {
      if (!mounted || !_dismissed) return;
      _dismissed = false;
      _animateTo(Offset.zero);
    });
  }

  void _handleCancel() {
    if (_dismissed) return;
    _animateTo(Offset.zero);
  }

  Map<Type, GestureRecognizerFactory> get _dismissGestures =>
      <Type, GestureRecognizerFactory>{
        SwipeDismissRecognizer:
            GestureRecognizerFactoryWithHandlers<SwipeDismissRecognizer>(
              () => SwipeDismissRecognizer(canStart: _canStart),
              (recognizer) {
                recognizer
                  ..canStart = _canStart
                  ..axis = widget.axis
                  ..bothDirections = widget.bothDirections
                  ..onStart = _handleStart
                  ..onUpdate = _handleUpdate
                  ..onEnd = _handleEnd
                  ..onCancel = _handleCancel;
              },
            ),
      };

  @override
  Widget build(BuildContext context) {
    final Widget content = widget.transformChild
        ? ValueListenableBuilder<Offset>(
            valueListenable: _offset,
            child: widget.child,
            builder: (context, offset, child) => _buildTransformed(
              offset: offset,
              child: child,
              progress: _progressFor(offset),
            ),
          )
        : widget.child;

    final scope = _SwipeDismissScope(
      offset: _offset,
      axis: widget.axis,
      enabled: widget.enabled,
      recognizeAtTarget: !widget.transformChild,
      bothDirections: widget.bothDirections,
      canStart: _canStart,
      onStart: _handleStart,
      onUpdate: _handleUpdate,
      onEnd: _handleEnd,
      onCancel: _handleCancel,
      child: content,
    );

    // When only a media target should move, placing the recognizer here would
    // let the viewer's InteractiveViewer/page recognizers win first. Targets
    // install the recognizer deeper around the actual media instead.
    if (!widget.transformChild) return scope;

    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: widget.enabled ? _dismissGestures : const {},
      child: scope,
    );
  }
}

/// Marks just the media surface that should follow a drag while viewer chrome
/// stays anchored and fades away.
class MediaSwipeDismissTarget extends StatelessWidget {
  const MediaSwipeDismissTarget({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_SwipeDismissScope>();
    if (scope == null) return child;

    Widget transformed = LayoutBuilder(
      builder: (context, constraints) {
        final extent = scope.axis == Axis.vertical
            ? constraints.maxHeight
            : constraints.maxWidth;
        return ValueListenableBuilder<Offset>(
          valueListenable: scope.offset,
          child: child,
          builder: (context, offset, child) {
            final fraction = extent.isFinite && extent > 0
                ? (offset.distance / (extent * _kFadeDistanceFraction))
                      .clamp(0.0, 1.0)
                      .toDouble()
                : 0.0;
            final progress = Curves.easeOutCubic.transform(fraction);
            return _buildTransformed(
              offset: offset,
              child: child,
              progress: progress,
            );
          },
        );
      },
    );

    if (!scope.recognizeAtTarget) return transformed;

    final gestures = scope.enabled
        ? <Type, GestureRecognizerFactory>{
            SwipeDismissRecognizer:
                GestureRecognizerFactoryWithHandlers<SwipeDismissRecognizer>(
                  () => SwipeDismissRecognizer(canStart: scope.canStart),
                  (recognizer) {
                    recognizer
                      ..canStart = scope.canStart
                      ..axis = scope.axis
                      ..bothDirections = scope.bothDirections
                      ..onStart = scope.onStart
                      ..onUpdate = scope.onUpdate
                      ..onEnd = scope.onEnd
                      ..onCancel = scope.onCancel;
                  },
                ),
          }
        : const <Type, GestureRecognizerFactory>{};

    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: gestures,
      child: transformed,
    );
  }
}

Widget _buildTransformed({
  required Offset offset,
  required Widget? child,
  required double progress,
}) {
  final scale = 1.0 - _kDismissScaleAmount * progress;
  return Transform(
    alignment: Alignment.center,
    transform: Matrix4.diagonal3Values(scale, scale, 1.0)
      ..setTranslationRaw(offset.dx, offset.dy, 0.0),
    child: child,
  );
}

class _SwipeDismissScope extends InheritedWidget {
  const _SwipeDismissScope({
    required this.offset,
    required this.axis,
    required this.enabled,
    required this.recognizeAtTarget,
    required this.bothDirections,
    required this.canStart,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    required this.onCancel,
    required super.child,
  });

  final ValueListenable<Offset> offset;
  final Axis axis;
  final bool enabled;
  final bool recognizeAtTarget;
  final bool bothDirections;
  final bool Function() canStart;
  final VoidCallback onStart;
  final ValueChanged<Offset> onUpdate;
  final ValueChanged<double> onEnd;
  final VoidCallback onCancel;

  @override
  bool updateShouldNotify(_SwipeDismissScope oldWidget) =>
      offset != oldWidget.offset ||
      axis != oldWidget.axis ||
      enabled != oldWidget.enabled ||
      recognizeAtTarget != oldWidget.recognizeAtTarget ||
      bothDirections != oldWidget.bothDirections ||
      canStart != oldWidget.canStart ||
      onStart != oldWidget.onStart ||
      onUpdate != oldWidget.onUpdate ||
      onEnd != oldWidget.onEnd ||
      onCancel != oldWidget.onCancel;
}
