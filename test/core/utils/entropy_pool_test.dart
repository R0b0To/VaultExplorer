import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/utils/entropy_pool.dart';

void main() {
  // Deterministic stand-in for the microsecond clock the pool reads per sample.
  int fakeMicros = 1000;
  int tick() => fakeMicros += 997;

  EntropyPool newPool({int required = 10, double minMove = 6.0}) =>
      EntropyPool(requiredSamples: required, minMoveDistance: minMove, microsClock: tick);

  /// Feeds [n] samples spaced 10 px apart; returns how many were accepted.
  int feed(EntropyPool pool, int n, {double startX = 0, double y = 5}) {
    var accepted = 0;
    for (var i = 0; i < n; i++) {
      if (pool.addSample(startX + i * 10.0, y, Duration(microseconds: 16000 * (i + 1)))) {
        accepted++;
      }
    }
    return accepted;
  }

  setUp(() => fakeMicros = 1000);

  test('starts empty and not satisfied', () {
    final pool = newPool();
    addTearDown(pool.dispose);
    expect(pool.sampleCount, 0);
    expect(pool.progress, 0.0);
    expect(pool.isComplete, isFalse);
    expect(pool.skipped, isFalse);
    expect(pool.isSatisfied, isFalse);
    expect(pool.hasUserEntropy, isFalse);
    expect(pool.takeBytes(), isEmpty);
    expect(pool.previewHex, '0' * 32);
  });

  test('progress follows accepted samples and completes at requiredSamples', () {
    final pool = newPool(required: 10);
    addTearDown(pool.dispose);
    feed(pool, 5);
    expect(pool.sampleCount, 5);
    expect(pool.progress, closeTo(0.5, 1e-9));
    expect(pool.isComplete, isFalse);
    expect(pool.isSatisfied, isFalse);
    feed(pool, 5, startX: 100);
    expect(pool.isComplete, isTrue);
    expect(pool.progress, 1.0);
    expect(pool.isSatisfied, isTrue);
  });

  test('moves shorter than minMoveDistance are ignored (resting finger)', () {
    final pool = newPool(minMove: 6.0);
    addTearDown(pool.dispose);
    expect(pool.addSample(50, 50, const Duration(milliseconds: 1)), isTrue);
    // 3 px away: sensor jitter, not movement.
    expect(pool.addSample(52, 52, const Duration(milliseconds: 2)), isFalse);
    expect(pool.addSample(50, 53, const Duration(milliseconds: 3)), isFalse);
    expect(pool.sampleCount, 1);
    // The reference point is the last ACCEPTED sample, so slow drift still adds up.
    expect(pool.addSample(50, 57, const Duration(milliseconds: 4)), isTrue);
    expect(pool.sampleCount, 2);
  });

  test('recording stops at the overshoot capacity', () {
    final pool = newPool(required: 4);
    addTearDown(pool.dispose);
    final accepted = feed(pool, 50);
    expect(accepted, 4 * EntropyPool.maxOvershootFactor);
    expect(pool.sampleCount, 4 * EntropyPool.maxOvershootFactor);
    expect(pool.takeBytes().length,
        4 * EntropyPool.maxOvershootFactor * EntropyPool.bytesPerSample);
    expect(pool.progress, 1.0);
  });

  test('takeBytes returns 16 bytes per sample encoding position, event time and clock', () {
    final pool = newPool();
    addTearDown(pool.dispose);
    pool.addSample(1.5, 2.25, const Duration(microseconds: 0x01020304));
    final bytes = pool.takeBytes();
    expect(bytes.length, EntropyPool.bytesPerSample);

    final bd = ByteData.sublistView(bytes);
    expect(bd.getUint32(0), (1.5 * 256).round());
    expect(bd.getUint32(4), (2.25 * 256).round());
    expect(bd.getUint32(8), 0x01020304);
    expect(bd.getUint32(12), 1000 + 997); // first tick() of the fake clock
  });

  test('takeBytes hands out an independent copy', () {
    final pool = newPool();
    addTearDown(pool.dispose);
    feed(pool, 3);
    final first = pool.takeBytes();
    final snapshot = Uint8List.fromList(first);
    first.fillRange(0, first.length, 0); // the caller wipes its copy
    expect(pool.takeBytes(), snapshot);
  });

  test('negative and large coordinates are stored without throwing', () {
    final pool = newPool();
    addTearDown(pool.dispose);
    expect(pool.addSample(-123.75, 99999.5, const Duration(days: 40)), isTrue);
    expect(pool.takeBytes().length, EntropyPool.bytesPerSample);
  });

  test('the preview changes as movement is added and is 32 hex chars', () {
    final pool = newPool();
    addTearDown(pool.dispose);
    final before = pool.previewHex;
    feed(pool, 3);
    final after = pool.previewHex;
    expect(after, isNot(before));
    expect(after, matches(RegExp(r'^[0-9a-f]{32}$')));
  });

  test('skip satisfies the step but hands over no bytes', () {
    final pool = newPool();
    addTearDown(pool.dispose);
    feed(pool, 3);
    pool.skip();
    expect(pool.skipped, isTrue);
    expect(pool.isSatisfied, isTrue);
    expect(pool.isComplete, isFalse);
    expect(pool.hasUserEntropy, isFalse);
    expect(pool.takeBytes(), isEmpty);
    expect(pool.sampleCount, 0); // what was collected is wiped
  });

  test('moving again after a skip starts a fresh collection', () {
    final pool = newPool(required: 3);
    addTearDown(pool.dispose);
    pool.skip();
    expect(pool.addSample(10, 10, const Duration(milliseconds: 1)), isTrue);
    expect(pool.skipped, isFalse);
    expect(pool.isSatisfied, isFalse);
    expect(pool.hasUserEntropy, isTrue);
    expect(pool.takeBytes().length, EntropyPool.bytesPerSample);
  });

  test('reset wipes everything and the next sample is accepted at any distance', () {
    final pool = newPool();
    addTearDown(pool.dispose);
    feed(pool, 5);
    pool.reset();
    expect(pool.sampleCount, 0);
    expect(pool.takeBytes(), isEmpty);
    expect(pool.previewHex, '0' * 32);
    // No "previous point" any more, so even the very same position counts.
    expect(pool.addSample(0, 5, const Duration(milliseconds: 1)), isTrue);
  });

  test('listeners are notified on samples, skip and reset', () {
    final pool = newPool();
    addTearDown(pool.dispose);
    var notified = 0;
    pool.addListener(() => notified++);
    pool.addSample(0, 0, const Duration(milliseconds: 1));
    expect(notified, 1);
    pool.addSample(0, 1, const Duration(milliseconds: 2)); // rejected: too close
    expect(notified, 1);
    pool.skip();
    expect(notified, 2);
    pool.reset();
    expect(notified, 3);
  });

  test('a disposed pool refuses new samples and yields nothing', () {
    final pool = newPool();
    feed(pool, 3);
    pool.dispose();
    expect(pool.addSample(500, 500, const Duration(milliseconds: 9)), isFalse);
    expect(pool.takeBytes(), isEmpty);
    expect(pool.sampleCount, 0);
  });

  test('the default pool needs a few strokes, not a handful of touches', () {
    final pool = EntropyPool();
    addTearDown(pool.dispose);
    expect(pool.requiredSamples, EntropyPool.defaultRequiredSamples);
    expect(pool.requiredSamples, greaterThanOrEqualTo(200));
  });
}
