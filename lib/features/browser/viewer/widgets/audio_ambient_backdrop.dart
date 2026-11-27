import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Picks the colours of an ambient backdrop out of a cover picture.
///
/// No palette package: the picture is decoded at a tiny size and its pixels
/// are bucketed by hue (weighted by how vivid they are), the way picks
/// its "vivid" colours. Everything stays in memory.
abstract class CoverPalette {
  /// How many colours [extract] returns.
  static const count = 4;

  static const _sectors = 12;
  static const _minHueDistance = 28.0;
  static const _maxVivid = 3;
  static const _artworkShare = 0.45;
  static const _variants = [
    (hue: 0.0, lightness: 0.0),
    (hue: 14.0, lightness: 0.07),
    (hue: -14.0, lightness: -0.06),
    (hue: 26.0, lightness: -0.02),
  ];

  /// [count] colours for [coverBytes], or an empty list when the picture
  /// cannot be decoded.
  static Future<List<Color>> extract(Uint8List coverBytes) async {
    final codec = await ui.instantiateImageCodec(coverBytes, targetWidth: 48);
    try {
      final frame = await codec.getNextFrame();
      final image = frame.image;
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (data == null) return const [];
        return fromRgba(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
      } finally {
        image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }

  /// Same as [extract] for already decoded RGBA pixels.
  @visibleForTesting
  static List<Color> fromRgba(Uint8List rgba) {
    final weight = List<double>.filled(_sectors, 0);
    final sumR = List<double>.filled(_sectors, 0);
    final sumG = List<double>.filled(_sectors, 0);
    final sumB = List<double>.filled(_sectors, 0);
    double allR = 0, allG = 0, allB = 0;
    var pixels = 0;

    for (var i = 0; i + 3 < rgba.length; i += 4) {
      if (rgba[i + 3] < 128) continue;
      final r = rgba[i], g = rgba[i + 1], b = rgba[i + 2];
      allR += r;
      allG += g;
      allB += b;
      pixels++;
      final hsl = HSLColor.fromColor(Color.fromARGB(255, r, g, b));
      if (hsl.saturation < 0.25 || hsl.lightness < 0.18 || hsl.lightness > 0.88) {
        continue;
      }
      final w = hsl.saturation * (1 - (2 * hsl.lightness - 1).abs());
      final sector = (hsl.hue / (360 / _sectors)).floor() % _sectors;
      weight[sector] += w;
      sumR[sector] += r * w;
      sumG[sector] += g * w;
      sumB[sector] += b * w;
    }
    if (pixels == 0) return const [];

    final order = List<int>.generate(_sectors, (i) => i)
      ..sort((a, b) => weight[b].compareTo(weight[a]));
    final vivid = <Color>[];
    final hues = <double>[];
    for (final s in order) {
      if (vivid.length == _maxVivid) break;
      if (weight[s] < pixels * 0.01) break;
      final color = Color.fromARGB(
        255,
        _byte(sumR[s] / weight[s]),
        _byte(sumG[s] / weight[s]),
        _byte(sumB[s] / weight[s]),
      );
      final hue = HSLColor.fromColor(color).hue;
      final repeated = hues.any((h) {
        final d = (h - hue).abs();
        return d < _minHueDistance || d > 360 - _minHueDistance;
      });
      if (repeated) continue;
      hues.add(hue);
      vivid.add(color);
    }

    // Grey or near-grey cover: fall back to its average tone.
    final base =
        vivid.isNotEmpty
        ? vivid.first
        : Color.fromARGB(
            255,
            _byte(allR / pixels),
            _byte(allG / pixels),
            _byte(allB / pixels),
          );
    return _compose(base, vivid);
  }

  static int _byte(double v) => math.min(255, math.max(0, v.round()));

  static List<Color> _compose(Color base, List<Color> vivid) {
    final source = HSLColor.fromColor(base);
    final saturation = math.min(0.55, math.max(0.22, source.saturation));
    final colors = List<Color>.filled(count, base);
    for (var i = 0; i < count; i++) {
      final v = _variants[i];
      final lightness = math.min(
        0.68,
        math.max(0.35, source.lightness + v.lightness),
      );
      colors[i] = source
          .withHue((source.hue + v.hue) % 360)
          .withSaturation(saturation)
          .withLightness(lightness)
          .toColor();
    }
    for (var i = 1; i < count && i <= vivid.length; i++) {
      final hsl = HSLColor.fromColor(vivid[i - 1]);
      final brightened = hsl
          .withSaturation(math.max(0.6, hsl.saturation))
          .withLightness(math.min(0.75, math.max(0.5, hsl.lightness)))
          .toColor();
      colors[i] = Color.lerp(colors[i], brightened, _artworkShare)!;
    }
    return colors;
  }
}

/// Slowly drifting, softly breathing coloured lights over a dark base tinted
/// by the cover
///
/// Meant to sit behind the player UI and fill the page. It repaints at about
/// 30 fps while [isPlaying] and stops its ticker while paused, so a paused
/// player costs nothing. It also stays still when the system asks for reduced
/// motion.
class AudioAmbientBackdrop extends StatefulWidget {
  /// Four colours, see [CoverPalette.extract].
  final List<Color> colors;
  final bool isPlaying;

  const AudioAmbientBackdrop({
    super.key,
    required this.colors,
    required this.isPlaying,
  });

  @override
  State<AudioAmbientBackdrop> createState() => _AudioAmbientBackdropState();
}

class _AudioAmbientBackdropState extends State<AudioAmbientBackdrop>
    with SingleTickerProviderStateMixin {
  static const _frameInterval = 1 / 30;

  late final _AmbientScene _scene = _AmbientScene(widget.colors);
  late final _AmbientPainter _painter = _AmbientPainter(_scene);
  late final Ticker _ticker = createTicker(_onTick);
  Duration _last = Duration.zero;
  double _sinceNotify = 0;
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant AudioAmbientBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.colors, widget.colors)) {
      _scene.setColors(widget.colors);
    }
    _syncTicker();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _scene.dispose();
    super.dispose();
  }

  void _syncTicker() {
    final shouldRun = widget.isPlaying && !_reduceMotion;
    if (shouldRun && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    } else if (!shouldRun && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _onTick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6)
        .clamp(0.0, 0.05)
        .toDouble();
    _last = elapsed;
    if (dt <= 0) return;
    _scene.time += dt;
    _sinceNotify += dt;
    if (_sinceNotify < _frameInterval) return;
    _sinceNotify = 0;
    _scene.notify();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox.expand(child: CustomPaint(painter: _painter)),
    );
  }
}

