import 'dart:async';

// A tab being dragged between windows, live: the window that carries it follows
// the cursor, and a strip of another window shows where the tab would land.
//
// This file has no Flutter types (plain numbers and small interfaces) so the
// rules can be tested on their own. The tab strip supplies the real pieces:
// the platform calls (tab_drag_platform.dart), the drop targets (each tab strip
// registers one) and a host that opens and closes windows.

/// A rectangle in a window's own coordinates (logical pixels).
typedef DragRect = ({double left, double top, double right, double bottom});

bool _contains(DragRect rect, double x, double y) =>
    x >= rect.left && x <= rect.right && y >= rect.top && y <= rect.bottom;

/// What the platform is asked on each step of a drag.
class TabDragPollRequest {
  const TabDragPollRequest({
    required this.carrierViewId,
    required this.grabX,
    required this.grabY,
    required this.park,
    required this.candidates,
  });

  /// The window that follows the cursor, if any.
  final int? carrierViewId;

  /// Where in the carrier's client area (logical pixels) the cursor stays.
  final double grabX;
  final double grabY;

  /// Keep the carrier out of sight instead of under the cursor: the tab is
  /// shown somewhere else (over a drop target, or back in its own strip).
  final bool park;

  /// The windows (by view id) that may be reported as under the cursor.
  final List<int> candidates;
}

/// What the platform reports for one step of a drag. Screen positions are in
/// physical pixels.
class TabDragPoll {
  const TabDragPoll({
    required this.cursorX,
    required this.cursorY,
    required this.buttonDown,
    this.windowViewId,
    this.originX = 0,
    this.originY = 0,
    this.scale = 1,
  });

  final double cursorX;
  final double cursorY;

  /// Whether the primary mouse button is still held.
  final bool buttonDown;

  /// The topmost of the requested windows under the cursor, or null when the
  /// cursor is over none of them (or something else covers them there).
  final int? windowViewId;

  /// Where that window's content starts on the screen, and its pixel ratio:
  /// `(cursor - origin) / scale` is the cursor in the window's own coordinates.
  final double originX;
  final double originY;
  final double scale;
}

/// The platform side of a live drag.
abstract interface class TabDragPlatform {
  /// Moves the carrier, then reports the cursor. Null when the platform cannot
  /// do it (the drag is then given up).
  Future<TabDragPoll?> poll(TabDragPollRequest request);

  /// Gets a window ready to be moved by the drag (a maximized one is restored)
  /// and returns the factor its width changed by.
  Future<double> prepare(int viewId);

  /// Brings a window to the front and focuses it.
  Future<void> activate(int viewId);
}

/// A place a dragged tab can be dropped: a tab strip in some window.
abstract interface class TabDropTarget<T extends Object> {
  int get viewId;

  /// Where the strip is, in its window's coordinates; null while it is not on
  /// screen. A tab over it is dropped into the strip.
  DragRect? get dropZone;

  bool accepts(T payload);

  /// The slot (0 = before the first tab) that a tab at window x [x] lands in.
  int slotAt(double x);

  /// Shows (or moves) the place the tab would land.
  void showDrop(T payload, int slot);
  void clearDrop();

  /// Takes the tab in at [slot]. False when it could not.
  bool drop(T payload, int slot);
}

/// The drop targets that currently exist.
class TabDropTargets<T extends Object> {
  final Set<TabDropTarget<T>> _targets = <TabDropTarget<T>>{};

  void register(TabDropTarget<T> target) => _targets.add(target);
  void unregister(TabDropTarget<T> target) => _targets.remove(target);

  Iterable<TabDropTarget<T>> inView(int viewId) =>
      _targets.where((target) => target.viewId == viewId);

  /// The ids of the windows that have a target.
  Set<int> get viewIds => {for (final target in _targets) target.viewId};

  bool get isEmpty => _targets.isEmpty;
}

/// Where in a window (logical pixels from its content's top-left corner) the
/// cursor stays while the window follows it.
typedef TabDragGrip = ({double x, double y});

/// The window that carries the tab while it is out of every strip.
class TabDragCarrierWindow {
  const TabDragCarrierWindow({
    required this.viewId,
    required this.close,
    required this.grip,
  });

  final int viewId;
  final void Function() close;

  /// Asked on every step: the window may learn where its tab really is only
  /// once it has been drawn.
  final TabDragGrip Function() grip;
}

/// How a drag ended.
enum TabDragOutcome {
  /// The tab went back to the strip it came from.
  returned,

