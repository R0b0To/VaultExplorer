import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/features/camera/panorama/panorama_capture_controller.dart';
import 'package:vaultexplorer/features/camera/panorama/panorama_pose.dart';

/// Everything drawn over the camera preview while panorama / photo-sphere mode
/// is on: guide line, reticle and target dots, mini-map, mode switch, Done/Cancel
/// chips and hints.
class PanoramaCaptureOverlay extends StatelessWidget {
  const PanoramaCaptureOverlay({
    super.key,
    required this.controller,
    required this.onCancel,
    required this.onFinish,
  });

  final PanoramaCaptureController controller;
  final VoidCallback onCancel;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        final size = MediaQuery.sizeOf(context);
        final pad = MediaQuery.paddingOf(context);
        final isShort = size.height < 520;
        final top = pad.top + (isShort ? 16.0 : 72.0);
        return Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(child: CustomPaint(painter: _ArPainter(c))),
            ),
            Positioned(top: top, left: 0, right: 0, child: _status(context, c)),
            if (c.hasPose && c.phase != PanoramaPhase.stitching)
              isShort
                  ? Positioned(
                      top: pad.top + 16,
                      right: pad.right + 16,
                      child: IgnorePointer(
                        child: SizedBox(
                          width: 144,
                          height: 72,
                          child: CustomPaint(painter: _MiniMapPainter(c)),
                        ),
                      ),
                    )
                  : Positioned(
                      top: top + 92,
                      left: 0,
                      right: 0,
                      child: IgnorePointer(
                        child: Center(
                          child: SizedBox(
                            width: 216,
                            height: 108,
                            child: CustomPaint(painter: _MiniMapPainter(c)),
                          ),
                        ),
                      ),
                    ),
            if (c.phase == PanoramaPhase.stitching)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black54,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Colors.white),
                        SizedBox(height: 16),
                        Text(
                          context.l10n.panoramaStitching,
                          style: TextStyle(color: Colors.white, fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _status(BuildContext context, PanoramaCaptureController c) {
    if (c.phase == PanoramaPhase.stitching) return const SizedBox.shrink();
    final children = <Widget>[];
    if (c.phase == PanoramaPhase.ready) {
      children.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _chip(
              label: context.l10n.panoramaModeWide,
              icon: Icons.panorama_horizontal,
              selected: c.kind == PanoramaKind.wide,
              onTap: () => c.setKind(PanoramaKind.wide),
            ),
            const SizedBox(width: 8),
            _chip(
              label: '360°',
              icon: Icons.panorama_photosphere,
              selected: c.kind == PanoramaKind.sphere,
              onTap: () => c.setKind(PanoramaKind.sphere),
            ),
          ],
        ),
      );
    } else {
      final label = c.isSphere
          ? context.l10n.xOfYCounter(c.targetsDone, c.targets.length)
          : context.l10n.panoramaShotCount(c.shotCount);
      children.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _chip(label: label, icon: null, selected: true, onTap: null),
            if (c.shotCount >= 1) ...[
              const SizedBox(width: 8),
              _chip(
                label: context.l10n.done,
                icon: Icons.check,
                selected: false,
                onTap: onFinish,
              ),
            ],
            const SizedBox(width: 8),
            _chip(
              label: context.l10n.cancel,
              icon: Icons.close,
              selected: false,
              onTap: onCancel,
            ),
          ],
        ),
      );
    }
    children.add(const SizedBox(height: 8));
    children.add(
      Text(
        _hintText(context, c),
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          shadows: [Shadow(blurRadius: 4, color: Colors.black87)],
        ),
      ),
    );
    return Column(mainAxisSize: MainAxisSize.min, children: children);
  }

  String _hintText(BuildContext context, PanoramaCaptureController c) {
    final l10n = context.l10n;
    if (!c.hasPose) return l10n.panoramaWaitingForMotionSensor;
    if (c.phase == PanoramaPhase.ready) {
      return c.isSphere
          ? l10n.panoramaStartSphereHint
          : l10n.panoramaStartWideHint;
    }
    return switch (c.hint) {
      PanoramaHint.holdStill => l10n.panoramaHoldStillHint,
      PanoramaHint.keepLevel =>
        c.wideAxis == 'v'
            ? l10n.panoramaKeepVerticallyAlignedHint
            : l10n.panoramaKeepLevelHint,
      PanoramaHint.moveToDot => l10n.panoramaAimAtDotOrHoldStillHint,
      PanoramaHint.tooFast => l10n.panoramaSlowDownHint,
      PanoramaHint.sweep || PanoramaHint.none =>
        c.isSphere
            ? l10n.panoramaAimAtDotHint
            : l10n.panoramaFollowLineHint(l10n.done),
    };
  }

  Widget _chip({
    required String label,
    required IconData? icon,
    required bool selected,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? Colors.amber : Colors.black54,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 16,
                color: selected ? Colors.black : Colors.white,
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.black : Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Rect _imageRect(Size size, double aspect) {
  var w = size.width;
  var h = w / aspect;
  if (h > size.height) {
    h = size.height;
    w = h * aspect;
  }
  return Rect.fromLTWH((size.width - w) / 2, (size.height - h) / 2, w, h);
}

class _ArPainter extends CustomPainter {
  _ArPainter(this.c);
  final PanoramaCaptureController c;

  @override
  void paint(Canvas canvas, Size size) {
    if (!c.hasPose || c.phase == PanoramaPhase.stitching) return;
    final rect = _imageRect(size, c.tanX / c.tanY);
    final center = size.center(Offset.zero);

    Offset toScreen(double nx, double ny) => Offset(
      rect.left + (nx * 0.5 + 0.5) * rect.width,
      rect.top + (0.5 - ny * 0.5) * rect.height,
    );

    if (!c.isSphere && c.phase == PanoramaPhase.capturing) {
      // Draw level horizon (or vertical meridian) guide line.
      final curLook = lookDirection(c.viewPose);
      final curLon = longitudeOf(curLook);
      final curLat = latitudeOf(curLook);
      final guidePath = Path();
      var started = false;
      const samples = 24;
      for (var i = 0; i <= samples; i++) {
        final t = -0.65 + i * (1.30 / samples);
        final dir = c.wideAxis == 'v'
            ? directionOf(
                (curLat + t).clamp(-math.pi / 2 + 0.02, math.pi / 2 - 0.02),
                c.originLon,
              )
            : directionOf(c.originLat, wrapAngle(curLon + t));
        final pr = projectToScreen(c.viewPose, dir, c.tanX, c.tanY);
        if (pr == null || pr.x.abs() > 1.2 || pr.y.abs() > 1.2) {
          started = false;
          continue;
        }
        final pt = toScreen(pr.x, pr.y);
        if (!started) {
          guidePath.moveTo(pt.dx, pt.dy);
          started = true;
        } else {
          guidePath.lineTo(pt.dx, pt.dy);
        }
      }
      canvas.drawPath(
        guidePath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white54,
      );

      // Subtle dots at already-captured wide positions.
      for (final s in c.shots) {
        final pr = projectToScreen(
          c.viewPose,
          lookDirection(s.pose),
          c.tanX,
          c.tanY,
        );
        if (pr != null && pr.x.abs() <= 1.2 && pr.y.abs() <= 1.2) {
          canvas.drawCircle(
            toScreen(pr.x, pr.y),
            5,
            Paint()..color = const Color(0xCC4CAF50),
          );
        }
      }

      // Guide ring(s) for the next frame position.
      final guides = c.wideGuideDirections;
      for (final g in guides) {
        final pr = projectToScreen(c.viewPose, g, c.tanX, c.tanY);
        if (pr != null && pr.x.abs() <= 1.3 && pr.y.abs() <= 1.3) {
          final p = toScreen(pr.x, pr.y);
          canvas.drawCircle(p, 14, Paint()..color = const Color(0x55FFC107));
          canvas.drawCircle(
            p,
            14,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.5
              ..color = Colors.amber,
          );
        } else if (c.wideAxis != null) {
          _arrowToDir(canvas, center, rect, g);
        }
      }
    }

    if (c.isSphere && c.phase == PanoramaPhase.capturing) {
      final next = c.nextTarget;
      for (final t in c.targets) {
        final pr = projectToScreen(c.viewPose, t.direction, c.tanX, c.tanY);
        final isNext = identical(t, next);
        if (pr != null && pr.x.abs() <= 1.3 && pr.y.abs() <= 1.3) {
          final p = toScreen(pr.x, pr.y);
          if (t.done) {
            canvas.drawCircle(p, 7, Paint()..color = const Color(0xCC4CAF50));
          } else if (isNext) {
            canvas.drawCircle(p, 16, Paint()..color = const Color(0x66FFC107));
            canvas.drawCircle(
              p,
              16,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 3
                ..color = Colors.amber,
            );
          } else {
            canvas.drawCircle(
              p,
              7,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2
                ..color = Colors.white70,
            );
          }
        } else if (isNext) {
          _arrowToDir(canvas, center, rect, t.direction);
        }
      }
    }

    // Center reticle with progress ring.
    canvas.drawCircle(
      center,
      20,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white,
    );
    canvas.drawCircle(center, 2.5, Paint()..color = Colors.white);
    if (c.phase == PanoramaPhase.capturing && c.holdProgress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: 27),
        -math.pi / 2,
        2 * math.pi * c.holdProgress,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round
          ..color = Colors.amber,
      );
    }
  }

  void _arrowToDir(
    Canvas canvas,
    Offset center,
    Rect rect,
    ({double x, double y, double z}) d,
  ) {
    final p = c.viewPose;
    final vx = p[0] * d.x + p[3] * d.y + p[6] * d.z;
    final vy = p[1] * d.x + p[4] * d.y + p[7] * d.z;
    final len = math.sqrt(vx * vx + vy * vy);
    final ux = len < 1e-4 ? 0.0 : vx / len;
    final uy = len < 1e-4 ? -1.0 : -vy / len;
    final radius = math.min(rect.width, rect.height) * 0.38;
    final tip = center + Offset(ux, uy) * radius;
    final angle = math.atan2(uy, ux);
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(
        tip.dx - 22 * math.cos(angle - 0.45),
        tip.dy - 22 * math.sin(angle - 0.45),
      )
      ..lineTo(
        tip.dx - 22 * math.cos(angle + 0.45),
        tip.dy - 22 * math.sin(angle + 0.45),
      )
      ..close();
    canvas.drawPath(path, Paint()..color = Colors.amber);
  }

  @override
  bool shouldRepaint(covariant _ArPainter oldDelegate) => true;
}

