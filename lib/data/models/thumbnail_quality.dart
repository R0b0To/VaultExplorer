import 'package:flutter/foundation.dart';

@immutable
class ThumbnailQuality {
  final int quality; // JPEG quality: 10..100
  final int size; // Target max edge in px: 100..[maxManualSize]

  /// When true, grid and masonry views ignore [size] and request each
  /// thumbnail at the on-screen pixel size of its cell (see
  /// [resolveForCell]), like Fossify Gallery does. [size] is then only the
  /// fallback for surfaces that don't resolve (list tiles, viewer, ...).
  final bool auto;

  const ThumbnailQuality({
    this.quality = 80,
    this.size = 180,
    this.auto = false,
  });

  /// Largest size the manual picker offers (and that [copyWith] / a manual
  /// [scaledSize] allow).
  static const int maxManualSize = 1000;

  /// Largest edge an auto-resolved thumbnail may ask for. 1 column on a
  /// 1440px-wide phone needs ~1400px; the native decoder additionally
  /// bounds its decode area, so this is not a memory guarantee.
  static const int maxAutoSize = 1536;
  static const int _autoMinSize = 128;
  static const int _autoBucket = 64;

  /// Thumbnails are fit-within (the *long* edge equals the requested size)
  /// while tiles are filled/cropped by the *short* edge. 4:3 is the usual
  /// photo shape, so a 4:3 source fills the cell at 1:1 device pixels.
  static const double coverOversample = 4 / 3;

  static const defaultQuality = ThumbnailQuality(quality: 80, size: 180);

  int get jpegQuality => quality.clamp(10, 100);

  int scaledSize(int base) {
    final ceiling = auto ? maxAutoSize : maxManualSize;
    return (base * (size / 180.0)).round().clamp(40, ceiling);
  }

  /// For an [auto] quality, returns a copy whose [size] is the pixel size a
  /// cell of [logicalWidth] (logical px) needs on a screen with
  /// [devicePixelRatio], rounded up to a multiple of 64 so cache keys don't
  /// change on every pixel of layout change. A non-auto quality is returned
  /// unchanged. The result stays [auto] so the memory cache can tell it
  /// must not be satisfied by a smaller resident thumbnail.
  ThumbnailQuality resolveForCell({
    required double logicalWidth,
    required double devicePixelRatio,
    double oversample = coverOversample,
  }) {
    if (!auto) return this;
    if (!logicalWidth.isFinite ||
        logicalWidth <= 0 ||
        !devicePixelRatio.isFinite ||
        devicePixelRatio <= 0) {
      return this;
    }
    final wanted = (logicalWidth * devicePixelRatio * oversample).ceil();
    final bucketed = ((wanted + _autoBucket - 1) ~/ _autoBucket) * _autoBucket;
    return ThumbnailQuality(
      quality: quality,
      size: bucketed.clamp(_autoMinSize, maxAutoSize),
      auto: true,
    );
  }

  String get label =>
      auto ? 'auto size · $quality% quality' : '${size}px · $quality% quality';

  ThumbnailQuality copyWith({
    int? quality,
    int? size,
    bool? auto,
  }) {
    return ThumbnailQuality(
      quality: (quality ?? this.quality).clamp(10, 100),
      size: (size ?? this.size).clamp(80, maxManualSize),
      auto: auto ?? this.auto,
    );
  }

  Map<String, dynamic> toJson() => {
        'quality': quality,
        'size': size,
        if (auto) 'auto': true,
      };

  static ThumbnailQuality fromJson(dynamic value) {
    if (value == null) return defaultQuality;
    if (value is Map<String, dynamic>) {
      return ThumbnailQuality(
        quality: (value['quality'] as num?)?.toInt() ?? 80,
        size: (value['size'] as num?)?.toInt() ?? 180,
        auto: value['auto'] == true,
      );
    }
    if (value is String) {
      switch (value) {
        case 'low':
          return const ThumbnailQuality(quality: 40, size: 140);
        case 'medium':
          return const ThumbnailQuality(quality: 80, size: 180);
        case 'high':
          return const ThumbnailQuality(quality: 90, size: 280);
        case 'veryHigh':
          return const ThumbnailQuality(quality: 98, size: 360);
        default:
          return defaultQuality;
      }
    }
    return defaultQuality;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ThumbnailQuality &&
          other.quality == quality &&
          other.size == size &&
          other.auto == auto;

  @override
  int get hashCode => Object.hash(quality, size, auto);
}