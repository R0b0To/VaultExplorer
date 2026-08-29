import 'package:material_ui/material_ui.dart';

/// Width thresholds that decide when a screen switches from the compact,
/// single-column layout (phone portrait, or a cramped window) to a layout
/// that makes deliberate use of extra horizontal space -- a side rail
/// instead of a bottom bar, two panes instead of one, etc.
///
/// Kept as one shared source of truth so every screen agrees on where the
/// line is, rather than each widget guessing its own pixel threshold.
abstract final class AppBreakpoints {
  /// Minimum width before a screen splits its content into two panes or
  /// columns. Below this, even a landscape window falls back to the
  /// compact single-column layout -- there just isn't room to do two
  /// columns justice (e.g. small/older phones, split-screen multitasking).
  static const wideContentMinWidth = 600.0;

  /// Soft cap on how wide the "secondary" pane (a side rail's content, or
  /// the left pane of a two-pane screen) is allowed to grow on very wide
  /// windows, so it reads as a fixed-width panel rather than stretching
  /// with the rest of the screen.
  static const secondaryPaneMaxWidth = 420.0;
}

/// Resolves the window's current size/orientation once per build so every
/// screen makes the same landscape/space decisions off shared numbers,
/// instead of re-deriving ad hoc `MediaQuery` thresholds in each widget.
@immutable
class ScreenInfo {
  final Size size;
  final Orientation orientation;

  const ScreenInfo({required this.size, required this.orientation});

  factory ScreenInfo.of(BuildContext context) {
    final mq = MediaQuery.of(context);
    return ScreenInfo(size: mq.size, orientation: mq.orientation);
  }

  double get width => size.width;
  double get height => size.height;

  /// True whenever the device/window is rotated to landscape. On its own
  /// this only means "wider than tall" -- it doesn't guarantee there's
  /// room for a second column; see [useWideLayout] for that.
  bool get isLandscape => orientation == Orientation.landscape;

  /// True once the window is both landscape *and* wide enough that
  /// splitting content into two panes/columns actually helps rather than
  /// just cramping both halves. Screens that want a two-column or
  /// side-by-side treatment should gate on this rather than [isLandscape]
  /// alone, so a narrow landscape window (small/older phone, split-screen)
  /// still falls back to a single stacked column.
  bool get useWideLayout =>
      isLandscape && width >= AppBreakpoints.wideContentMinWidth;

  /// Clamped width for a fixed-width secondary pane in a two-pane layout,
  /// so it reads as a panel of a sensible size rather than stretching to
  /// half the screen on very wide windows or getting squeezed too thin
  /// right at the [useWideLayout] threshold.
  double secondaryPaneWidth({double fraction = 0.4}) =>
      (width * fraction).clamp(280.0, AppBreakpoints.secondaryPaneMaxWidth);
}

extension ScreenInfoX on BuildContext {
  /// Shorthand for `ScreenInfo.of(context)`, mirroring the `context.colors`
  /// / `context.typography` getters in `AppThemeX`.
  ScreenInfo get screen => ScreenInfo.of(this);
}
