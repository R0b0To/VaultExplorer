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

  /// Minimum window width at which the navigation menu is docked as a
  /// permanent sidebar instead of a modal drawer (Material's "expanded"
  /// window class). Tablets in landscape and desktop windows reach it;
  /// phones in portrait and tablets in portrait stay on the modal drawer.
  static const dockedSidebarMinWidth = 840.0;

  /// Minimum window height for the docked sidebar. A phone held in
  /// landscape can be wider than [dockedSidebarMinWidth], but its height
  /// is far too short to spend a third of the width on a permanent menu.
  static const dockedSidebarMinHeight = 480.0;

  /// Width of the docked navigation sidebar.
  static const dockedSidebarWidth = 288.0;

  /// Whether a window of [size] gets the docked navigation sidebar. Takes a
  /// plain [Size] so callers high in the tree can decide from
  /// `MediaQuery.sizeOf` and rebuild only when the window itself changes,
  /// not on every keyboard or inset change.
  static bool useDockedSidebarFor(Size size) =>
      size.width >= dockedSidebarMinWidth &&
      size.height >= dockedSidebarMinHeight;

  /// Widest a single-column page (a form, a settings detail pane, a list of
  /// cards) is allowed to grow before it is centered instead of stretched.
  static const pageMaxWidth = 1100.0;

  /// Narrowest a card in an adaptive card grid is allowed to be.
  static const cardGridMinTileWidth = 340.0;
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
    // The narrow lookups subscribe the caller to size and orientation changes
    // only, not to every MediaQuery change (keyboard, insets, text scale).
    return ScreenInfo(
      size: MediaQuery.sizeOf(context),
      orientation: MediaQuery.orientationOf(context),
    );
  }

  double get width => size.width;
  double get height => size.height;

  /// True whenever the device/window is rotated to landscape. On its own
  /// this only means "wider than tall" -- it doesn't guarantee there's
  /// room for a second column; see [useWideLayout] for that.
  bool get isLandscape => orientation == Orientation.landscape;

  /// True once the window is wide enough that splitting content into two
  /// panes/columns actually helps rather than just cramping both halves.
  /// Screens that want a two-column or side-by-side treatment should gate on
  /// this, so a narrow window (small/older phone, split-screen) still falls
  /// back to a single stacked column.
  ///
  /// This is decided by width alone: a tablet held in portrait, a foldable
  /// and a desktop window resized to a tall shape have just as much
  /// horizontal room as a landscape phone does.
  bool get useWideLayout => width >= AppBreakpoints.wideContentMinWidth;

  /// True when the window is landscape *or* wide enough that it should use
  /// the layouts and settings made for a landscape window (top toolbar,
  /// landscape grid columns). A tablet or a desktop window that happens to be
  /// taller than wide is still a big screen and must not fall back to the
  /// phone-portrait layout with a bottom toolbar.
  bool get useLandscapeLayout =>
      isLandscape || width >= AppBreakpoints.wideContentMinWidth;

  /// [Orientation.landscape] when [useLandscapeLayout], otherwise
  /// [Orientation.portrait]. For code that keys per-orientation settings (grid
  /// column counts, say) on the orientation but should treat a wide window
  /// like a landscape one.
  Orientation get layoutOrientation =>
      useLandscapeLayout ? Orientation.landscape : Orientation.portrait;

  /// The most columns the file manager's grid view may show. A wide window
  /// has room for far more tiles than a phone held sideways, so the pinch
  /// zoom range grows with it. The grid, the masonry view and the geometry
  /// code that mirrors them must all read this one value.
  int get maxGridColumns => useLandscapeLayout ? (width >= 900 ? 10 : 7) : 4;

  /// The most columns the file manager's masonry view may show; see
  /// [maxGridColumns].
  int get maxMasonryColumns => useLandscapeLayout ? (width >= 900 ? 9 : 6) : 3;

  /// True when the navigation menu is shown as a permanent sidebar: a
  /// tablet in landscape, an unfolded foldable or a desktop window.
  bool get useDockedSidebar => AppBreakpoints.useDockedSidebarFor(size);

  /// How many equally wide cards fit side by side in [availableWidth]
  /// without any of them getting narrower than [minTileWidth].
  static int cardColumnsFor(
    double availableWidth, {
    double minTileWidth = AppBreakpoints.cardGridMinTileWidth,
    int? maxColumns = 3,
  }) {
    if (availableWidth.isNaN || availableWidth <= 0) return 1;
    final fit = (availableWidth / minTileWidth).floor();
    if (fit < 1) return 1;
    if (maxColumns != null && fit > maxColumns) return maxColumns;
    return fit;
  }

  /// Clamped width for a fixed-width secondary pane in a two-pane layout,
  /// so it reads as a panel of a sensible size rather than stretching to
  /// half the screen on very wide windows or getting squeezed too thin
  /// right at the [useWideLayout] threshold.
  double secondaryPaneWidth({double fraction = 0.4}) =>
      (width * fraction).clamp(280.0, AppBreakpoints.secondaryPaneMaxWidth);
}

extension ScreenInfoX on BuildContext {
  /// Whether pop-ups opened from here (sheets, unlock and settings pages)
  /// should appear as centered dialogs instead of full-screen pages and
  /// bottom sheets: true beside a docked sidebar and in any window large
  /// enough to have one.
  ///
  /// Decided from the real window, not from the (narrower) content area a
  /// docked sidebar leaves, so a 1024 px tablet does not flip between the two
  /// presentations depending on where the pop-up was opened. Safe to call from
  /// an event handler: it does not subscribe the caller to rebuilds.
  bool get prefersDialogs =>
      getInheritedWidgetOfExactType<DockedSidebarScope>() != null ||
      AppBreakpoints.useDockedSidebarFor(MediaQuery.sizeOf(this));

  /// Shorthand for `ScreenInfo.of(context)`, mirroring the `context.colors`
  /// / `context.typography` getters in `AppThemeX`.
  ScreenInfo get screen => ScreenInfo.of(this);
}

/// Marks the part of the widget tree that sits beside a docked navigation
/// sidebar. Page-level chrome (the hamburger button, the back arrow that
/// returns to the dashboard) reads it to drop controls that only exist to
/// open a drawer that is no longer there.
///
/// Routes pushed on the root navigator are not descendants of the shell, so
/// they never see it and keep their normal chrome.
class DockedSidebarScope extends InheritedWidget {
  const DockedSidebarScope({super.key, required super.child});

  /// Whether [context] lives beside a docked sidebar.
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DockedSidebarScope>() != null;

  @override
  bool updateShouldNotify(DockedSidebarScope oldWidget) => false;
}
