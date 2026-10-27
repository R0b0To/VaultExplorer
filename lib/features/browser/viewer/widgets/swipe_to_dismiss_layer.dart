import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

/// Share of the screen, along the drag axis, that the content has to be pulled
/// before letting go closes the viewer.
const double _kDismissDistanceFraction = 0.2;

/// Release speed (logical px/s along the drag axis) that closes the viewer no
/// matter how far it was pulled.
const double _kDismissFlingVelocity = 700.0;

/// A drag only counts once it has travelled this many times further along its
/// axis than across it, so a diagonal scribble never closes the viewer.
const double _kAxisDominance = 1.5;

/// Recognizes a one-finger drag that travels mainly along [axis] and reports
/// how far it has moved.
///
/// It is deliberately a plain [OneSequenceGestureRecognizer] rather than a
/// drag recognizer subclass: the viewer needs a direction filter (down only,
/// or either way) that the stock recognizers cannot express, and it must give
/// the touch back to the playlist pager, the zoom/pan handling and the
/// brightness/volume strips whenever one of them is the better owner.
///
/// Those all sit deeper in the widget tree, so they see every move event
/// first. This recognizer only ever wins a drag nobody else has claimed.
class SwipeDismissRecognizer extends OneSequenceGestureRecognizer {
  SwipeDismissRecognizer({required this.canStart, super.debugOwner})
    : super(supportedDevices: const {PointerDeviceKind.touch});

  /// Asked when a finger lands. `false` leaves that touch entirely alone
  /// (zoomed in, pinching, a page change still settling, ...).
  bool Function() canStart;

  /// Axis the dismissing drag travels along.
  Axis axis = Axis.vertical;

  /// Whether the drag may go either way along [axis]. When `false` only the
  /// positive direction (down for a vertical axis) is accepted.
  bool bothDirections = false;

  VoidCallback? onStart;

  /// Distance moved along [axis] since the drag was accepted (signed).
  ValueChanged<double>? onUpdate;

  /// Fired on release with the velocity along [axis] in logical px/s.
  ValueChanged<double>? onEnd;

  /// Fired when an accepted drag is interrupted (second finger, cancel).
  VoidCallback? onCancel;

  int? _pointer;
  Offset _origin = Offset.zero;
  Offset _moved = Offset.zero;
  double _acceptedAt = 0.0;
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
    _acceptedAt = 0.0;
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
        onUpdate?.call(_primaryOf(_moved) - _acceptedAt);
      } else {
        _consider();
      }
    } else if (event is PointerUpEvent) {
      _velocity?.addPosition(event.timeStamp, event.position);
      if (_accepted) {
        final velocity = _velocity?.getVelocity().pixelsPerSecond ?? Offset.zero;
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
    final slop = computeHitSlop(PointerDeviceKind.touch, gestureSettings);
    final primary = _primaryOf(_moved);
    final cross = _crossOf(_moved).abs();

    // Heading the wrong way for a one-way gesture (e.g. up instead of down).
    if (!bothDirections && primary < -slop / 2) {
      resolve(GestureDisposition.rejected);
      return;
    }
    // Mostly across the axis: that is the pager's or the seek gesture's.
    if (cross > slop && cross >= primary.abs()) {
      resolve(GestureDisposition.rejected);
      return;
    }
    if (primary.abs() >= slop && primary.abs() > cross * _kAxisDominance) {
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
    _acceptedAt = _primaryOf(_moved);
    onStart?.call();
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
/// The content follows the finger (shrinking a little as it goes) while
/// [progress] reports how far along the dismissal is, so the owner can fade
/// whatever sits behind it. Letting go past a fifth of the screen, or with a
/// fast flick, calls [onDismiss]; otherwise the content springs back.
///
/// [axis] is the direction of the dismissing drag. The viewer picks the axis
/// opposite to the one the playlist pages along, so the two never compete.
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
  });

  /// Whether the gesture is armed at all.
  final bool enabled;

  /// Direction of the dismissing drag.
  final Axis axis;

  /// `true` lets the drag go either way along [axis]; `false` accepts only
  /// the positive direction (down for a vertical axis).
  final bool bothDirections;

  /// Asked each time a finger lands; `false` leaves that touch alone.
  final bool Function() canStart;

  /// Called once, when a drag is released past the threshold.
  final VoidCallback onDismiss;

  /// Receives 0..1 while the content is pulled away (1 at half a screen).
  final ValueNotifier<double>? progress;

  final Widget child;

  @override
  State<MediaSwipeDismissLayer> createState() => _MediaSwipeDismissLayerState();
}

