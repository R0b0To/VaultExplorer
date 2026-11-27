import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/browser/widgets/tab_drag_session.dart';

const int kSource = 1;
const int kOther = 2;
const int kCarrier = 9;

/// A platform that answers each step from a script (the last answer repeats).
class FakePlatform implements TabDragPlatform {
  final List<TabDragPoll?> script = <TabDragPoll?>[];
  final List<TabDragPollRequest> requests = <TabDragPollRequest>[];
  final List<int> activated = <int>[];
  double prepareRatio = 1;
  TabDragPoll? _last;

  @override
  Future<TabDragPoll?> poll(TabDragPollRequest request) async {
    requests.add(request);
    if (script.isNotEmpty) _last = script.removeAt(0);
    return _last;
  }

  @override
  Future<double> prepare(int viewId) async => prepareRatio;

  @override
  Future<void> activate(int viewId) async => activated.add(viewId);
}

class FakeTarget implements TabDropTarget<String> {
  FakeTarget(
    this.viewId, {
    this.zone = (left: 0, top: 0, right: 500, bottom: 32),
  });

  @override
  final int viewId;
  DragRect? zone;
  bool accepting = true;
  bool takes = true;
  final List<String> events = <String>[];

  @override
  DragRect? get dropZone => zone;
  @override
  bool accepts(String payload) => accepting;
  @override
  int slotAt(double x) => (x / 100).floor();
  @override
  void showDrop(String payload, int slot) => events.add('show $slot');
  @override
  void clearDrop() => events.add('clear');
  @override
  bool drop(String payload, int slot) {
    events.add('drop $slot');
    return takes;
  }
}

class FakeHost implements TabDragHost {
  bool inSource = false;
  bool canOpen = true;
  double gripX = 40;
  double gripY = 12;
  int opened = 0;
  int closed = 0;
  final List<bool> returnedCalls = <bool>[];
  int shown = 0;
  TabDragResult? result;
  int finishedCalls = 0;

  @override
  bool isInSourceStrip(double x, double y, {required bool wasInside}) =>
      inSource;
  @override
  TabDragCarrierWindow? openCarrier({required void Function() onShown}) {
    if (!canOpen) return null;
    opened++;
    return TabDragCarrierWindow(
      viewId: kCarrier,
      close: () => closed++,
      grip: () => (x: gripX, y: gripY),
    );
  }

  @override
  void returned(bool returned) => returnedCalls.add(returned);
  @override
  void carrierShown() => shown++;
  @override
  void finished(TabDragResult result) {
    finishedCalls++;
    this.result = result;
  }
}

TabDragPoll poll({
  double x = 0,
  double y = 0,
  bool down = true,
  int? view,
  double ox = 0,
  double oy = 0,
  double scale = 1,
}) => TabDragPoll(
  cursorX: x,
  cursorY: y,
  buttonDown: down,
  windowViewId: view,
  originX: ox,
  originY: oy,
  scale: scale,
);

class Rig {
  Rig({bool alone = false, double grabX = 70, double grabY = 9}) {
    session = TabDragSession<String>(
      payload: 'tab',
      sourceViewId: kSource,
      platform: platform,
      targets: targets,
      host: host,
      movesSourceWindow: alone,
      grabX: grabX,
      grabY: grabY,
      interval: const Duration(hours: 1),
    );
  }
  final platform = FakePlatform();
  final targets = TabDropTargets<String>();
  final host = FakeHost();
  late final TabDragSession<String> session;

  /// Feeds [polls] to the session one step at a time.
  Future<void> run(List<TabDragPoll> polls) async {
    platform.script.addAll(polls);
    for (var i = 0; i < polls.length; i++) {
      await session.tick();
    }
  }
}

