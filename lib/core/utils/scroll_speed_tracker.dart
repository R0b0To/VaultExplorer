import 'dart:async';

/// Tells whether a scrollable is moving too fast for what it shows to be read.
///
/// Fed with the scroll offset every time it changes ([sample]); it keeps a
/// smoothed speed and reports `fast` with a little hysteresis (it takes
/// [enterScreensPerSecond] to become fast and less than [exitScreensPerSecond]
/// to stop being), so the answer does not flicker around the threshold. When no
/// sample arrives for [idleTimeout] the scrollable is not moving at all.
///
/// Speeds are measured in *viewport heights per second* rather than pixels, so
/// the same numbers work for a phone and a tablet.
///
/// This is the only thing that ever holds back thumbnails or layout changes
/// while scrolling, and it holds them back only while the content is a blur:
/// as soon as the speed falls below [exitScreensPerSecond] (well before the
/// scroll stops) everything resumes. Set [enterScreensPerSecond] to infinity
/// and nothing is ever held back.
class ScrollSpeedTracker {
  ScrollSpeedTracker({
    required this.onFastChanged,
    this.enterScreensPerSecond = 2.5,
    this.exitScreensPerSecond = 1.2,
    this.idleTimeout = const Duration(milliseconds: 120),
    this.smoothing = 0.5,
  }) : assert(exitScreensPerSecond <= enterScreensPerSecond);

  final void Function(bool fast) onFastChanged;
  final double enterScreensPerSecond;
  final double exitScreensPerSecond;
  final Duration idleTimeout;

  /// Weight of the newest measurement in the smoothed speed (0..1).
  final double smoothing;

  bool _fast = false;
  double _speed = 0; // pixels per second, smoothed
  double? _lastPixels;
  Duration? _lastTime;
  Timer? _idleTimer;

  bool get isFast => _fast;

  /// The smoothed speed in pixels per second (for tests and debugging).
  double get pixelsPerSecond => _speed;

  /// Reports that the scroll offset is [pixels] at time [now] (any monotonic
  /// clock) in a viewport [viewportExtent] tall.
  void sample(double pixels, double viewportExtent, Duration now) {
    if (viewportExtent <= 0) return;
    final lastPixels = _lastPixels;
    final lastTime = _lastTime;
    if (lastPixels != null && lastTime != null) {
      final seconds = (now - lastTime).inMicroseconds / 1e6;
      // Two events in the same frame say nothing about speed; let the distance
      // build up until there is a measurable interval.
      if (seconds < 0.004) return;
      final instant = (pixels - lastPixels).abs() / seconds;
      _speed = _speed * (1 - smoothing) + instant * smoothing;
    }
    _lastPixels = pixels;
    _lastTime = now;

    final threshold =
        viewportExtent * (_fast ? exitScreensPerSecond : enterScreensPerSecond);
    _set(_speed > threshold);

    _idleTimer?.cancel();
    _idleTimer = Timer(idleTimeout, _becameIdle);
  }

  void _becameIdle() {
    _speed = 0;
    _lastPixels = null;
    _lastTime = null;
    _set(false);
  }

  void _set(bool fast) {
    if (fast == _fast) return;
    _fast = fast;
    onFastChanged(fast);
  }

  void dispose() {
    _idleTimer?.cancel();
    _idleTimer = null;
  }
}
