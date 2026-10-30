import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// How far a single finger has to travel from where it landed, in any
/// direction, before it is claimed as a drag of the playlist pager, as a
/// multiple of the device's touch slop.
///
/// It is deliberately not about direction: the first leg of a curved or
/// L-shaped swipe often points anywhere. And it is relative to the device's
/// slop because that is what everything it competes with is relative to. The
/// item's zoom recognizer accepts any one-finger drag after twice the touch
/// slop (about 16 px on Android, where the slop is about 8 px), so this has to
/// stay clearly under 2. It is over 1 so a tap or a wobble never gets there.
const double kPlaylistSwipeClaimSlopFactor = 1.5;

/// How much further than along the paging axis a drag must have moved across
/// it for swipe to dismiss to claim it. The dismiss recognizer asks this of a
/// drag along its own axis, which is always across the paging axis, and a
/// pager claim that left it no drags to claim would make dismiss hard to
/// trigger.
const double kPlaylistSwipeDismissYieldRatio = 1.15;

/// The same for swipe to seek in a vertical playlist, where its drag is also
/// across the paging axis.
const double kPlaylistSwipeSeekYieldRatio = 1.2;

/// Net distance, in logical pixels, that a swipe has to travel along the
/// paging axis to wrap around at the end of a looping playlist.
const double kPlaylistSwipeMinDistance = 32.0;

/// How far off the paging axis a swipe may point and still wrap around at the
/// end of a looping playlist: the distance across may be up to this many
/// times the distance along (2.0 is about 63 degrees off the axis).
const double kPlaylistSwipeMaxCrossRatio = 2.0;

/// Reads the overall movement of a touch, [delta] from touch-down to release
/// in global coordinates, and says whether it is a swipe to the next item
/// (`1`), to the previous item (`-1`), or neither (`0`).
///
/// [axisDirection] is the scroll direction of the pager. Only the net
/// movement matters, not the path the finger took.
int playlistSwipeDirection(
  Offset delta,
  AxisDirection axisDirection, {
  double minDistance = kPlaylistSwipeMinDistance,
  double maxCrossRatio = kPlaylistSwipeMaxCrossRatio,
}) {
  // Along the axis, positive when the content is pulled toward the next item.
  final double along = switch (axisDirection) {
    AxisDirection.down => -delta.dy,
    AxisDirection.up => delta.dy,
    AxisDirection.right => -delta.dx,
    AxisDirection.left => delta.dx,
  };
  final double cross = switch (axisDirection) {
    AxisDirection.down || AxisDirection.up => delta.dx,
    AxisDirection.right || AxisDirection.left => delta.dy,
  };
  if (along.abs() < minDistance) return 0;
  if (cross.abs() > along.abs() * maxCrossRatio) return 0;
  return along > 0 ? 1 : -1;
}

/// The claiming rule shared by the horizontal and the vertical recognizer.
///
/// It follows a single finger and says when that finger has moved
/// [kPlaylistSwipeClaimSlopFactor] touch slops from where it landed, whatever
/// the direction, ignoring the direction of any single move event. It does not decide
/// anything else: whatever the recognizers accept is handed to the pager as a
/// normal drag by [PlaylistSwipeDrag], so the page follows the finger and the
/// pager's own physics decide whether the swipe commits or is cancelled.
class _SwipeClaim {
  int? _finger;
  Offset _movement = Offset.zero;
  double? _crossAxisYieldRatio;

  /// Starts following [pointer]. False if a finger is already being followed:
  /// a second finger is a pinch, which belongs to the zoom recognizer.
  ///
  /// [crossAxisYieldRatio], when not null, keeps the claim off a drag that
  /// leans across the paging axis by more than that ratio, because another
  /// recognizer claims such drags (see [PlaylistSwipeDrag.crossAxisYieldRatio]).
  bool addFinger(int pointer, double? crossAxisYieldRatio) {
    if (_finger != null) return false;
    _finger = pointer;
    _movement = Offset.zero;
    _crossAxisYieldRatio = crossAxisYieldRatio;
    return true;
  }

  /// Takes in [event] and returns true once the finger has travelled far
  /// enough from where it landed to be claimed: [kPlaylistSwipeClaimSlopFactor]
  /// times [touchSlop]. [axis] is the axis the pager pages along.
  bool hasMovedFarEnough(
    PointerEvent event, {
    required double touchSlop,
    required Axis axis,
  }) {
    if (event is! PointerMoveEvent || event.pointer != _finger) return false;
    _movement += event.delta;
    if (_movement.distance < touchSlop * kPlaylistSwipeClaimSlopFactor) {
      return false;
    }
    final ratio = _crossAxisYieldRatio;
    if (ratio != null) {
      final along = axis == Axis.horizontal ? _movement.dx : _movement.dy;
      final cross = axis == Axis.horizontal ? _movement.dy : _movement.dx;
      // Left unclaimed, not rejected: if the drag straightens out toward the
      // paging axis it is still claimed.
      if (cross.abs() > along.abs() * ratio) return false;
    }
    return true;
  }

