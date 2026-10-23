import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

/// The small "fit to screen · 180%" chip shown over a zoomed view. Tapping it
/// puts the view back to its normal size, which is how the image editor and
/// the media player reset a zoom without a double-tap.
class ZoomIndicatorPill extends StatelessWidget {
  final double scale;
  final VoidCallback onReset;

  const ZoomIndicatorPill({
    super.key,
    required this.scale,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.65),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onReset,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.fit_screen_rounded,
                color: Colors.white,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                '${(scale * 100).round()}%',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  fontFeatures: [ui.FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
