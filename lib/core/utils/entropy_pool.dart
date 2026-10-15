import 'dart:typed_data';

import 'package:flutter/foundation.dart';

/// Collects entropy from the user's touch movement for the volume-creation
/// wizards -- the equivalent of VeraCrypt desktop's "move your mouse as
/// randomly as possible" step.
///
/// The collected bytes are handed to the native layer (`userEntropy` argument
/// of the create calls), which XORs a SHA-512 keystream derived from them into
/// the random salts and master keys it draws from the OS generator. That
/// mixing can only ADD entropy -- the OS generator is always used as well, so a
/// predictable or hostile gesture can never weaken the keys. This class
/// therefore only has to gather plenty of timing/position jitter, not to judge
/// its quality.
///
/// Each accepted sample records 16 bytes: the finger position (1/256 px
/// fixed point, x then y), the pointer event's own timestamp, and a second,
/// independent microsecond clock read when the event was handled. Samples
/// closer than [minMoveDistance] to the previous accepted one are ignored, so
/// resting the finger (sensor noise only) cannot fill the pool.
///
/// The wizard owns one pool, listens for [isSatisfied] to enable "Next", and
/// calls [takeBytes] when it starts the create call. [dispose] wipes the buffer.
class EntropyPool extends ChangeNotifier {
  EntropyPool({
    this.requiredSamples = defaultRequiredSamples,
    this.minMoveDistance = defaultMinMoveDistance,
    int Function()? microsClock,
  })  : assert(requiredSamples > 0),
        _clock = microsClock ?? _defaultClock(),
        _capacity = requiredSamples * maxOvershootFactor,
        _data = Uint8List(requiredSamples * maxOvershootFactor * bytesPerSample),
        _preview = Uint8List(previewBytes);

  /// Accepted samples needed to fill the progress bar -- a few strokes
  /// across the pad.
  static const int defaultRequiredSamples = 400;

  /// Logical pixels the finger must travel between two accepted samples.
  static const double defaultMinMoveDistance = 6.0;

  /// Bytes stored per accepted sample (4 x uint32).
  static const int bytesPerSample = 16;

  /// Samples beyond [requiredSamples] that are still recorded (so a long
  /// scribble keeps adding), up to this multiple of it.
  static const int maxOvershootFactor = 2;

  /// Size of the display-only pool shown in the UI.
  static const int previewBytes = 16;

  final int requiredSamples;
  final double minMoveDistance;
  final int Function() _clock;
  final int _capacity;
  final Uint8List _data;
  final Uint8List _preview;

  int _count = 0;
  double _lastX = 0;
  double _lastY = 0;
  bool _hasLast = false;
  bool _skipped = false;
  bool _wiped = false;

  static int Function() _defaultClock() {
    final sw = Stopwatch()..start();
    return () => sw.elapsedMicroseconds;
  }

  /// Number of samples accepted so far.
  int get sampleCount => _count;

  /// 0.0 .. 1.0 progress towards [requiredSamples].
  double get progress => (_count / requiredSamples).clamp(0.0, 1.0);

  /// Whether enough movement has been collected.
  bool get isComplete => _count >= requiredSamples;

  /// Whether the user chose to continue with the device's secure random
  /// generator only (accessibility escape hatch: the step needs a finger
  /// moving over a pad). Collecting again clears this.
  bool get skipped => _skipped;

  /// What the wizard needs to let the user continue.
  bool get isSatisfied => isComplete || _skipped;

  /// Whether [takeBytes] will return anything: some movement was collected and
  /// the step was not skipped.
  bool get hasUserEntropy => !_skipped && _count > 0;

  /// A 16-byte rolling digest of the movement for the UI, as 32 hex characters.
  /// Purely a visual aid showing the pool being stirred -- NOT the keying
  /// material, which is only ever handed to the native layer.
  String get previewHex {
    final sb = StringBuffer();
    for (final b in _preview) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  /// Offers a pointer position (logical pixels, relative to the pad) and the
  /// pointer event's timestamp. Returns true when it was recorded.
  bool addSample(double x, double y, Duration eventTime) {
    if (_wiped || _count >= _capacity) return false;
    if (_hasLast) {
      final dx = x - _lastX;
      final dy = y - _lastY;
      if (dx * dx + dy * dy < minMoveDistance * minMoveDistance) return false;
    }
    _lastX = x;
    _lastY = y;
    _hasLast = true;

    final bd = ByteData.sublistView(_data, _count * bytesPerSample, (_count + 1) * bytesPerSample);
    bd.setUint32(0, (x * 256).round() & 0xFFFFFFFF);
    bd.setUint32(4, (y * 256).round() & 0xFFFFFFFF);
    bd.setUint32(8, eventTime.inMicroseconds & 0xFFFFFFFF);
    bd.setUint32(12, _clock() & 0xFFFFFFFF);

    // Display-only mixing (see previewHex).
    for (var j = 0; j < previewBytes; j++) {
      _preview[j] =
          (_preview[j] + bd.getUint8(j) + (_preview[(j + 1) % previewBytes] >> 3) + 1) & 0xFF;
    }

    _count++;
    _skipped = false;
    // Notify on every sample: the collector card animates with the pool.
    // Listeners that only care about completion compare isSatisfied themselves.
    notifyListeners();
    return true;
  }

  /// Continue without collecting: the native layer then uses the OS random
  /// generator alone (it is always part of the key material either way).
  void skip() {
    if (_wiped) return;
    _wipeBuffers();
    _skipped = true;
    notifyListeners();
  }

  /// Discards everything collected so far and starts over.
  void reset() {
    if (_wiped) return;
    _wipeBuffers();
    _skipped = false;
    notifyListeners();
  }

  /// A copy of the bytes collected so far (empty when skipped or nothing has
  /// been collected). The caller owns -- and should wipe -- the copy.
  Uint8List takeBytes() {
    if (!hasUserEntropy) return Uint8List(0);
    return Uint8List.fromList(Uint8List.sublistView(_data, 0, _count * bytesPerSample));
  }

  void _wipeBuffers() {
    _data.fillRange(0, _data.length, 0);
    _preview.fillRange(0, _preview.length, 0);
    _count = 0;
    _hasLast = false;
  }

  @override
  void dispose() {
    _wipeBuffers();
    _wiped = true;
    super.dispose();
  }
}
