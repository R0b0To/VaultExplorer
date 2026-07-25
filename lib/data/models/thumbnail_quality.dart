import 'package:flutter/foundation.dart';

@immutable
class ThumbnailQuality {
  final int quality; // JPEG quality: 10..100
  final int size; // Target max edge in px: 100..500

  const ThumbnailQuality({
    this.quality = 80,
    this.size = 180,
  });

  static const defaultQuality = ThumbnailQuality(quality: 80, size: 180);

  int get jpegQuality => quality.clamp(10, 100);

  int scaledSize(int base) {
    return (base * (size / 180.0)).round().clamp(40, 1000);
  }

  String get label => '${size}px · $quality% quality';

  ThumbnailQuality copyWith({
    int? quality,
    int? size,
  }) {
    return ThumbnailQuality(
      quality: (quality ?? this.quality).clamp(10, 100),
      size: (size ?? this.size).clamp(80, 600),
    );
  }

  Map<String, dynamic> toJson() => {
        'quality': quality,
        'size': size,
      };

  static ThumbnailQuality fromJson(dynamic value) {
    if (value == null) return defaultQuality;
    if (value is Map<String, dynamic>) {
      return ThumbnailQuality(
        quality: (value['quality'] as num?)?.toInt() ?? 80,
        size: (value['size'] as num?)?.toInt() ?? 180,
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
          other.size == size;

  @override
  int get hashCode => Object.hash(quality, size);
}