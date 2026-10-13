/// Why native code declined to produce a preview for an image.
enum ImagePreviewUnavailableReason {
  /// The source is beyond what the app will decode at all (huge pixel
  /// count). Permanent for that file, so callers may remember it.
  tooLarge,

  /// There wasn't enough free memory to decode it right now. Transient:
  /// don't remember it and don't auto-retry, but a manual retry may work
  /// once memory has been freed.
  outOfMemory,
}

/// Thrown instead of returning `null` when an image preview failed for a
/// reason the UI can explain (and shouldn't blindly retry).
class ImagePreviewUnavailableException implements Exception {
  final ImagePreviewUnavailableReason reason;

  const ImagePreviewUnavailableException(this.reason);

  @override
  String toString() => 'ImagePreviewUnavailableException($reason)';
}
