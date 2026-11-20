import 'package:test/test.dart';
import 'package:vaultexplorer/core/utils/perf_trace.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';

void main() {
  late List<String> lines;

  setUp(() {
    PerfTrace.reset();
    PerfTrace.samplers.clear();
    PerfTrace.describeEnvironment = null;
    PerfTrace.maxSlowLinesPerWindow = 20;
    lines = <String>[];
    PerfTrace.sink = lines.add;
    VeLog.enabled = true;
  });

  tearDown(() {
    PerfTrace.reset();
    VeLog.enabled = false;
  });

  void busyWaitMs(int ms) {
    final sw = Stopwatch()..start();
    while (sw.elapsedMilliseconds < ms) {}
  }

  group('PerfTrace when tracing is off', () {
    test('begin returns 0 and nothing is recorded', () {
      VeLog.enabled = false;
      expect(PerfTrace.begin(), 0);
      PerfTrace.end('x', 0);
      PerfTrace.record('x', 5000);
      PerfTrace.count('c');
      expect(PerfTrace.statFor('x'), isNull);
      expect(PerfTrace.counterFor('c'), 0);
    });

    test('flush while off prints nothing', () {
      PerfTrace.record('x', 1000);
      VeLog.enabled = false;
      PerfTrace.flush();
      expect(lines, isEmpty);
    });
  });

  group('PerfTrace recording', () {
    test('begin/end records one sample under the name', () {
      final t0 = PerfTrace.begin();
      expect(t0, isNot(0));
      busyWaitMs(2);
      PerfTrace.end('work', t0);
      final stat = PerfTrace.statFor('work')!;
      expect(stat.count, 1);
      expect(stat.totalUs, greaterThanOrEqualTo(1500));
    });

    test('record and count accumulate', () {
      PerfTrace.record('a', 100);
      PerfTrace.record('a', 300);
      PerfTrace.count('hits');
      PerfTrace.count('hits', 4);
      final stat = PerfTrace.statFor('a')!;
      expect(stat.count, 2);
      expect(stat.totalUs, 400);
      expect(stat.maxUs, 300);
      expect(PerfTrace.counterFor('hits'), 5);
    });

    test('a negative duration is treated as zero', () {
      PerfTrace.record('neg', -50);
      expect(PerfTrace.statFor('neg')!.totalUs, 0);
    });
  });

  group('PerfStat percentiles', () {
    test('report the bucket upper bound, never above the max', () {
      final stat = PerfStat();
      for (var i = 0; i < 90; i++) {
        stat.add(100);
      }
      for (var i = 0; i < 10; i++) {
        stat.add(100000);
      }
      expect(stat.percentileUpperBoundUs(0.5), lessThanOrEqualTo(128));
      expect(stat.percentileUpperBoundUs(0.5), greaterThanOrEqualTo(100));
      expect(stat.percentileUpperBoundUs(0.95), 100000);
    });

    test('an empty stat reports 0', () {
      expect(PerfStat().percentileUpperBoundUs(0.95), 0);
    });
  });

  group('PerfTrace.flush', () {
    test('prints rows biggest total first, then counters, then resets', () {
      PerfTrace.record('small', 1000);
      PerfTrace.record('big', 900000);
      PerfTrace.record('big', 100000);
      PerfTrace.count('b.count', 2);
      PerfTrace.count('a.count');
      PerfTrace.flush();

      final rows = lines.where((l) => l.contains(' n=')).toList();
      expect(rows, hasLength(2));
      expect(rows.first.startsWith('big'), isTrue);
      expect(rows.last.startsWith('small'), isTrue);
      expect(rows.first.contains('n=2'), isTrue);
      expect(lines.last, 'counters: a.count=1 b.count=2');

      expect(PerfTrace.statFor('big'), isNull);
      expect(PerfTrace.counterFor('a.count'), 0);
      lines.clear();
      PerfTrace.flush(); // nothing new -> silent
      expect(lines, isEmpty);
    });
  });

  group('PerfTrace slow-call lines', () {
    test('end(slowMs:) prints SLOW for a slow call and not for a fast one', () {
      final fast = PerfTrace.begin();
      PerfTrace.end('fast', fast, slowMs: 10000);
      expect(lines.where((l) => l.startsWith('SLOW')), isEmpty);

      final slow = PerfTrace.begin();
      busyWaitMs(3);
      PerfTrace.end('slow', slow, slowMs: 1);
      expect(lines.where((l) => l.startsWith('SLOW slow')), hasLength(1));
    });

    test('lines are rate limited per window and the rest are counted', () {
      PerfTrace.maxSlowLinesPerWindow = 2;
      for (var i = 0; i < 5; i++) {
        final t0 = PerfTrace.begin();
        busyWaitMs(2);
        PerfTrace.end('slow', t0, slowMs: 1);
      }
      expect(lines.where((l) => l.startsWith('SLOW')), hasLength(2));
      expect(PerfTrace.counterFor('perf.slow_suppressed'), 3);
      // Every call is still aggregated.
      expect(PerfTrace.statFor('slow')!.count, 5);
    });
  });

  group('PerfTrace scroll tagging', () {
    test('isScrolling is true right after markScroll and false after the grace', () async {
      expect(PerfTrace.isScrolling, isFalse);
      PerfTrace.markScroll();
      expect(PerfTrace.isScrolling, isTrue);
      await Future<void>.delayed(PerfTrace.scrollGrace + const Duration(milliseconds: 60));
      expect(PerfTrace.isScrolling, isFalse);
    });

    test('markScroll does nothing while tracing is off', () {
      VeLog.enabled = false;
      PerfTrace.markScroll();
      expect(PerfTrace.isScrolling, isFalse);
    });
  });

  group('PerfTrace environment header', () {
    test('is printed once per session, before the first summary', () {
      PerfTrace.describeEnvironment = () => ['build=profile', 'tier=HIGH'];
      PerfTrace.record('x', 1000);
      PerfTrace.flush();
      expect(lines.first.contains('environment'), isTrue);
      expect(lines, contains('build=profile'));
      expect(lines, contains('tier=HIGH'));

      lines.clear();
      PerfTrace.record('x', 1000);
      PerfTrace.flush();
      expect(lines.contains('build=profile'), isFalse);

      // Switching tracing off and on again is a new session.
      PerfTrace.reset();
      PerfTrace.record('x', 1000);
      PerfTrace.flush();
      expect(lines, contains('build=profile'));
    });

    test('a throwing description does not break the summary', () {
      PerfTrace.describeEnvironment = () => throw StateError('boom');
      PerfTrace.record('x', 1000);
      PerfTrace.flush();
      expect(lines.where((l) => l.startsWith('x ')), hasLength(1));
    });

    test('nothing is printed without a description', () {
      PerfTrace.record('x', 1000);
      PerfTrace.flush();
      expect(lines.any((l) => l.contains('environment')), isFalse);
    });
  });

  group('PerfTrace gauges', () {
    test('report the average and maximum over the window, then reset', () {
      PerfTrace.gauge('queue.waiting', 2);
      PerfTrace.gauge('queue.waiting', 10);
      PerfTrace.gauge('queue.waiting', 6);
      PerfTrace.flush();
      expect(lines.last, 'gauges: queue.waiting=avg 6/max 10');
      expect(PerfTrace.gaugeFor('queue.waiting'), isNull);
    });

    test('sampleGauges runs every sampler and survives a failing one', () {
      var calls = 0;
      PerfTrace.samplers.add(() => throw StateError('bad sampler'));
      PerfTrace.samplers.add(() {
        calls++;
        PerfTrace.gauge('level', 7);
      });
      PerfTrace.sampleGauges();
      expect(calls, 1);
      expect(PerfTrace.gaugeFor('level')!.last, 7);
    });

    test('flush takes one last reading so a quiet window still reports', () {
      PerfTrace.samplers.add(() => PerfTrace.gauge('level', 3));
      PerfTrace.flush();
      expect(lines.last, 'gauges: level=avg 3/max 3');
    });

    test('are ignored while tracing is off', () {
      VeLog.enabled = false;
      PerfTrace.gauge('level', 3);
      expect(PerfTrace.gaugeFor('level'), isNull);
    });
  });
}
