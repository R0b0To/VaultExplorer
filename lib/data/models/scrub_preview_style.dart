import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

/// How the video seekbar previews the frame under the thumb while the user
/// is dragging it.
///
/// Chosen in Media player controls > Playback & display and stored in
/// `MediaViewerToolbarConfig`.
enum ScrubPreviewStyle {
  /// A small thumbnail with a timestamp floating above the seekbar thumb.
  /// The original behaviour, and the default.
  miniBox,

  /// The frame fills the video area for the duration of the drag, with a
  /// timestamp pill above the controls. The seekbar stays on top of it.
  fullscreen;

  String getLocalizedLabel(AppLocalizations l10n) => switch (this) {
        ScrubPreviewStyle.miniBox => l10n.scrubPreviewMiniBoxLabel,
        ScrubPreviewStyle.fullscreen => l10n.scrubPreviewFullscreenLabel,
      };

  String getLocalizedDescription(AppLocalizations l10n) => switch (this) {
        ScrubPreviewStyle.miniBox => l10n.scrubPreviewMiniBoxDesc,
        ScrubPreviewStyle.fullscreen => l10n.scrubPreviewFullscreenDesc,
      };

  IconData get icon => switch (this) {
        ScrubPreviewStyle.miniBox => Icons.picture_in_picture_alt_rounded,
        ScrubPreviewStyle.fullscreen => Icons.fullscreen_rounded,
      };

  String toJson() => name;

  /// Unknown or missing values (a settings file written before this option
  /// existed, or by a newer build) fall back to [miniBox], i.e. what every
  /// existing install was already doing.
  static ScrubPreviewStyle fromJson(String? value) => switch (value) {
        'fullscreen' => ScrubPreviewStyle.fullscreen,
        _ => ScrubPreviewStyle.miniBox,
      };
}
