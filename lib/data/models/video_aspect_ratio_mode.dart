import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

/// How a video's decoded frame is mapped into the player's viewport.
///
/// [bestFit] and [fill] size the viewport itself to the full available
/// space (letterboxed to the source ratio, or stretched to fill exactly);
/// [ratio16x9] and [ratio4x3] instead force the viewport to a fixed shape
/// and crop the source to cover it, matching the "16:9 / 4:3" cropping
/// options common on players like MX Player/VLC. [centre] shows the
/// source at its native pixel size with no scaling at all.
enum VideoAspectRatioMode {
  bestFit,
  fill,
  ratio16x9,
  ratio4x3,
  centre;

  IconData get icon => switch (this) {
        VideoAspectRatioMode.bestFit => Icons.fit_screen_rounded,
        VideoAspectRatioMode.fill => Icons.aspect_ratio_rounded,
        VideoAspectRatioMode.ratio16x9 => Icons.crop_16_9_rounded,
        VideoAspectRatioMode.ratio4x3 => Icons.crop_5_4_rounded,
        VideoAspectRatioMode.centre => Icons.crop_square_rounded,
      };

  String getLocalizedLabel(AppLocalizations l10n) => switch (this) {
        VideoAspectRatioMode.bestFit => l10n.aspectRatioBestFit,
        VideoAspectRatioMode.fill => l10n.aspectRatioFill,
        VideoAspectRatioMode.ratio16x9 => l10n.aspectRatio16x9,
        VideoAspectRatioMode.ratio4x3 => l10n.aspectRatio4x3,
        VideoAspectRatioMode.centre => l10n.aspectRatioCentre,
      };

  String toJson() => name;

  static VideoAspectRatioMode fromJson(String? value) => switch (value) {
        'bestFit' => VideoAspectRatioMode.bestFit,
        'fill' => VideoAspectRatioMode.fill,
        'ratio16x9' => VideoAspectRatioMode.ratio16x9,
        'ratio4x3' => VideoAspectRatioMode.ratio4x3,
        'centre' => VideoAspectRatioMode.centre,
        _ => VideoAspectRatioMode.bestFit,
      };
}