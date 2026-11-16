import 'dart:async';

import 'package:vaultexplorer/core/utils/ve_log.dart';

/// Aggregated timings for one named operation over the current window.
///
/// Durations are kept as a count / total / max plus a log2 histogram (bucket
/// `b` holds durations in `[2^(b-1), 2^b)` microseconds), which is enough to
/// report a median and a 95th percentile without storing every sample.
class PerfStat {
  int count = 0;
  int totalUs = 0;
  int maxUs = 0;
  final List<int> buckets = List<int>.filled(44, 0);

  void add(int us) {
    if (us < 0) us = 0;
    count++;
    totalUs += us;
    if (us > maxUs) maxUs = us;
    final b = us.bitLength;
    buckets[b < buckets.length ? b : buckets.length - 1]++;
  }

  /// Upper bound (µs) of the bucket that contains the [p]-th percentile.
  int percentileUpperBoundUs(double p) {
    if (count == 0) return 0;
    final target = (count * p).ceil().clamp(1, count);
    var seen = 0;
    for (var b = 0; b < buckets.length; b++) {
      seen += buckets[b];
      if (seen >= target) {
        if (b == 0) return 0;
        final upper = 1 << b;
        return upper < maxUs ? upper : maxUs;
      }
    }
    return maxUs;
  }
}

/// A level (queue depth, cache size, ...) sampled repeatedly over a window.
class PerfGauge {
  int count = 0;
  int sum = 0;
  int max = 0;
  int last = 0;

  void add(int value) {
    count++;
    sum += value;
    if (value > max) max = value;
    last = value;
  }
}

/// Lightweight, allocation-free-when-off performance tracing.
///
/// Turn it on with the existing **Debug logging** switch in Settings (the
/// same one that drives [VeLog]), or build with `--dart-define=VE_PERF=true`.
/// While on, every [begin]/[end] pair, [record] and [count] is aggregated in
/// memory and a summary is printed every [flushInterval]:
///
/// ```
/// [VE_PERF] ── window 10.0s ──────────────────────────────
/// [VE_PERF] thumb.fetch  n=84  total=3.46s avg=41ms p50<=32ms p95<=131ms max=212ms
/// [VE_PERF] counters: thumb.mem_hit=412 thumb.disk_hit=61
/// ```
///
/// Rows are sorted by total time, so the first lines are the biggest
/// contributors. When tracing is off, [begin] returns 0 and every other call
/// returns immediately — no clock reads, no string work, no allocation.
///
/// Typical use:
/// ```dart
/// final t0 = PerfTrace.begin();
/// final result = await doWork();
/// PerfTrace.end('feature.work', t0);          // or slowMs: 50 to also log outliers
/// ```
///
/// Everything printed goes to logcat under the `flutter` tag prefixed with
/// `[VE_PERF]`, so `adb logcat | grep VE_PERF` (or the in-app Logcat screen)
/// shows it. Native (Kotlin) timings use the same prefix.
abstract final class PerfTrace {
  static const bool _forced = bool.fromEnvironment('VE_PERF');

  /// Whether tracing is active right now.
  static bool get enabled => _forced || VeLog.enabled;

  /// Where finished lines go. Replaced in tests.
  static void Function(String line) sink = _defaultSink;

  /// How often an aggregated summary is printed while tracing is on.
  static Duration flushInterval = const Duration(seconds: 10);

  /// Most individual `SLOW` lines printed per window (the rest are counted
  /// under `perf.slow_suppressed`), so a pathological scroll cannot flood
  /// logcat and distort the very thing being measured.
  static int maxSlowLinesPerWindow = 20;

  /// How long after the last scroll sample the app still counts as
  /// "scrolling" for tagging frame timings.
  static const Duration scrollGrace = Duration(milliseconds: 300);

  static final Stopwatch _clock = Stopwatch()..start();
  static final Map<String, PerfStat> _stats = <String, PerfStat>{};
  static final Map<String, int> _counters = <String, int>{};
  static final Map<String, PerfGauge> _gauges = <String, PerfGauge>{};
  static Timer? _timer;
  static bool _headerPrinted = false;
  static int _windowStartUs = 0;
  static int _slowLines = 0;
  static int _lastScrollUs = -(1 << 40);

  /// Describes the environment (build mode, device tier, queue sizes, ...).
  /// Printed once at the start of every tracing session, so a captured log
  /// says what it was captured on. Set by app start-up.
  static List<String> Function()? describeEnvironment;

  /// Functions that record [gauge] values (queue depth, cache sizes). Run by
  /// [sampleGauges], which the frame monitor calls about every 100 ms while
  /// tracing is on, and once more right before each summary.
  static final List<void Function()> samplers = <void Function()>[];

  static void _defaultSink(String line) {
    // ignore: avoid_print
    print('[VE_PERF] $line');
  }

  // ── Recording ─────────────────────────────────────────────────────────────

  /// Starts a measurement. Returns 0 (and does nothing) when tracing is off.
  static int begin() => enabled ? _clock.elapsedMicroseconds + 1 : 0;