class _MediaSwipeDismissLayerState extends State<MediaSwipeDismissLayer>
    with SingleTickerProviderStateMixin {
  final ValueNotifier<double> _offset = ValueNotifier<double>(0.0);
  late final AnimationController _settle;
  double _settleFrom = 0.0;
  double _settleTo = 0.0;
  double _dragBase = 0.0;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _settle =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 220),
        )..addListener(() {
          final t = Curves.easeOutCubic.transform(_settle.value);
          _setOffset(_settleFrom + (_settleTo - _settleFrom) * t);
        });
  }

  @override
  void didUpdateWidget(MediaSwipeDismissLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled && !widget.enabled) {
      _settle.stop();
      _dismissed = false;
      _setOffset(0.0);
    }
  }

  @override
  void dispose() {
    _settle.dispose();
    _offset.dispose();
    super.dispose();
  }

  /// Size of the layer along the drag axis, measured when a drag starts (never
  /// during build) and reused while that drag is painted.
  double _dragExtent = 0.0;

  double _measureExtent() {
    final box = context.findRenderObject();
    if (box is RenderBox && box.hasSize) {
      return widget.axis == Axis.vertical ? box.size.height : box.size.width;
    }
    return 0.0;
  }

  double get _extent => _dragExtent > 0 ? _dragExtent : _measureExtent();

  double _progressFor(double offset) {
    final extent = _dragExtent;
    if (extent <= 0) return 0.0;
    return (offset.abs() / (extent * 0.5)).clamp(0.0, 1.0);
  }

  void _setOffset(double value) {
    _offset.value = value;
    widget.progress?.value = _progressFor(value);
  }

  void _animateTo(double target) {
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

  void _handleUpdate(double delta) {
    if (_dismissed) return;
    var value = _dragBase + delta;
    if (!widget.bothDirections && value < 0) value = 0.0;
    _setOffset(value);
  }

  void _handleEnd(double velocity) {
    if (_dismissed) return;
    final offset = _offset.value;
    final extent = _extent;
    final sign = offset == 0 ? (velocity < 0 ? -1.0 : 1.0) : offset.sign;
    final towardsExit = velocity * sign;

    final farEnough =
        extent > 0 && offset.abs() >= extent * _kDismissDistanceFraction;
    final flung = towardsExit >= _kDismissFlingVelocity && offset.abs() > 12.0;
    final flungBack = towardsExit <= -_kDismissFlingVelocity;

    if (!flungBack && (farEnough || flung)) {
      _dismiss(sign);
    } else {
      _animateTo(0.0);
    }
  }

  void _dismiss(double sign) {
    _dismissed = true;
    _animateTo(sign * _extent);
    widget.onDismiss();
    // The viewer normally pops right away and this widget goes with it. If
    // something swallowed the pop, bring the content back instead of leaving
    // an empty screen.
    Future<void>.delayed(const Duration(milliseconds: 800), () {
      if (!mounted || !_dismissed) return;
      _dismissed = false;
      _animateTo(0.0);
    });
  }

  void _handleCancel() {
    if (_dismissed) return;
    _animateTo(0.0);
  }

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: widget.enabled
          ? <Type, GestureRecognizerFactory>{
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
            }
          : const <Type, GestureRecognizerFactory>{},
      child: ValueListenableBuilder<double>(
        valueListenable: _offset,
        child: widget.child,
        builder: (context, offset, child) {
          final scale = 1.0 - 0.08 * _progressFor(offset);
          final dx = widget.axis == Axis.horizontal ? offset : 0.0;
          final dy = widget.axis == Axis.vertical ? offset : 0.0;
          // Always a Transform, even at rest, so the subtree below keeps its
          // element (and therefore its state) when a drag starts and ends.
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.diagonal3Values(scale, scale, 1.0)
              ..setTranslationRaw(dx, dy, 0.0),
            child: child,
          );
        },
      ),
    );
  }
}
