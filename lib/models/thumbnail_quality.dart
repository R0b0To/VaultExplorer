enum ThumbnailQuality {
  low,
  medium,
  high;

  String get label {
    switch (this) {
      case ThumbnailQuality.low:
        return 'Low (faster, smaller)';
      case ThumbnailQuality.medium:
        return 'Medium (balanced)';
      case ThumbnailQuality.high:
        return 'High (slower, larger)';
    }
  }

  int get jpegQuality {
    switch (this) {
      case ThumbnailQuality.low:
        return 40;
      case ThumbnailQuality.medium:
        return 70;
      case ThumbnailQuality.high:
        return 90;
    }
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
      default:
        return null;
    }
  }
}