  /// Finishes a measurement started with [begin]. A [slowMs] above 0 also
  /// prints an immediate `SLOW` line when this one call took at least that
  /// long (rate-limited, see [maxSlowLinesPerWindow]).
  static void end(String name, int startToken, {int slowMs = 0}) {
    if (startToken == 0) return;
    final us = _clock.elapsedMicroseconds + 1 - startToken;
    record(name, us);
    if (slowMs > 0 && us >= slowMs * 1000) _slow(name, us);
  }

  /// Adds one duration sample (microseconds) under [name].
  static void record(String name, int micros) {
    if (!enabled) return;
    _ensureTimer();
    (_stats[name] ??= PerfStat()).add(micros);
  }

  /// Adds [n] to the counter [name] (cache hits, cancellations, …).
  static void count(String name, [int n = 1]) {
    if (!enabled) return;
    _ensureTimer();
    _counters[name] = (_counters[name] ?? 0) + n;
  }

  /// Records the current value of a level (not a duration) under [name]; the
  /// summary shows its average and maximum over the window.
  static void gauge(String name, int value) {
    if (!enabled) return;
    _ensureTimer();
    (_gauges[name] ??= PerfGauge()).add(value);
  }

  /// Runs every registered sampler once.
  static void sampleGauges() {
    if (!enabled) return;
    for (final sampler in samplers) {
      try {
        sampler();
      } catch (_) {
        // A sampler must never be able to break the app.
      }
    }
  }

  /// Notes that a scrollable just moved, so frame timings reported soon after
  /// can be told apart as "while scrolling" vs "idle".
  static void markScroll() {
    if (!enabled) return;
    _lastScrollUs = _clock.elapsedMicroseconds;
  }

  /// True while a scroll is in progress (or ended less than [scrollGrace] ago).
  static bool get isScrolling =>
      _clock.elapsedMicroseconds - _lastScrollUs < scrollGrace.inMicroseconds;

  // ── Reporting ─────────────────────────────────────────────────────────────

  static void _slow(String name, int us) {
    if (_slowLines >= maxSlowLinesPerWindow) {
      _counters['perf.slow_suppressed'] =
          (_counters['perf.slow_suppressed'] ?? 0) + 1;
      return;
    }
    _slowLines++;
    sink('SLOW $name ${_fmt(us)}');
  }

  static void _ensureTimer() {
    if (_timer != null) return;
    _windowStartUs = _clock.elapsedMicroseconds;
    _timer = Timer.periodic(flushInterval, (_) => flush());
  }

  /// Prints the current window's summary and starts a new window.
  /// Does nothing (and stops the timer) once tracing has been switched off.
  static void flush() {
    if (!enabled) {
      reset();
      return;
    }
    sampleGauges();
    if (_stats.isEmpty && _counters.isEmpty && _gauges.isEmpty) return;

    if (!_headerPrinted) {
      _headerPrinted = true;
      try {
        final header = describeEnvironment?.call();
        if (header != null) {
          sink('── environment ──────────────────────');
          header.forEach(sink);
        }
      } catch (_) {
        // The header is a convenience; never let it break the summary.
      }
    }

    final nowUs = _clock.elapsedMicroseconds;
    final windowS = (nowUs - _windowStartUs) / 1e6;
    sink('── window ${windowS.toStringAsFixed(1)}s ──────────────────────');

    final rows = _stats.entries.toList()
      ..sort((a, b) => b.value.totalUs.compareTo(a.value.totalUs));
    for (final e in rows.take(40)) {
      final s = e.value;
      sink(
        '${e.key.padRight(28)} n=${s.count} '
        'total=${_fmt(s.totalUs)} avg=${_fmt(s.totalUs ~/ s.count)} '
        'p50<=${_fmt(s.percentileUpperBoundUs(0.5))} '
        'p95<=${_fmt(s.percentileUpperBoundUs(0.95))} max=${_fmt(s.maxUs)}',
      );
    }
    if (_counters.isNotEmpty) {
      final keys = _counters.keys.toList()..sort();
      sink('counters: ${keys.map((k) => '$k=${_counters[k]}').join(' ')}');
    }

    if (_gauges.isNotEmpty) {
      final keys = _gauges.keys.toList()..sort();
      sink(
        'gauges: ${keys.map((k) {
          final g = _gauges[k]!;
          return '$k=avg ${g.sum ~/ g.count}/max ${g.max}';
        }).join(' ')}',
      );
    }

    _stats.clear();
    _counters.clear();
    _gauges.clear();
    _slowLines = 0;
    _windowStartUs = nowUs;
  }

  /// Drops all collected data and stops the flush timer.
  static void reset() {
    _timer?.cancel();
    _timer = null;
    _stats.clear();
    _counters.clear();
    _gauges.clear();
    _slowLines = 0;
    _headerPrinted = false;
  }

  /// The stats collected so far this window, by name (for tests/debugging).
  static PerfStat? statFor(String name) => _stats[name];

  /// The gauge collected so far this window (for tests/debugging).
  static PerfGauge? gaugeFor(String name) => _gauges[name];

  /// The counter value collected so far this window (for tests/debugging).
  static int counterFor(String name) => _counters[name] ?? 0;

  static String _fmt(int us) {
    if (us >= 1000000) return '${(us / 1e6).toStringAsFixed(2)}s';
    if (us >= 1000) return '${(us / 1000).toStringAsFixed(us >= 10000 ? 0 : 1)}ms';
    return '${us}us';
  }
}
