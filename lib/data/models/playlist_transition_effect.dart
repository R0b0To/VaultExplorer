import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

/// Represents the transition animation style used when navigating through items in a playlist.
enum PlaylistTransitionEffect {
  /// Standard horizontal sliding (default PageView).
  slide,

  /// Smooth cross-fade opacity transition.
  fade,

  /// Scale down & zoom opacity transition.
  zoom,

  /// 3D card stack depth transition (outgoing recedes, incoming slides over).
  depth,

  /// 3D perspective cube rotation.
  cube,

  /// 3D card flip animation.
  flip;

  // ── Human-readable labels ─────────────────────────────────────────────────

  String get label {
    switch (this) {
      case PlaylistTransitionEffect.slide:
        return 'Slide (Default)';
      case PlaylistTransitionEffect.fade:
        return 'Fade';
      case PlaylistTransitionEffect.zoom:
        return 'Zoom & Scale';
      case PlaylistTransitionEffect.depth:
        return 'Depth Stack';
      case PlaylistTransitionEffect.cube:
        return '3D Cube';
      case PlaylistTransitionEffect.flip:
        return '3D Flip';
    }
  }

  String getLocalizedLabel(AppLocalizations l10n) => switch (this) {
        PlaylistTransitionEffect.slide => l10n.playlistTransitionSlideLabel,
        PlaylistTransitionEffect.fade => l10n.playlistTransitionFadeLabel,
        PlaylistTransitionEffect.zoom => l10n.playlistTransitionZoomLabel,
        PlaylistTransitionEffect.depth => l10n.playlistTransitionDepthLabel,
        PlaylistTransitionEffect.cube => l10n.playlistTransitionCubeLabel,
        PlaylistTransitionEffect.flip => l10n.playlistTransitionFlipLabel,
      };

  // ── Icons ─────────────────────────────────────────────────────────────────

  IconData get icon {
    switch (this) {
      case PlaylistTransitionEffect.slide:
        return Icons.swipe_rounded;
      case PlaylistTransitionEffect.fade:
        return Icons.blur_on_rounded;
      case PlaylistTransitionEffect.zoom:
        return Icons.zoom_in_rounded;
      case PlaylistTransitionEffect.depth:
        return Icons.layers_rounded;
      case PlaylistTransitionEffect.cube:
        return Icons.view_in_ar_rounded;
      case PlaylistTransitionEffect.flip:
        return Icons.flip_camera_android_rounded;
    }
  }

  // ── JSON serialisation ────────────────────────────────────────────────────

  String toJson() => name;

  static PlaylistTransitionEffect fromJson(String? value) {
    if (value == null) return PlaylistTransitionEffect.slide;
    return PlaylistTransitionEffect.values.firstWhere(
      (e) => e.name == value,
      orElse: () => PlaylistTransitionEffect.slide,
    );
  }
}