void main() {
  group('a tab pulled out of a window with company', () {
    test('gets a window of its own that is made once, and stays', () async {
      final rig = Rig();
      await rig.run([poll(x: 300, y: 300), poll(x: 320, y: 310)]);
      expect(rig.host.opened, 1);
      // From the second step on the carrier is the one that follows the cursor.
      expect(rig.platform.requests[0].carrierViewId, isNull);
      expect(rig.platform.requests[1].carrierViewId, kCarrier);
      expect(rig.platform.requests[1].park, isFalse);
      // The grip is the window's own, and may change once it is drawn.
      expect(rig.platform.requests[1].grabX, 40);
      expect(rig.platform.requests[1].grabY, 12);
      rig.host.gripX = 300;
      await rig.run([poll(x: 325, y: 312)]);
      expect(rig.platform.requests.last.grabX, 300);

      await rig.run([poll(x: 330, y: 320, down: false)]);
      expect(rig.session.isFinished, isTrue);
      expect(rig.host.result!.outcome, TabDragOutcome.detached);
      expect(rig.host.result!.carrierViewId, kCarrier);
      expect(rig.host.closed, 0);
      // The window that was left where it was let go is put under the cursor.
      expect(rig.platform.requests.last.park, isFalse);
      expect(rig.platform.requests.last.carrierViewId, kCarrier);
    });

    test('the source window is always among the windows asked about', () async {
      final rig = Rig();
      final other = FakeTarget(kOther);
      rig.targets.register(other);
      await rig.run([poll()]);
      expect(rig.platform.requests.single.candidates..sort(), [
        kSource,
        kOther,
      ]);
    });

    test(
      'over another window\'s strip it shows there and parks the carrier',
      () async {
        final rig = Rig();
        final other = FakeTarget(kOther);
        rig.targets.register(other);
        await rig.run([
          poll(x: 300, y: 300), // free: carrier made
          poll(x: 250, y: 10, view: kOther), // over the strip, slot 2
        ]);
        expect(other.events, ['show 2']);
        await rig.run([poll(x: 260, y: 12, view: kOther)]);
        // The carrier was parked for the step after it went over the strip.
        expect(rig.platform.requests.last.park, isTrue);
        // A move within the same slot changes nothing; another slot moves it.
        expect(other.events, ['show 2']);
        await rig.run([poll(x: 410, y: 12, view: kOther)]);
        expect(other.events, ['show 2', 'show 4']);
      },
    );

    test(
      'letting go over a strip drops the tab in and closes the carrier',
      () async {
        final rig = Rig();
        final other = FakeTarget(kOther);
        rig.targets.register(other);
        await rig.run([
          poll(x: 300, y: 300),
          poll(x: 150, y: 10, view: kOther),
          poll(x: 150, y: 10, view: kOther, down: false),
        ]);
        expect(other.events, ['show 1', 'drop 1', 'clear']);
        expect(rig.host.result!.outcome, TabDragOutcome.dropped);
        expect(rig.host.result!.targetViewId, kOther);
        expect(rig.host.closed, 1);
        expect(rig.platform.activated, [kOther]);
      },
    );

    test(
      'a strip that cannot take it leaves the tab in its own window',
      () async {
        final rig = Rig();
        final other = FakeTarget(kOther)..takes = false;
        rig.targets.register(other);
        await rig.run([
          poll(x: 300, y: 300),
          poll(x: 150, y: 10, view: kOther),
          poll(x: 150, y: 10, view: kOther, down: false),
        ]);
        expect(rig.host.result!.outcome, TabDragOutcome.detached);
        expect(rig.host.closed, 0);
        expect(rig.platform.activated, isEmpty);
      },
    );

    test('a strip that refuses it is not a target at all', () async {
      final rig = Rig();
      final other = FakeTarget(kOther)..accepting = false;
      rig.targets.register(other);
      await rig.run([poll(x: 300, y: 300), poll(x: 150, y: 10, view: kOther)]);
      expect(other.events, isEmpty);
      await rig.run([poll(x: 150, y: 10, view: kOther)]);
      expect(rig.platform.requests.last.park, isFalse);
    });

    test('over a window but beside its strip it is not dropped', () async {
      final rig = Rig();
      final other = FakeTarget(kOther);
      rig.targets.register(other);
      await rig.run([
        poll(x: 300, y: 300),
        poll(x: 150, y: 200, view: kOther, down: false),
      ]);
      // Never shown, so there is nothing to clear either.
      expect(other.events, isEmpty);
      expect(rig.host.result!.outcome, TabDragOutcome.detached);
    });

    test('screen positions are turned into the window\'s own', () async {
      final rig = Rig();
      final other = FakeTarget(kOther);
      rig.targets.register(other);
      // The window starts at screen (1000, 500) at 200% scale: the cursor at
      // screen (1500, 520) is at (250, 10) in the window, which is slot 2.
      await rig.run([
        poll(x: 300, y: 300),
        poll(x: 1500, y: 520, view: kOther, ox: 1000, oy: 500, scale: 2),
      ]);
      expect(other.events, ['show 2']);
    });

    test('leaving a strip clears it', () async {
      final rig = Rig();
      final other = FakeTarget(kOther);
      rig.targets.register(other);
      await rig.run([
        poll(x: 300, y: 300),
        poll(x: 150, y: 10, view: kOther),
        poll(x: 150, y: 400), // over nothing
      ]);
      expect(other.events, ['show 1', 'clear']);
      await rig.run([poll(x: 150, y: 400)]);
      expect(rig.platform.requests.last.park, isFalse);
    });

    test(
      'back over its own strip: the tab is home, the carrier parks',
      () async {
        final rig = Rig();
        await rig.run([poll(x: 300, y: 300)]);
        expect(rig.host.opened, 1);
        rig.host.inSource = true;
        await rig.run([poll(x: 100, y: 10, view: kSource)]);
        expect(rig.host.returnedCalls, [true]);
        await rig.run([poll(x: 100, y: 10, view: kSource)]);
        expect(rig.platform.requests.last.park, isTrue);
        // Letting go there ends the drag at home and closes the carrier.
        await rig.run([poll(x: 100, y: 10, view: kSource, down: false)]);
        expect(rig.host.result!.outcome, TabDragOutcome.returned);
        expect(rig.host.closed, 1);
        // Going out again would not have made a second window.
        expect(rig.host.opened, 1);
      },
    );

    test('out again after coming back reuses the carrier', () async {
      final rig = Rig();
      await rig.run([poll(x: 300, y: 300)]);
      rig.host.inSource = true;
      await rig.run([poll(x: 100, y: 10, view: kSource)]);
      rig.host.inSource = false;
      await rig.run([poll(x: 100, y: 200, view: kSource)]);
      expect(rig.host.returnedCalls, [true, false]);
      expect(rig.host.opened, 1);
      await rig.run([poll(x: 100, y: 200, down: false)]);
      expect(rig.host.result!.outcome, TabDragOutcome.detached);
    });

    test('a window that cannot be opened cancels the drag', () async {
      final rig = Rig()..host.canOpen = false;
      await rig.run([poll(x: 300, y: 300), poll(x: 300, y: 300, down: false)]);
      expect(rig.host.result!.outcome, TabDragOutcome.cancelled);
    });
  });

  group('a window\'s only tab', () {
    test('moves the window itself', () async {
      final rig = Rig(alone: true);
      await rig.run([poll(x: 300, y: 300), poll(x: 400, y: 350)]);
      expect(rig.host.opened, 0);
      for (final request in rig.platform.requests) {
        expect(request.carrierViewId, kSource);
        expect(request.park, isFalse);
      }
      await rig.run([poll(x: 410, y: 350, down: false)]);
      expect(rig.host.result!.outcome, TabDragOutcome.movedWindow);
      expect(rig.host.closed, 0);
    });

    test('parks over a strip and is dropped into it', () async {
      final rig = Rig(alone: true);
      final other = FakeTarget(kOther);
      rig.targets.register(other);
      await rig.run([
        poll(x: 300, y: 300),
        poll(x: 50, y: 10, view: kOther),
        poll(x: 50, y: 10, view: kOther),
      ]);
      expect(rig.platform.requests.last.park, isTrue);
      await rig.run([poll(x: 50, y: 10, view: kOther, down: false)]);
      expect(rig.host.result!.outcome, TabDragOutcome.dropped);
      expect(other.events.contains('drop 0'), isTrue);
    });

    test(
      'is put back under the cursor if let go after leaving a strip',
      () async {
        final rig = Rig(alone: true);
        final other = FakeTarget(kOther);
        rig.targets.register(other);
        await rig.run([
          poll(x: 50, y: 10, view: kOther), // parked from the next step
          poll(x: 50, y: 10, view: kOther),
          poll(x: 600, y: 400, down: false), // let go away from any strip
        ]);
        expect(rig.host.result!.outcome, TabDragOutcome.movedWindow);
        expect(rig.platform.requests.last.park, isFalse);
        expect(rig.platform.requests.last.carrierViewId, kSource);
      },
    );

    test(
      'a window that had to be restored keeps the grip proportionally',
      () async {
        final rig = Rig(alone: true, grabX: 800);
        rig.platform.prepareRatio = 0.5;
        rig.platform.script.add(poll(x: 10, y: 10));
        await rig.session.start();
        await rig.session.finishNow();
        expect(rig.platform.requests.first.grabX, 400);
        rig.session.abort();
      },
    );

    test('the source is never offered as a place to drop into', () async {
      final rig = Rig(alone: true);
      final own = FakeTarget(kSource);
      rig.targets.register(own);
      await rig.run([poll(x: 100, y: 10, view: kSource, down: false)]);
      expect(own.events, isEmpty);
      expect(rig.host.result!.outcome, TabDragOutcome.movedWindow);
    });
  });

  group('the windows that move are never targets', () {
    test('the carrier is not offered as a place to drop into', () async {
      final rig = Rig();
      final carrierTarget = FakeTarget(kCarrier);
      rig.targets.register(carrierTarget);
      await rig.run([
        poll(x: 300, y: 300),
        poll(x: 100, y: 10, view: kCarrier, down: false),
      ]);
      expect(carrierTarget.events, isEmpty);
      expect(rig.host.result!.outcome, TabDragOutcome.detached);
    });
  });

  group('ending', () {
    test('a platform that fails gives the drag up', () async {
      final rig = Rig();
      rig.platform.script.add(null);
      await rig.session.tick();
      expect(rig.host.result!.outcome, TabDragOutcome.cancelled);
    });

    test('finishing now settles on a fresh look at the cursor', () async {
      final rig = Rig();
      final other = FakeTarget(kOther);
      rig.targets.register(other);
      rig.platform.script.addAll([
        poll(x: 300, y: 300),
        poll(x: 150, y: 10, view: kOther), // still reads as held
      ]);
      await rig.session.tick();
      await rig.session.finishNow();
      expect(rig.host.result!.outcome, TabDragOutcome.dropped);
      expect(rig.host.finishedCalls, 1);
    });

    test('is settled only once', () async {
      final rig = Rig();
      await rig.run([poll(x: 300, y: 300, down: false)]);
      await rig.session.finishNow();
      await rig.session.tick();
      expect(rig.host.finishedCalls, 1);
    });

    test('giving up mid-drag closes the carrier and drops nothing', () async {
      final rig = Rig();
      final other = FakeTarget(kOther);
      rig.targets.register(other);
      await rig.run([poll(x: 300, y: 300), poll(x: 150, y: 10, view: kOther)]);
      rig.session.abort();
      expect(rig.host.result!.outcome, TabDragOutcome.cancelled);
      expect(rig.host.closed, 1);
      expect(other.events, ['show 1', 'clear']);
    });
  });
}
