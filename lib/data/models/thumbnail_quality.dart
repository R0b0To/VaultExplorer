enum ThumbnailQuality {
  low,
  medium,
  high,
  veryHigh;

  String get label {
    switch (this) {
      case ThumbnailQuality.low:
        return 'Low (faster, smaller)';
      case ThumbnailQuality.medium:
        return 'Medium (balanced)';
      case ThumbnailQuality.high:
        return 'High (slower, larger)';
      case ThumbnailQuality.veryHigh:
        return 'Very High (sharpest, largest)';
    }
  }

  int get jpegQuality {
    switch (this) {
      case ThumbnailQuality.low:
        return 40;
      case ThumbnailQuality.medium:
        return 80;
      case ThumbnailQuality.high:
        return 90;
      case ThumbnailQuality.veryHigh:
        return 98;
    }
  }

  int scaledSize(int base) {
    final pct = switch (this) {
      ThumbnailQuality.low => 75,
      ThumbnailQuality.medium => 100,
      ThumbnailQuality.high => 160,
      ThumbnailQuality.veryHigh => 200,
    };
    return (base * pct / 100).round();
  }

  String toJson() {
    return name;
  }

  static ThumbnailQuality? fromJson(String? value) {
    switch (value) {
      case 'low':
        return ThumbnailQuality.low;
      case 'medium':
        return ThumbnailQuality.medium;
      case 'high':
        return ThumbnailQuality.high;
      case 'veryHigh':
        return ThumbnailQuality.veryHigh;
      default:
        return null;
    }
  }
}
