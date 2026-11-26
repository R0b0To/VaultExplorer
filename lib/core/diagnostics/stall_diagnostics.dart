import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' show FrameTiming;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';

/// Temporary diagnostics for "the app stops answering inputs while music plays".
///
/// Writes `vaultexplorer_stall.log` in the system temp folder (the path is
/// printed to the console once). It never logs file names or paths: only
/// operation names, durations and counters. On unless it is a release build
/// (or `--dart-define=VE_STALL_DIAG=true`).
///
/// What the log tells apart:
///  * `WATCHDOG: main isolate silent` — a separate isolate noticed that the UI
///    isolate stopped answering, and keeps saying so until it answers again,
///    with what the app was doing when it went quiet. That is a blocked or
///    starved UI isolate.
///  * `lag: event loop ...` — the UI isolate was late (blocked or flooded) by
///    that much; written when it catches up.
///  * `pool: op=... total=... exec=... queue=...` — an engine call that took
///    long, split into time waiting for a worker and time inside the engine.
///    Inputs that wait for the engine look "stuck" with a healthy UI isolate.
///  * `frame: slow` — a frame whose build or raster took long.
///  * `stats 5s` — counters per five seconds: a flood of anything shows here.
///  * `semantics:` — whether an accessibility client (a screen reader, a UI
///    Automation tool) has switched semantics on, and `semantics.update` in the
///    stats: how many semantics updates were sent to it. On Windows those go
///    to the client on the platform thread.
///  * `media:` / `smtc:` — the system media controls (state changes, commands
///    and how late they arrived).
abstract final class StallDiagnostics {
  static final bool enabled =
      !kReleaseMode || const bool.fromEnvironment('VE_STALL_DIAG');

  static bool _started = false;
  static SendPort? _sink;
  static String? logPath;

  static final Map<String, int> _counters = <String, int>{};
  static final Map<String, String Function()> _contexts =
      <String, String Function()>{};
  static final Map<int, _InFlight> _inFlight = <int, _InFlight>{};
  static int _nextId = 0;
  static int _maxLagMs = 0;
  static int _frames = 0;
  static int _slowFrames = 0;

  /// Starts the log, the watchdog isolate and the monitors. Safe to repeat.
  static Future<void> start() async {
    if (!enabled || _started) return;
    _started = true;
    final path =
        '${Directory.systemTemp.path}${Platform.pathSeparator}vaultexplorer_stall.log';
    logPath = path;
    try {
      final ready = ReceivePort();
      await Isolate.spawn(
        _watchdogMain,
        <Object?>[ready.sendPort, path],
        debugName: 've-stall-watchdog',
      );
      _sink = await ready.first as SendPort;
    } catch (e) {
      debugPrint('[StallDiagnostics] could not start: $e');
      return;
    }
    debugPrint('[StallDiagnostics] writing to $path');
    log('diag', 'started (pid $pid, ${Platform.operatingSystem})');

    registerContext('scheduler', () {
      final s = SchedulerBinding.instance;
      return 'tickers=${s.transientCallbackCount} frameScheduled=${s.hasScheduledFrame}';
    });

    // Heartbeat for the watchdog isolate, with a snapshot of what is going on.
    Timer.periodic(const Duration(milliseconds: 200), (_) {
      _sink?.send(<Object?>[
        'hb',
        DateTime.now().microsecondsSinceEpoch,
        _context(),
      ]);
    });

    // How late the UI isolate's own timers fire.
    final clock = Stopwatch()..start();
    var last = 0;
    Timer.periodic(const Duration(milliseconds: 50), (_) {
      final now = clock.elapsedMilliseconds;
      final lag = now - last - 50;
      last = now;
      if (lag > _maxLagMs) _maxLagMs = lag;
      if (lag > 250) {
        log('lag', 'event loop was late by ${lag}ms; ${_context()}');
      }
    });

    registerContext(
      'semantics',
      () => SemanticsBinding.instance.semanticsEnabled ? 'on' : 'off',
    );
    _hookSemantics();
    SemanticsBinding.instance.addSemanticsEnabledListener(_hookSemantics);

    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
    Timer.periodic(const Duration(seconds: 5), (_) => _printStats());
  }

  /// A line in the log (no file names or paths).
  static void log(String tag, String message) {
    _sink?.send(<Object?>[
      'log',
      DateTime.now().microsecondsSinceEpoch,
      '$tag: $message',
    ]);
  }

  static void bump(String key, [int by = 1]) {
    if (!_started) return;
    _counters[key] = (_counters[key] ?? 0) + by;
  }

  /// A one-line description of some state, shown with every stall report.
  static void registerContext(String name, String Function() describe) {
    _contexts[name] = describe;
  }

  /// Runs [body], counting it under [key] and logging it when it took more
  /// than [warnMs].
  static T time<T>(String key, T Function() body, {int warnMs = 8}) {
    if (!_started) return body();
    final watch = Stopwatch()..start();
    try {
      return body();
    } finally {
      bump(key);
      final ms = watch.elapsedMilliseconds;
      if (ms >= warnMs) log('slow', '$key took ${ms}ms');
    }
  }

