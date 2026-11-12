import 'dart:async';

import 'package:test/test.dart';
import 'package:vaultexplorer/core/utils/scroll_speed_tracker.dart';

void main() {
  const viewport = 800.0;

  test('a steady slow scroll is never fast', () {
    final changes = <bool>[];
    final t = ScrollSpeedTracker(onFastChanged: changes.add);
    var offset = 0.0;
    for (var i = 0; i < 120; i++) {
      offset += 4; // 4 px per 16 ms = 250 px/s, a third of a screen per second
      t.sample(offset, viewport, Duration(milliseconds: 16 * i));
    }
    expect(t.isFast, isFalse);
    expect(changes, isEmpty);
    t.dispose();
  });

  test('a fast fling becomes fast quickly and stops being fast as it slows down', () {
    final changes = <bool>[];
    final t = ScrollSpeedTracker(onFastChanged: changes.add);
    var offset = 0.0;
    var ms = 0;
    // 8 px/ms = 8000 px/s = 10 screens per second.
    for (var i = 0; i < 10; i++) {
      offset += 128;
      ms += 16;
      t.sample(offset, viewport, Duration(milliseconds: ms));
    }
    expect(t.isFast, isTrue);
    // Decelerate geometrically; "fast" must end while it is still moving.
    var step = 128.0;
    var movingWhenSlow = false;
    for (var i = 0; i < 80; i++) {
      step *= 0.93;
      offset += step;
      ms += 16;
      t.sample(offset, viewport, Duration(milliseconds: ms));
      if (!t.isFast && step > 1) {
        movingWhenSlow = true;
        break;
      }
    }
    expect(movingWhenSlow, isTrue, reason: 'resumed while still scrolling');
    expect(changes, [true, false]);
    t.dispose();
  });

  test('hysteresis: hovering around the threshold does not flicker', () {
    final changes = <bool>[];
    final t = ScrollSpeedTracker(onFastChanged: changes.add, smoothing: 1.0);
    var offset = 0.0;
    var ms = 0;
    void move(double screensPerSecond) {
      final px = screensPerSecond * viewport * 0.016;
      offset += px;
      ms += 16;
      t.sample(offset, viewport, Duration(milliseconds: ms));
    }

    move(0.1);
    move(0.1);
    for (var i = 0; i < 20; i++) {
      move(i.isEven ? 2.6 : 1.8); // above "enter", then between exit and enter
    }
    expect(t.isFast, isTrue);
    expect(changes, [true], reason: 'stays fast while above the exit threshold');
    for (var i = 0; i < 3; i++) {
      move(1.0);
    }
    expect(t.isFast, isFalse);
    expect(changes, [true, false]);
    t.dispose();
  });

  test('speed is relative to the viewport, not to pixels', () {
    bool run(double viewportExtent) {
      final t = ScrollSpeedTracker(onFastChanged: (_) {}, smoothing: 1.0);
      var offset = 0.0;
      for (var i = 0; i < 10; i++) {
        offset += 1600 * 0.016; // 1600 px/s
        t.sample(offset, viewportExtent, Duration(milliseconds: 16 * (i + 1)));
      }
      final fast = t.isFast;
      t.dispose();
      return fast;
    }

    expect(run(500), isTrue); // 3.2 screens/s on a small viewport
    expect(run(1000), isFalse); // 1.6 screens/s on a tall one
  });

  test('jumps made by the scroll handle (huge distances) count as fast', () {
    final t = ScrollSpeedTracker(onFastChanged: (_) {});
    // The handle jumps a few screens per event.
    for (var i = 0; i < 6; i++) {
      t.sample(i * 4000.0, viewport, Duration(milliseconds: 16 * (i + 1)));
    }
    expect(t.isFast, isTrue);
    t.dispose();
  });

  test('events within the same few milliseconds do not produce a bogus speed', () {
    final t = ScrollSpeedTracker(onFastChanged: (_) {}, smoothing: 1.0);
    t.sample(0, viewport, const Duration(milliseconds: 100));
    // jumpTo fires start/update/end for one move: all at the same instant.
    t.sample(5, viewport, const Duration(milliseconds: 100));
    t.sample(10, viewport, const Duration(microseconds: 100500));
    expect(t.isFast, isFalse);
    expect(t.pixelsPerSecond, 0);
    t.dispose();
  });

  test('no samples for a moment means it is not moving', () async {
    final changes = <bool>[];
    final t = ScrollSpeedTracker(
      onFastChanged: changes.add,
      idleTimeout: const Duration(milliseconds: 20),
    );
    var offset = 0.0;
    for (var i = 0; i < 8; i++) {
      offset += 500;
      t.sample(offset, viewport, Duration(milliseconds: 16 * (i + 1)));
    }
    expect(t.isFast, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(t.isFast, isFalse);
    expect(changes, [true, false]);
    t.dispose();
  });

  test('infinite threshold disables the gate entirely', () {
    final t = ScrollSpeedTracker(
      onFastChanged: (_) {},
      enterScreensPerSecond: double.infinity,
      exitScreensPerSecond: double.infinity,
    );
    for (var i = 0; i < 20; i++) {
      t.sample(i * 100000.0, viewport, Duration(milliseconds: 16 * (i + 1)));
    }
    expect(t.isFast, isFalse);
    t.dispose();
  });
}
