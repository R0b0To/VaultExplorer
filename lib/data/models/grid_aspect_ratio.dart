import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

enum GridAspectRatio {
  square,
  landscape,
  portrait;

  double get ratio => switch (this) {
        GridAspectRatio.square => 1.0,
        GridAspectRatio.landscape => 16.0 / 9.0,
        GridAspectRatio.portrait => 9.0 / 16.0,
      };

  IconData get icon => switch (this) {
        GridAspectRatio.square => Icons.crop_square_rounded,
        GridAspectRatio.landscape => Icons.crop_16_9_rounded,
        GridAspectRatio.portrait => Icons.crop_portrait_rounded,
      };

  String get label => switch (this) {
        GridAspectRatio.square => '1:1 (Square)',
        GridAspectRatio.landscape => '16:9 (Landscape)',
        GridAspectRatio.portrait => '9:16 (Portrait)',
      };

  String getLocalizedLabel(AppLocalizations l10n) => switch (this) {
        GridAspectRatio.square => l10n.gridAspectSquareLabel,
        GridAspectRatio.landscape => l10n.gridAspectLandscapeLabel,
        GridAspectRatio.portrait => l10n.gridAspectPortraitLabel,
      };

  String toJson() => name;

  static GridAspectRatio fromJson(String? value) => switch (value) {
        'square' => GridAspectRatio.square,
        'landscape' => GridAspectRatio.landscape,
        'portrait' => GridAspectRatio.portrait,
        _ => GridAspectRatio.square,
      };
}