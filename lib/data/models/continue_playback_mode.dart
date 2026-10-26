/// What the media viewer does with playback that is still running when the
/// viewer is closed (back button, swipe, "close").
///
/// [off] keeps the long-standing behaviour: closing the viewer stops and
/// releases the player. The other two hand the live player over to the
/// app-wide mini player, so audio keeps playing -- and video keeps playing in
/// a small floating window -- while the person moves around the app.
enum ContinuePlaybackMode {
  /// Closing the viewer stops playback.
  off,

  /// Audio keeps playing in a mini player bar; video still stops.
  audioOnly,

  /// Audio keeps playing in a mini player bar and video in a floating window.
  audioAndVideo;

  /// Whether playback of an item of the given kind survives closing the viewer.
  bool keepsPlaying({required bool isVideo}) => switch (this) {
    ContinuePlaybackMode.off => false,
    ContinuePlaybackMode.audioOnly => !isVideo,
    ContinuePlaybackMode.audioAndVideo => true,
  };

  static ContinuePlaybackMode fromJson(String? name) =>
      ContinuePlaybackMode.values.firstWhere(
        (mode) => mode.name == name,
        orElse: () => ContinuePlaybackMode.off,
      );
}
