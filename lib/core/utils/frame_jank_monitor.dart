import 'dart:ui' show FrameTiming, PlatformDispatcher;

import 'package:flutter/scheduler.dart';
import 'package:vaultexplorer/core/utils/perf_trace.dart';

/// Feeds Flutter's per-frame timings into [PerfTrace] so dropped frames show
/// up in the same log as everything else, split by what the app was doing.
///
/// For each frame it records how long the UI thread took to build it
/// (`frame.build.*`) and how long the raster thread took to draw it
/// (`frame.raster.*`), tagged `.scroll` while a scrollable is moving (see
/// `PerfTrace.markScroll`) and `.idle` otherwise. It also counts frames that
/// overran the display's budget:
///
/// * `frame.jank.build.*`   -- UI thread over budget: too much work in
///   `build`/layout/paint callbacks, or work done synchronously on the UI
///   isolate (parsing, sorting, platform-channel decoding).
/// * `frame.jank.raster.*`  -- raster thread over budget: too much to draw
///   (large images decoded late, many layers, expensive clips/shadows).
///
/// That distinction is the first thing to know when a scroll stutters.
/// Does nothing unless tracing is on (see [PerfTrace.enabled]).
abstract final class FrameJankMonitor {
  static bool _started = false;
  static int? _budgetUs;

  /// Starts listening. Safe to call more than once.
  static void start() {
    if (_started) return;
    _started = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  /// Microseconds one frame may take at the display's refresh rate.
  static int get budgetUs => _budget;

  static int get _budget {
    return _budgetUs ??= () {
      try {
        final views = PlatformDispatcher.instance.views;
        final hz = views.isEmpty ? 60.0 : views.first.display.refreshRate;
        if (hz >= 30 && hz <= 240) return (1e6 / hz).round();
      } catch (_) {
        // Fall through to the 60 Hz default.
      }
      return 16667;
    }();
  }

  static void _onTimings(List<FrameTiming> timings) {
    if (!PerfTrace.enabled) return;
    // About every 100 ms: take a reading of queue depths and cache sizes.
   PerfTrace.sampleGauges();
    PerfTrace.gauge('frame.tickers', SchedulerBinding.instance.transientCallbackCount);
    final tag = PerfTrace.isScrolling ? 'scroll' : 'idle';
    final budget = _budget;
    for (final t in timings) {
      final build = t.buildDuration.inMicroseconds;
      final raster = t.rasterDuration.inMicroseconds;
      PerfTrace.record('frame.build.$tag', build);
      PerfTrace.record('frame.raster.$tag', raster);
      PerfTrace.count('frame.total.$tag');
      if (build > budget) PerfTrace.count('frame.jank.build.$tag');
      if (raster > budget) PerfTrace.count('frame.jank.raster.$tag');
      if (t.totalSpan.inMicroseconds > budget * 2) {
        PerfTrace.count('frame.severe.$tag');
      }
    }
  }
}
