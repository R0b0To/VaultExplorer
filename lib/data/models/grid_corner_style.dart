import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

/// Corner shape of the cards in the file manager's grid and masonry views.
enum GridCornerStyle {
  rounded,
  square;

  /// Corner radius (logical px) of a grid/masonry card. [rounded] is the
  /// long-standing default look.
  double get radius => switch (this) {
        GridCornerStyle.rounded => 12.0,
        GridCornerStyle.square => 0.0,
      };

  String getLocalizedLabel(AppLocalizations l10n) => switch (this) {
        GridCornerStyle.rounded => l10n.gridCornerRoundedLabel,
        GridCornerStyle.square => l10n.gridCornerSquareLabel,
      };

  String toJson() => name;

  static GridCornerStyle fromJson(String? value) => switch (value) {
        'square' => GridCornerStyle.square,
        _ => GridCornerStyle.rounded,
      };
}