  // ── Engine worker pool ────────────────────────────────────────────────

  static int poolBegin(String op, int workerLoad) {
    if (!_started) return -1;
    final id = _nextId++;
    _inFlight[id] = _InFlight(op, workerLoad);
    bump('pool.calls');
    bump('pool.op.$op');
    return id;
  }

  static void poolEnd(int id, {int execMicros = -1}) {
    if (id < 0) return;
    final call = _inFlight.remove(id);
    if (call == null) return;
    final total = call.watch.elapsedMilliseconds;
    if (total >= 300) {
      final exec = execMicros < 0 ? -1 : execMicros ~/ 1000;
      log(
        'pool',
        'op=${call.op} total=${total}ms exec=${exec}ms '
            'queue=${exec < 0 ? '?' : '${total - exec}'}ms '
            'workerLoadAtStart=${call.workerLoad}',
      );
    }
  }

  // ── Internals ─────────────────────────────────────────────────────────

  static String _context() {
    final parts = <String>[];
    _contexts.forEach((name, describe) {
      try {
        parts.add('$name{${describe()}}');
      } catch (e) {
        parts.add('$name{error $e}');
      }
    });
    final waiting = <String>[
      for (final c in _inFlight.values)
        if (c.watch.elapsedMilliseconds >= 300)
          '${c.op}:${c.watch.elapsedMilliseconds}ms',
    ];
    if (_inFlight.isNotEmpty) {
      parts.add(
        'pool{inFlight=${_inFlight.length}'
        '${waiting.isEmpty ? '' : ' slow=${waiting.take(6).join(',')}'}}',
      );
    }
    return parts.join(' ');
  }

  static void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      _frames++;
      final total = t.totalSpan.inMilliseconds;
      if (total >= 100) {
        _slowFrames++;
        log(
          'frame',
          'slow: total=${total}ms build=${t.buildDuration.inMilliseconds}ms '
              'raster=${t.rasterDuration.inMilliseconds}ms',
        );
      }
    }
  }

  static void _hookSemantics() {
    final enabled = SemanticsBinding.instance.semanticsEnabled;
    log('semantics', 'enabled=$enabled');
    if (!enabled) return;
    // Counts the updates the framework sends to the platform.
    RendererBinding.instance.rootPipelineOwner.semanticsOwner?.addListener(
      () => bump('semantics.update'),
    );
  }

  static void _onPointer(PointerEvent event) {
    bump('pointer.events');
    if (event is PointerDownEvent) {
      log('pointer', 'down (${event.kind.name}, buttons ${event.buttons})');
    }
  }

  static void _printStats() {
    final entries = _counters.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = entries
        .take(14)
        .map((e) => '${e.key}=${e.value}')
        .join(' ');
    log(
      'stats 5s',
      'frames=$_frames slowFrames=$_slowFrames maxLag=${_maxLagMs}ms '
          'inFlight=${_inFlight.length} | $top',
    );
    _counters.clear();
    _frames = 0;
    _slowFrames = 0;
    _maxLagMs = 0;
  }
}

class _InFlight {
  _InFlight(this.op, this.workerLoad);

  final String op;
  final int workerLoad;
  final Stopwatch watch = Stopwatch()..start();
}

/// The watchdog and the only writer of the log. It runs in its own isolate so
/// it keeps working, and keeps reporting, while the UI isolate is blocked.
void _watchdogMain(List<Object?> init) {
  final reply = init[0] as SendPort;
  final path = init[1] as String;
  final file = File(path).openSync(mode: FileMode.write);

  void write(int micros, String text) {
    final at = DateTime.fromMicrosecondsSinceEpoch(micros).toIso8601String();
    file.writeStringSync('$at $text\n');
    file.flushSync();
  }

  int nowMicros() => DateTime.now().microsecondsSinceEpoch;

  final port = ReceivePort();
  var lastHeartbeat = nowMicros();
  var lastContext = '';
  var silentSince = 0;
  var lastReport = 0;

  port.listen((Object? message) {
    final m = message as List<Object?>;
    if (m[0] == 'hb') {
      final now = nowMicros();
      if (silentSince != 0) {
        write(
          now,
          'WATCHDOG: main isolate answering again after '
          '${(now - silentSince) ~/ 1000}ms of silence',
        );
        silentSince = 0;
      }
      lastHeartbeat = now;
      lastContext = m[2] as String;
    } else {
      write(m[1] as int, m[2] as String);
    }
  });

  Timer.periodic(const Duration(milliseconds: 250), (_) {
    final now = nowMicros();
    final gap = now - lastHeartbeat;
    if (gap <= 1000000) return;
    if (silentSince == 0) {
      silentSince = lastHeartbeat;
      lastReport = now;
      write(
        now,
        'WATCHDOG: main isolate silent for ${gap ~/ 1000}ms. '
        'Last known state: $lastContext',
      );
    } else if (now - lastReport >= 2000000) {
      lastReport = now;
      write(now, 'WATCHDOG: main isolate STILL silent (${gap ~/ 1000}ms)');
    }
  });

  reply.send(port.sendPort);
}
