import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:vaultexplorer/features/browser/viewer/native_video_controller.dart';

/// Estimates where playback is between the player's position reports.
///
/// The player reports its position a few times per second, so a bar that just
/// shows the last report moves in small jumps. This keeps the report it was
/// last given and adds the time that has passed since (at the playback speed),
/// which is what the ear is actually doing in between.
class PositionExtrapolator {
  PositionExtrapolator({int Function()? clockMs})
    : _clock = clockMs ?? _monotonicClock();

  /// A report that comes in this far behind the estimate is lag, not a seek:
  /// the estimate is kept so the bar never steps backwards.
  static const int lagToleranceMs = 350;

  /// Estimating past the last report by more than this means the player has
  /// stalled (buffering), so the estimate stops instead of running away.
  static const int maxAheadMs = 2500;

  final int Function() _clock;

  int _baseMs = 0;
  int _baseAt = 0;
  int _durationMs = 0;
  bool _playing = false;
  double _speed = 1;

  static int Function() _monotonicClock() {
    final watch = Stopwatch()..start();
    return () => watch.elapsedMilliseconds;
  }

  Duration get duration => Duration(milliseconds: _durationMs);

  bool get isPlaying => _playing;

  /// Takes the player's latest report.
  void report({
    required Duration position,
    required Duration duration,
    required bool playing,
    double speed = 1,
  }) {
    final estimate = this.estimate;
    var base = position.inMilliseconds;
    if (_playing && playing && base < estimate && estimate - base < lagToleranceMs) {
      base = estimate;
    }
    _baseMs = base;
    _baseAt = _clock();
    _durationMs = duration.inMilliseconds;
    _playing = playing;
    _speed = speed > 0 ? speed : 1;
  }

  /// Where playback is now, in milliseconds.
  int get estimate {
    var value = _baseMs;
    if (_playing) {
      final since = math.min(_clock() - _baseAt, maxAheadMs);
      value += (since * _speed).round();
    }
    if (_durationMs > 0 && value > _durationMs) value = _durationMs;
    return value < 0 ? 0 : value;
  }
}

/// Drives a [PositionExtrapolator] from a player and calls [onFrame] on every
/// frame while playing, with the smoothed position, so a progress bar glides
/// instead of stepping.
class SmoothPlaybackPosition {
  SmoothPlaybackPosition({
    required TickerProvider vsync,
    required this.onFrame,
  }) {
    _ticker = vsync.createTicker((_) => onFrame(position, duration));
  }

  final void Function(Duration position, Duration duration) onFrame;
  final PositionExtrapolator _extrapolator = PositionExtrapolator();
  late final Ticker _ticker;

  Duration get position => Duration(milliseconds: _extrapolator.estimate);

  Duration get duration => _extrapolator.duration;

  /// Feeds in the player's current value (call it on every change).
  void report(NativeVideoValue value, {double speed = 1}) {
    final playing = value.isInitialized && value.isPlaying;
    _extrapolator.report(
      position: value.position,
      duration: value.duration,
      playing: playing,
      speed: speed,
    );
    if (playing) {
      if (!_ticker.isActive) _ticker.start();
    } else if (_ticker.isActive) {
      _ticker.stop();
    }
    // Show the report itself right away (a seek while paused, a new track).
    onFrame(position, duration);
  }

  void stop() {
    if (_ticker.isActive) _ticker.stop();
  }

  void dispose() {
    _ticker.dispose();
  }
}