  /// The tab stays in a window of its own, where it was let go.
  detached,

  /// The tab was the only one in its window, which stays where it was let go.
  movedWindow,

  /// Another window's strip took the tab in.
  dropped,

  /// Nothing came of it; the tab stays where it was.
  cancelled,
}

class TabDragResult {
  const TabDragResult(this.outcome, {this.targetViewId, this.carrierViewId});

  final TabDragOutcome outcome;

  /// For [TabDragOutcome.dropped]: the window that took the tab.
  final int? targetViewId;

  /// For [TabDragOutcome.detached]: the window the tab is in now.
  final int? carrierViewId;
}

/// What a drag needs from the strip it started in.
abstract interface class TabDragHost {
  /// Whether window position ([x], [y]) is within the source strip's zone, in
  /// which the tab has not left. [wasInside] is the previous answer, so that a
  /// cursor on the boundary does not flip back and forth.
  bool isInSourceStrip(double x, double y, {required bool wasInside});

  /// Opens the window that carries the tab, or null if it cannot be opened.
  /// [onShown] is called once the window has drawn its first frame.
  TabDragCarrierWindow? openCarrier({required void Function() onShown});

  /// The tab is back over its source strip (true) or has left it (false).
  void returned(bool returned);

  /// The carrier window is on screen now.
  void carrierShown();

  /// The drag is over. Called once.
  void finished(TabDragResult result);
}

enum _Mode { free, overTarget, returned }

/// One drag of a tab, from the moment it is pulled out of its strip to the
/// moment the mouse button is released.
///
/// While it runs, a timer asks the platform for the cursor each frame. What the
/// tab does follows from where the cursor is:
///
///  * over a strip that accepts it: the tab shows there, and the carrier is
///    parked out of the way;
///  * back over its own strip: the tab is where it started again;
///  * anywhere else: the carrier window follows the cursor. That is a new window
///    for a tab that has company in its window, and the window itself for a
///    tab that is alone ([movesSourceWindow]).
///
/// Releasing the button settles it (see [TabDragOutcome]).
class TabDragSession<T extends Object> {
  TabDragSession({
    required this.payload,
    required this.sourceViewId,
    required this.platform,
    required this.targets,
    required this.host,
    this.movesSourceWindow = false,
    this.grabX = 0,
    this.grabY = 0,
    this.interval = const Duration(milliseconds: 16),
  });

  final T payload;
  final int sourceViewId;
  final TabDragPlatform platform;
  final TabDropTargets<T> targets;
  final TabDragHost host;

  /// The tab is its window's only one, so the window itself is what follows the
  /// cursor.
  final bool movesSourceWindow;

  /// Where in the source window the cursor stays when that window is the
  /// carrier ([movesSourceWindow]); a new window brings its own.
  double grabX;
  double grabY;

  final Duration interval;

  _Mode _mode = _Mode.free;
  TabDropTarget<T>? _target;
  int _slot = 0;
  TabDragCarrierWindow? _carrier;
  bool _carrierFailed = false;
  bool _started = false;
  bool _finished = false;
  Timer? _timer;
  Future<void>? _inFlight;

  bool get isFinished => _finished;

