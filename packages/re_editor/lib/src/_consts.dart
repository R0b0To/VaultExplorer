part of re_editor;

final kIsMacOS = defaultTargetPlatform == TargetPlatform.macOS;
final kIsAndroid = defaultTargetPlatform == TargetPlatform.android;
final kIsIOS = defaultTargetPlatform == TargetPlatform.iOS;

/// Upper bound on how many lines the wrapped editor measures one by one when
/// the scroll position moves backwards. Beyond it the editor jumps with the
/// fixed-height estimate instead (see `_updateDisplayRenderParagraphs`).
const int _kMaxExactBackwardLines = 64;