class _MiniMapPainter extends CustomPainter {
  _MiniMapPainter(this.c);
  final PanoramaCaptureController c;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(bounds, const Radius.circular(10)),
      Paint()..color = const Color(0x99000000),
    );
    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(bounds, const Radius.circular(10)),
    );
    final grid = Paint()
      ..color = Colors.white12
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      grid,
    );
    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      grid,
    );

    final fill = Paint()..color = const Color(0x554CAF50);
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0xAA4CAF50);
    final origin = c.phase == PanoramaPhase.capturing
        ? c.originLon
        : longitudeOf(lookDirection(c.viewPose));
    for (final s in c.shots) {
      _drawFootprint(canvas, size, s.pose, origin, fill, edge);
    }
    for (final t in c.targets) {
      final x = (wrapAngle(t.lon - origin) / math.pi * 0.5 + 0.5) * size.width;
      final y = (0.5 - t.lat / math.pi) * size.height;
      canvas.drawCircle(
        Offset(x, y),
        2.5,
        Paint()..color = t.done ? const Color(0xFF4CAF50) : Colors.white54,
      );
    }
    _drawFootprint(
      canvas,
      size,
      c.viewPose,
      origin,
      Paint()..color = const Color(0x22FFFFFF),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white,
    );
    canvas.restore();
  }

  void _drawFootprint(
    Canvas canvas,
    Size size,
    List<double> pose,
    double origin,
    Paint fill,
    Paint edge,
  ) {
    final pts = <Offset>[];
    var minLat = double.infinity;
    var maxLat = -double.infinity;
    double? prevLon;
    const corners = <(double, double)>[(-1, -1), (1, -1), (1, 1), (-1, 1)];
    const n = 6;
    for (var e = 0; e < 4; e++) {
      final a = corners[e];
      final b = corners[(e + 1) % 4];
      for (var i = 0; i < n; i++) {
        final t = i / n;
        final d = screenRay(
          pose,
          a.$1 + (b.$1 - a.$1) * t,
          a.$2 + (b.$2 - a.$2) * t,
          c.tanX,
          c.tanY,
        );
        var lon = wrapAngle(longitudeOf(d) - origin);
        if (prevLon != null) {
          while (lon - prevLon > math.pi) {
            lon -= 2 * math.pi;
          }
          while (lon - prevLon < -math.pi) {
            lon += 2 * math.pi;
          }
        }
        prevLon = lon;
        final lat = latitudeOf(d);
        minLat = math.min(minLat, lat);
        maxLat = math.max(maxLat, lat);
        pts.add(
          Offset(
            (lon / math.pi * 0.5 + 0.5) * size.width,
            (0.5 - lat / math.pi) * size.height,
          ),
        );
      }
    }
    final first = pts.first;
    final last = pts.last;
    if ((last.dx - first.dx).abs() > size.width * 0.5) {
      final top = maxLat > math.pi / 2 - 0.35;
      final rect = top
          ? Rect.fromLTRB(
              0,
              0,
              size.width,
              (0.5 - minLat / math.pi) * size.height,
            )
          : Rect.fromLTRB(
              0,
              (0.5 - maxLat / math.pi) * size.height,
              size.width,
              size.height,
            );
      canvas.drawRect(rect, fill);
      canvas.drawRect(rect, edge);
      return;
    }
    final path = Path()..addPolygon(pts, true);
    for (final dx in <double>[0, -size.width, size.width]) {
      final shifted = path.shift(Offset(dx, 0));
      canvas.drawPath(shifted, fill);
      canvas.drawPath(shifted, edge);
    }
  }

  @override
  bool shouldRepaint(covariant _MiniMapPainter oldDelegate) => true;
}