  /// The window carrying the tab, once there is one.
  int? get carrierViewId => _carrier?.viewId;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    if (movesSourceWindow) {
      final ratio = await platform.prepare(sourceViewId);
      if (_finished) return;
      if (ratio.isFinite && ratio > 0) grabX *= ratio;
    }
    _timer = Timer.periodic(interval, (_) => unawaited(tick()));
    unawaited(tick());
  }

  /// One step of the drag. Steps do not overlap: asking while one is under way
  /// waits for that one.
  Future<void> tick({bool ending = false}) {
    if (_finished) return Future<void>.value();
    return _inFlight ??= _tick(ending: ending)
        .whenComplete(() => _inFlight = null);
  }

  /// Gives the drag up (the strip it started in is going away): nothing comes
  /// of it, and the carrier window is closed.
  void abort() => _finish(failed: true);

  /// Settles the drag now, on the cursor's current position, even if the mouse
  /// button still reads as held. For when the strip is told of the release
  /// before the platform notices it.
  Future<void> finishNow() async {
    if (_finished) return;
    final pending = _inFlight;
    if (pending != null) await pending;
    if (_finished) return;
    await tick(ending: true);
  }

  Future<void> _tick({required bool ending}) async {
    final poll = await platform.poll(
      _request(
        park: _mode != _Mode.free,
        candidates: <int>{...targets.viewIds, sourceViewId}.toList(),
      ),
    );
    if (_finished) return;
    if (poll == null) {
      _finish(failed: true);
      return;
    }
    _update(poll);
    if (ending || !poll.buttonDown) _finish();
  }

  TabDragPollRequest _request({
    required bool park,
    List<int> candidates = const <int>[],
  }) {
    final carrier = _carrier;
    final grip = movesSourceWindow || carrier == null
        ? (x: grabX, y: grabY)
        : carrier.grip();
    return TabDragPollRequest(
      carrierViewId: movesSourceWindow ? sourceViewId : carrier?.viewId,
      grabX: grip.x,
      grabY: grip.y,
      park: park,
      candidates: candidates,
    );
  }

  void _update(TabDragPoll poll) {
    var next = _Mode.free;
    TabDropTarget<T>? target;
    var slot = 0;
    final view = poll.windowViewId;
    if (view != null) {
      final scale = poll.scale > 0 ? poll.scale : 1.0;
      final x = (poll.cursorX - poll.originX) / scale;
      final y = (poll.cursorY - poll.originY) / scale;
      if (view == sourceViewId) {
        // The tab's own window: it is home over its strip, and a window that is
        // itself moving with the tab is never somewhere to drop it.
        if (!movesSourceWindow &&
            host.isInSourceStrip(x, y, wasInside: _mode == _Mode.returned)) {
          next = _Mode.returned;
        }
      } else if (view != _carrier?.viewId) {
        for (final candidate in targets.inView(view)) {
          final zone = candidate.dropZone;
          if (zone != null &&
              _contains(zone, x, y) &&
              candidate.accepts(payload)) {
            target = candidate;
            slot = candidate.slotAt(x);
            next = _Mode.overTarget;
            break;
          }
        }
      }
    }

    final previous = _target;
    if (next == _Mode.overTarget) {
      if (previous != target) previous?.clearDrop();
      if (previous != target || _slot != slot || _mode != _Mode.overTarget) {
        target!.showDrop(payload, slot);
      }
    } else {
      previous?.clearDrop();
    }
    if ((_mode == _Mode.returned) != (next == _Mode.returned)) {
      host.returned(next == _Mode.returned);
    }
    _mode = next;
    _target = next == _Mode.overTarget ? target : null;
    _slot = slot;

    // The carrier is made when the tab first has nowhere else to be.
    if (_mode == _Mode.free &&
        !movesSourceWindow &&
        _carrier == null &&
        !_carrierFailed) {
      final carrier = host.openCarrier(onShown: host.carrierShown);
      if (carrier == null) {
        _carrierFailed = true;
      } else {
        _carrier = carrier;
      }
    }
  }

  void _finish({bool failed = false}) {
    if (_finished) return;
    _finished = true;
    _timer?.cancel();

    final target = _target;
    final mode = _mode;
    var taken = false;
    if (!failed && mode == _Mode.overTarget && target != null) {
      taken = target.drop(payload, _slot);
    }
    target?.clearDrop();

    final carrier = _carrier;
    final TabDragOutcome outcome;
    if (taken) {
      outcome = TabDragOutcome.dropped;
    } else if (failed) {
      outcome = TabDragOutcome.cancelled;
    } else if (mode == _Mode.returned) {
      outcome = TabDragOutcome.returned;
    } else if (movesSourceWindow) {
      outcome = TabDragOutcome.movedWindow;
    } else if (carrier != null) {
      outcome = TabDragOutcome.detached;
    } else {
      outcome = TabDragOutcome.cancelled;
    }

    // A window that was parked out of sight is put under the cursor again; the
    // carrier of a drop, or of a drag that went back, is not needed any more.
    final keepsCarrier = outcome == TabDragOutcome.detached;
    if (!keepsCarrier) carrier?.close();
    if (outcome == TabDragOutcome.movedWindow ||
        outcome == TabDragOutcome.detached ||
        (movesSourceWindow && outcome == TabDragOutcome.cancelled)) {
      unawaited(platform.poll(_request(park: false)));
    }
    if (taken) unawaited(platform.activate(target!.viewId));

    host.finished(
      TabDragResult(
        outcome,
        targetViewId: taken ? target!.viewId : null,
        carrierViewId: keepsCarrier ? carrier?.viewId : null,
      ),
    );
  }
}