  void reset() {
    _finger = null;
    _movement = Offset.zero;
    _crossAxisYieldRatio = null;
  }
}

/// Claims a touch for a pager that pages sideways.
///
/// The two recognizers are the same apart from the axis they extend. They
/// can't share a mixin: the framework's drag recognizer base class is sealed.
class PlaylistSwipeHorizontalRecognizer extends HorizontalDragGestureRecognizer {
  PlaylistSwipeHorizontalRecognizer({
    required this.canClaim,
    this.crossAxisYieldRatio,
  }) : super(supportedDevices: const {PointerDeviceKind.touch});

  /// Asked when a finger lands.
  final bool Function() canClaim;

  /// Asked when a finger lands. See [PlaylistSwipeDrag.crossAxisYieldRatio].
  final double? Function()? crossAxisYieldRatio;

  final _SwipeClaim _claim = _SwipeClaim();

  @override
  bool isPointerAllowed(PointerEvent event) =>
      canClaim() && super.isPointerAllowed(event);

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (!_claim.addFinger(event.pointer, crossAxisYieldRatio?.call())) {
      // A second finger is a pinch: give the touch up.
      resolve(GestureDisposition.rejected);
      return;
    }
    super.addAllowedPointer(event);
  }

  // Only the movement from touch-down decides. The stock test counts the
  // distance along one axis only, so it would never claim a drag that starts
  // out across it.
  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) => false;

  @override
  void handleEvent(PointerEvent event) {
    if (_claim.hasMovedFarEnough(
      event,
      touchSlop: computeHitSlop(event.kind, gestureSettings),
      axis: Axis.horizontal,
    )) {
      resolve(GestureDisposition.accepted);
    }
    super.handleEvent(event);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _claim.reset();
    super.didStopTrackingLastPointer(pointer);
  }
}

/// Claims a touch for a pager that pages vertically. See
/// [PlaylistSwipeHorizontalRecognizer].
class PlaylistSwipeVerticalRecognizer extends VerticalDragGestureRecognizer {
  PlaylistSwipeVerticalRecognizer({
    required this.canClaim,
    this.crossAxisYieldRatio,
  }) : super(supportedDevices: const {PointerDeviceKind.touch});

  /// Asked when a finger lands.
  final bool Function() canClaim;

  /// Asked when a finger lands. See [PlaylistSwipeDrag.crossAxisYieldRatio].
  final double? Function()? crossAxisYieldRatio;

  final _SwipeClaim _claim = _SwipeClaim();

  @override
  bool isPointerAllowed(PointerEvent event) =>
      canClaim() && super.isPointerAllowed(event);

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (!_claim.addFinger(event.pointer, crossAxisYieldRatio?.call())) {
      // A second finger is a pinch: give the touch up.
      resolve(GestureDisposition.rejected);
      return;
    }
    super.addAllowedPointer(event);
  }

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) => false;

  @override
  void handleEvent(PointerEvent event) {
    if (_claim.hasMovedFarEnough(
      event,
      touchSlop: computeHitSlop(event.kind, gestureSettings),
      axis: Axis.vertical,
    )) {
      resolve(GestureDisposition.accepted);
    }
    super.handleEvent(event);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _claim.reset();
    super.didStopTrackingLastPointer(pointer);
  }
}

/// Hands the touches that the recognizers above claim to the playlist pager,
/// the way a [Scrollable] hands its own drag to its position: the page follows
/// the finger along the paging axis, and on release the pager's physics settle
/// it, so a drag that falls short is cancelled and the page snaps back.
class PlaylistSwipeDrag {
  PlaylistSwipeDrag({
    required this.positionOf,
    required this.canClaim,
    this.crossAxisYieldRatio,
  });

  /// The pager's scroll position, or null while it has none.
  final ScrollPosition? Function() positionOf;

  /// Whether item swiping is allowed right now (not zoomed, not pinching, and
  /// so on). Asked when a finger lands and again on every move, so a drag in
  /// progress is cancelled the moment swiping becomes locked.
  final bool Function() canClaim;