class _AmbientScene extends ChangeNotifier {
  List<Color> colors;
  double time = 0;

  _AmbientScene(this.colors);

  void setColors(List<Color> value) {
    colors = value;
    notifyListeners();
  }

  void notify() => notifyListeners();
}

class _AmbientPainter extends CustomPainter {
  final _AmbientScene scene;

  _AmbientPainter(this.scene) : super(repaint: scene);

  static const _lights = [
    (x: 0.20, y: 0.22, sx: 0.22, sy: 0.16, px: 0.13, py: 0.10, phase: 0.0, radius: 0.80, alpha: 0.55),
    (x: 0.80, y: 0.30, sx: 0.20, sy: 0.22, px: 0.09, py: 0.12, phase: 1.7, radius: 0.70, alpha: 0.50),
    (x: 0.28, y: 0.80, sx: 0.22, sy: 0.18, px: 0.11, py: 0.08, phase: 3.1, radius: 0.75, alpha: 0.50),
    (x: 0.78, y: 0.76, sx: 0.18, sy: 0.22, px: 0.12, py: 0.09, phase: 4.6, radius: 0.65, alpha: 0.45),
  ];
  static const _breath = 0.12;
  // Keeps the white title and the visualizer readable over the brightest glow.
  static const _scrimAlpha = 0.28;

  final _basePaint = Paint();
  final _scrimPaint = Paint()
    ..color = const Color(0xFF000000).withValues(alpha: _scrimAlpha);
  final _paints = List.generate(
    _lights.length,
    (_) => Paint()..blendMode = BlendMode.screen,
    growable: false,
  );
  final _shaded = List<Color?>.filled(_lights.length, null);
  Size _size = Size.zero;
  Color? _base;

  static Color _baseTone(Color color) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withSaturation(math.min(0.45, hsl.saturation))
        .withLightness(0.07)
        .toColor();
  }

  static ui.Gradient _glow(Color color, double radius) {
    return ui.Gradient.radial(
      Offset.zero,
      radius,
      [
        color,
        color.withValues(alpha: 0.72),
        color.withValues(alpha: 0.36),
        color.withValues(alpha: 0.12),
        color.withValues(alpha: 0.0),
      ],
      const [0.0, 0.22, 0.48, 0.74, 1.0],
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final colors = scene.colors;
    final time = scene.time;
    final resized = _size != size;
    _size = size;

    if (_base != colors.first) {
      _base = colors.first;
      _basePaint.color = _baseTone(colors.first);
    }
    canvas.drawRect(Offset.zero & size, _basePaint);

    final longest = size.longestSide;
    for (var i = 0; i < _lights.length; i++) {
      final light = _lights[i];
      final paint = _paints[i];
      final color = colors[i % colors.length];
      final radius = longest * light.radius;
      if (resized || _shaded[i] != color) {
        _shaded[i] = color;
        paint.shader = _glow(color, radius);
      }
      final breath = math.sin(time * 0.2 + light.phase);
      final alpha = (light.alpha + _breath * breath).clamp(0.0, 1.0).toDouble();
      paint.color = Color.fromRGBO(255, 255, 255, alpha);
      final dx =
          size.width * (light.x + light.sx * math.sin(time * light.px + light.phase));
      final dy =
          size.height *
          (light.y + light.sy * math.cos(time * light.py + light.phase * 1.3));
      canvas.save();
      canvas.translate(dx, dy);
      canvas.drawCircle(Offset.zero, radius, paint);
      canvas.restore();
    }
    canvas.drawRect(Offset.zero & size, _scrimPaint);
  }

  @override
  bool shouldRepaint(covariant _AmbientPainter oldDelegate) =>
      oldDelegate.scene != scene;
}
