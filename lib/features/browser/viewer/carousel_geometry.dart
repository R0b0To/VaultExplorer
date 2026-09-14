import 'dart:math' as math;

import 'package:flutter/widgets.dart' show EdgeInsets;

/// Layout math for the media viewer's continuous-scroll carousel: how tall
/// each item is (accounting for aspect ratio and rotation), and the
/// index<->scroll-offset conversions the "snap to nearest item" and
/// "programmatically scroll to index N" behaviors both depend on.
///
/// Extracted from `_MediaViewerScreenState`'s `_getItemHeight`,
/// `_getContinuousListPadding`, `_getOffsetForIndex`, and
/// `_getIndexForOffset` (media-viewer-screen decomposition, tech-debt
/// audit, Sept 2026). These were pure functions of the playlist, viewport
/// size, per-file rotation, and an aspect-ratio lookup already -- they only
/// lived on the State class because that lookup went through
/// [MediaAspectRatioCache] with `widget.container` baked in. Passing that
/// lookup (and the audio check) in as plain functions makes this
/// independently constructible and testable with known inputs/outputs --
/// no widget tree, no fake container -- for math that's easy to get subtly
/// wrong (off-by-one on the last item, wrong centering when an item is
/// shorter than the viewport) and had no unit coverage in its widget-bound
/// form.
///
/// Unlike the other clusters in that audit, this one needed no behavior
/// decision, just a home outside the widget: identical formulas, same
/// edge-case handling, only the two external lookups now passed in rather
/// than reached for.
class CarouselGeometry {
  final List<String> playlist;
  final Map<String, int> rotations;
  final bool Function(String fileName) isAudio;
  final double? Function(String fileName) aspectRatioFor;

  const CarouselGeometry({
    required this.playlist,
    required this.rotations,
    required this.isAudio,
    required this.aspectRatioFor,
  });

  double itemHeight(int index, double viewportWidth, double viewportHeight) {
    if (index < 0 || index >= playlist.length) {
      return viewportHeight;
    }
    final fileName = playlist[index];
    if (isAudio(fileName)) {
      return math.min(320.0, viewportHeight);
    }
    final ratio = aspectRatioFor(fileName);
    if (ratio != null && ratio > 0 && viewportWidth > 0) {
      final rotation = rotations[fileName] ?? 0;
      final effectiveRatio = (rotation % 2 != 0) ? 1.0 / ratio : ratio;
      final calculatedHeight = viewportWidth / effectiveRatio;
      return calculatedHeight.clamp(120.0, viewportHeight);
    }
    return (viewportWidth / (16 / 9)).clamp(120.0, viewportHeight);
  }

  EdgeInsets continuousListPadding(double viewportWidth, double viewportHeight) {
    if (playlist.isEmpty || viewportHeight <= 0) return EdgeInsets.zero;
    final h0 = itemHeight(0, viewportWidth, viewportHeight);
    final topPadding = math.max(0.0, (viewportHeight - h0) / 2.0);
    final hLast = itemHeight(playlist.length - 1, viewportWidth, viewportHeight);
    final bottomPadding = math.max(0.0, (viewportHeight - hLast) / 2.0);
    return EdgeInsets.only(top: topPadding, bottom: bottomPadding);
  }

  double offsetForIndex(int targetIndex, double viewportWidth, double viewportHeight) {
    if (playlist.isEmpty || viewportHeight <= 0) return 0.0;
    if (targetIndex <= 0) return 0.0;
    if (targetIndex >= playlist.length) targetIndex = playlist.length - 1;

    final padding = continuousListPadding(viewportWidth, viewportHeight);
    double sumPrevHeights = 0.0;
    for (int i = 0; i < targetIndex; i++) {
      sumPrevHeights += itemHeight(i, viewportWidth, viewportHeight);
    }
    final currentItemHeight = itemHeight(targetIndex, viewportWidth, viewportHeight);
    if (currentItemHeight >= viewportHeight) {
      return padding.top + sumPrevHeights;
    }
    return padding.top + sumPrevHeights - (viewportHeight - currentItemHeight) / 2.0;
  }

  int indexForOffset(double offset, double viewportWidth, double viewportHeight) {
    if (playlist.isEmpty) return 0;
    if (playlist.length == 1) return 0;

    final padding = continuousListPadding(viewportWidth, viewportHeight);
    double currentOffset = padding.top;
    int bestIdx = 0;
    double minDiff = double.infinity;

    for (int i = 0; i < playlist.length; i++) {
      final h = itemHeight(i, viewportWidth, viewportHeight);
      final ideal = (h >= viewportHeight) ? currentOffset : currentOffset - (viewportHeight - h) / 2.0;
      final diff = (offset - ideal).abs();
      if (diff < minDiff) {
        minDiff = diff;
        bestIdx = i;
      } else if (currentOffset > offset + viewportHeight) {
        break;
      }
      currentOffset += h;
    }
    return bestIdx;
  }
}