  /// Asked when a finger lands. While another recognizer owns drags across the
  /// paging axis (swipe to dismiss, or swipe to seek in a vertical playlist),
  /// returns how much further across than along the axis a drag has to lean
  /// for that recognizer to claim it, and null when none can start.
  ///
  /// A drag that clearly leans that way is left for that recognizer, instead
  /// of racing it. Otherwise the pager, which takes a drag of any direction
  /// after a short travel, would win every drag that is not perfectly straight
  /// and the other gesture would be very hard to trigger.
  final double? Function()? crossAxisYieldRatio;

  Drag? _drag;

  void _start(DragStartDetails details) {
    final position = positionOf();
    if (position == null || !canClaim()) return;
    _drag = position.drag(details, () => _drag = null);
  }

  void _update(DragUpdateDetails details) {
    final drag = _drag;
    if (drag == null) return;
    if (!canClaim()) {
      _cancel();
      return;
    }
    drag.update(details);
  }

  void _end(DragEndDetails details) {
    final drag = _drag;
    _drag = null;
    drag?.end(details);
  }

  void _cancel() {
    final drag = _drag;
    _drag = null;
    drag?.cancel();
  }

  /// The recognizers to put in a [RawGestureDetector] for a pager that pages
  /// along [axis]. They are set up like the pager's own drag recognizers, so
  /// a claimed drag settles just like one the pager recognized itself.
  Map<Type, GestureRecognizerFactory> gestures(
    BuildContext context,
    Axis axis,
  ) {
    final behavior = ScrollConfiguration.of(context);
    // The device's own touch slop, which the pager's recognizer, the taps and
    // the zoom viewer all use. A RawGestureDetector does not apply it by
    // itself, as a GestureDetector does.
    final gestureSettings = MediaQuery.maybeGestureSettingsOf(context);
    void configure(DragGestureRecognizer recognizer) {
      final physics = positionOf()?.physics;
      recognizer
        ..gestureSettings = gestureSettings
        ..onStart = _start
        ..onUpdate = _update
        ..onEnd = _end
        ..onCancel = _cancel
        ..minFlingDistance = physics?.minFlingDistance
        ..minFlingVelocity = physics?.minFlingVelocity
        ..maxFlingVelocity = physics?.maxFlingVelocity
        ..velocityTrackerBuilder = behavior.velocityTrackerBuilder(context);
    }

    return switch (axis) {
      Axis.horizontal => <Type, GestureRecognizerFactory>{
        PlaylistSwipeHorizontalRecognizer:
            GestureRecognizerFactoryWithHandlers<
              PlaylistSwipeHorizontalRecognizer
            >(
              () => PlaylistSwipeHorizontalRecognizer(
                canClaim: canClaim,
                crossAxisYieldRatio: crossAxisYieldRatio,
              ),
              configure,
            ),
      },
      Axis.vertical => <Type, GestureRecognizerFactory>{
        PlaylistSwipeVerticalRecognizer:
            GestureRecognizerFactoryWithHandlers<
              PlaylistSwipeVerticalRecognizer
            >(
              () => PlaylistSwipeVerticalRecognizer(
                canClaim: canClaim,
                crossAxisYieldRatio: crossAxisYieldRatio,
              ),
              configure,
            ),
      },
    };
  }
}

/// Tells the items under the playlist pager how to claim a swipe for it.
class PlaylistSwipeScope extends InheritedWidget {
  const PlaylistSwipeScope({
    super.key,
    required this.drag,
    required this.axis,
    required this.enabled,
    required super.child,
  });

  final PlaylistSwipeDrag drag;

  /// The axis the pager pages along.
  final Axis axis;

  /// False when there is no pager to swipe, as in the continuous list.
  final bool enabled;

  static PlaylistSwipeScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PlaylistSwipeScope>();

  @override
  bool updateShouldNotify(PlaylistSwipeScope oldWidget) =>
      drag != oldWidget.drag ||
      axis != oldWidget.axis ||
      enabled != oldWidget.enabled;
}

/// A transparent layer that lets an item claim a swipe for the playlist pager.
///
/// Put it in the item's [Stack] above the item's own gesture handling (the
/// zoom viewer, in particular), the way the brightness and volume strips are.
/// Recognizers see a touch from the topmost widget down, so this one gets to
/// claim a curved or L-shaped swipe before the zoom recognizer does.
class PlaylistSwipeClaimLayer extends StatelessWidget {
  const PlaylistSwipeClaimLayer({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = PlaylistSwipeScope.maybeOf(context);
    if (scope == null || !scope.enabled) return const SizedBox.shrink();
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      excludeFromSemantics: true,
      gestures: scope.drag.gestures(context, scope.axis),
      child: const SizedBox.expand(),
    );
  }
}
