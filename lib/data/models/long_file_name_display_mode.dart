import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

/// How a file/folder name that doesn't fit on one line is shortened.
///
/// Applies wherever a name is rendered on a single line across the file
/// manager -- list rows (`FileRowShell`) and grid/masonry captions
/// (`GridCardShell`) alike -- via `FileNameLabel`. Names are never allowed
/// to wrap onto a second line; this only controls *how* the overflow is
/// hidden.
enum LongFileNameDisplayMode {
  /// Hide the start of the name, keeping the end (and file extension)
  /// visible: "…report_final_v3.docx".
  ellipsizeStart,

  /// Hide the middle of the name, keeping both the start and the end (and
  /// file extension) visible: "quarterly_report…final_v3.docx".
  ellipsizeMiddle,

  /// Hide the end of the name, keeping the start visible (default):
  /// "quarterly_report_final_v…".
  ellipsizeEnd,

  /// Never hide anything -- instead, slowly scroll the full name back and
  /// forth horizontally so all of it eventually becomes visible.
  marquee;

  // ── Human-readable labels ─────────────────────────────────────────────────

  String get label {
    switch (this) {
      case LongFileNameDisplayMode.ellipsizeStart:
        return 'Ellipsize start';
      case LongFileNameDisplayMode.ellipsizeMiddle:
        return 'Ellipsize middle';
      case LongFileNameDisplayMode.ellipsizeEnd:
        return 'Ellipsize end';
      case LongFileNameDisplayMode.marquee:
        return 'Scroll (marquee)';
    }
  }

  String getLocalizedLabel(AppLocalizations l10n) {
    switch (this) {
      case LongFileNameDisplayMode.ellipsizeStart:
        return l10n.longFileNameEllipsizeStartLabel;
      case LongFileNameDisplayMode.ellipsizeMiddle:
        return l10n.longFileNameEllipsizeMiddleLabel;
      case LongFileNameDisplayMode.ellipsizeEnd:
        return l10n.longFileNameEllipsizeEndLabel;
      case LongFileNameDisplayMode.marquee:
        return l10n.longFileNameMarqueeLabel;
    }
  }

  String get description {
    switch (this) {
      case LongFileNameDisplayMode.ellipsizeStart:
        return 'Trims the beginning of long names, keeping the end and file extension visible.';
      case LongFileNameDisplayMode.ellipsizeMiddle:
        return 'Trims the middle of long names, keeping the start and the file extension visible.';
      case LongFileNameDisplayMode.ellipsizeEnd:
        return 'Trims the end of long names, keeping the start visible.';
      case LongFileNameDisplayMode.marquee:
        return 'Keeps the full name, slowly scrolling it back and forth so all of it stays readable.';
    }
  }

  String getLocalizedDescription(AppLocalizations l10n) {
    switch (this) {
      case LongFileNameDisplayMode.ellipsizeStart:
        return l10n.longFileNameEllipsizeStartDesc;
      case LongFileNameDisplayMode.ellipsizeMiddle:
        return l10n.longFileNameEllipsizeMiddleDesc;
      case LongFileNameDisplayMode.ellipsizeEnd:
        return l10n.longFileNameEllipsizeEndDesc;
      case LongFileNameDisplayMode.marquee:
        return l10n.longFileNameMarqueeDesc;
    }
  }

  // ── JSON serialisation ────────────────────────────────────────────────────

  String toJson() {
    switch (this) {
      case LongFileNameDisplayMode.ellipsizeStart:
        return 'ellipsizeStart';
      case LongFileNameDisplayMode.ellipsizeMiddle:
        return 'ellipsizeMiddle';
      case LongFileNameDisplayMode.ellipsizeEnd:
        return 'ellipsizeEnd';
      case LongFileNameDisplayMode.marquee:
        return 'marquee';
    }
  }

  static LongFileNameDisplayMode? fromJson(String? value) {
    switch (value) {
      case 'ellipsizeStart':
        return LongFileNameDisplayMode.ellipsizeStart;
      case 'ellipsizeMiddle':
        return LongFileNameDisplayMode.ellipsizeMiddle;
      case 'ellipsizeEnd':
        return LongFileNameDisplayMode.ellipsizeEnd;
      case 'marquee':
        return LongFileNameDisplayMode.marquee;
      default:
        return null; // Return null so we know it isn't configured
    }
  }
}
