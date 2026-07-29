class MediaViewerConstants {
  static const Duration uiHideDelay = Duration(seconds: 3);
  static const Duration animationDuration = Duration(milliseconds: 250);
  static const Duration pageTransitionDuration = Duration(milliseconds: 300);
  static const Duration doubleTapIndicatorDelay = Duration(milliseconds: 550);

  static const double maxImageZoom = 4.0;

  /// Full-resolution decode headroom used by [EncryptedImageWidget] to
  /// bound `Image.memory`'s decode target (Finding F-10). Deliberately
  /// smaller than [maxImageZoom]: this caps how many *pixels* Skia decodes
  /// relative to the viewport, not the interactive zoom ceiling itself — a
  /// 48MP source at 4x the viewport's physical size would still be tens of
  /// MB of raw bitmap. 3x gives comfortable pinch-zoom headroom before the
  /// image visibly softens, without decoding at "whatever the source file
  /// happens to be."
  static const double fullResDecodeZoomHeadroom = 3.0;
  static const double maxVideoZoom = 6.0;

  static const int maxPrefetchCacheSize = 5;
  static const int maxDirectorySearchDepth = 20;
  // Caps how many subdirectories _scanDirectoryRecursively will walk
  // concurrently at each level, so a huge "All (incl. subfolders)" vault
  // doesn't burst hundreds of simultaneous native channel calls at once.
  static const int maxDirectoryScanConcurrency = 8;
  static const int thumbnailTargetSize = 360;
  static const int carouselThumbnailTargetSize = 160;

  static const List<double> playbackSpeeds = [0.5, 1.0, 1.25, 1.5, 2.0];

  static const List<String> imageExtensions = [
    'jpg',
    'jpeg',
    'png',
    'gif',
    'webp',
  ];
static const List<String> videoExtensions = [
  'mp4', 'm4v', 'webm', 'mov', 'avi', 'mkv', 'mpeg', 'mpg',
  'flv', 'ts', 'wmv', '3gp', 'vob', 'ogv', 'divx', 'f4v', 'm2ts',
];

static const List<String> audioExtensions = [
  'mp3', 'm4a', 'wav', 'flac', 'ogg', 'aac',
  'opus', 'wma', 'ac3', 'eac3', 'm4b', 'ape', 'aiff', 'dts',
];

  static bool isImage(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    return imageExtensions.contains(ext);
  }

  static bool isVideo(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    return videoExtensions.contains(ext);
  }

  static bool isAudio(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    return audioExtensions.contains(ext);
  }

  static bool isSupported(String fileName) {
    return isImage(fileName) || isVideo(fileName) || isAudio(fileName);
  }
}