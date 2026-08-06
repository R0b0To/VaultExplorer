import 'package:flutter/material.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

enum PlaylistScrollMode {
  horizontal,
  verticalPage,
  verticalContinuous;

  String get label {
    switch (this) {
      case PlaylistScrollMode.horizontal:
        return 'Horizontal';
      case PlaylistScrollMode.verticalPage:
        return 'Vertical Paged';
      case PlaylistScrollMode.verticalContinuous:
        return 'Vertical Continuous';
    }
  }

  String getLocalizedLabel(AppLocalizations l10n) => switch (this) {
        PlaylistScrollMode.horizontal => l10n.playlistScrollHorizontalLabel,
        PlaylistScrollMode.verticalPage => l10n.playlistScrollVerticalPageLabel,
        PlaylistScrollMode.verticalContinuous => l10n.playlistScrollVerticalContinuousLabel,
      };

  IconData get icon => switch (this) {
        PlaylistScrollMode.horizontal => Icons.swap_horiz_rounded,
        PlaylistScrollMode.verticalPage => Icons.swap_vert_rounded,
        PlaylistScrollMode.verticalContinuous => Icons.view_stream_rounded,
      };

  Axis get axis => switch (this) {
        PlaylistScrollMode.horizontal => Axis.horizontal,
        PlaylistScrollMode.verticalPage => Axis.vertical,
        PlaylistScrollMode.verticalContinuous => Axis.vertical,
      };

  bool get isContinuous => this == PlaylistScrollMode.verticalContinuous;

  String toJson() => name;

  static PlaylistScrollMode fromJson(String? value) {
    if (value == null) return PlaylistScrollMode.horizontal;
    switch (value) {
      case 'horizontal':
        return PlaylistScrollMode.horizontal;
      case 'vertical':
      case 'verticalPage':
        return PlaylistScrollMode.verticalPage;
      case 'verticalContinuous':
        return PlaylistScrollMode.verticalContinuous;
      default:
        return PlaylistScrollMode.horizontal;
    }
  }
}