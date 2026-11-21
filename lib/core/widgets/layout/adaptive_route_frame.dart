import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Presents a full-screen page as a centered panel when the window is large.
///
/// A single-purpose page (unlock a vault, change a password) stretched across
/// a 1280 px tablet or a desktop window is mostly empty space with a form lost
/// in the middle. On a large window this frames the page as a rounded panel of
/// at most [maxWidth] x [maxHeight] centered on a quiet backdrop; on anything
/// smaller it returns [child] untouched, so phones and small tablets keep the
/// familiar full-screen page.
///
/// The page inside is told it has the panel's size (not the window's), so its
/// own width-based layout decisions (single column vs. two columns) match what
/// it actually gets.
class AdaptiveRouteFrame extends StatelessWidget {
  const AdaptiveRouteFrame({
    super.key,
    required this.child,
    this.maxWidth = 880,
    this.maxHeight = 760,
    this.minWindowWidth = 960,
    this.minWindowHeight = 640,
    this.showBackdrop = true,
    this.closeOnEscape = false,
  });

  final Widget child;
  final double maxWidth;
  final double maxHeight;

  /// Windows narrower or shorter than this keep the full-screen page.
  final double minWindowWidth;
  final double minWindowHeight;

  /// Paints a quiet opaque backdrop behind the panel. Turn it off when the
  /// frame sits in a dialog route whose own barrier already dims the page
  /// underneath.
  final bool showBackdrop;

  /// Closes the route (as the back button would, so a page that guards
  /// against leaving can still veto it) when Escape is pressed. Dialog routes
  /// that cannot be dismissed by tapping the barrier do not get Escape for
  /// free.
  final bool closeOnEscape;

  static const double _margin = 24;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    if (mq.size.width < minWindowWidth || mq.size.height < minWindowHeight) {
      return child;
    }

    final cs = Theme.of(context).colorScheme;
    final availableWidth = mq.size.width - _margin * 2;
    final availableHeight = mq.size.height - _margin * 2;
    final width = availableWidth < maxWidth ? availableWidth : maxWidth;
    final height = availableHeight < maxHeight ? availableHeight : maxHeight;

    Widget panel = Center(
      child: Material(
        elevation: 3,
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(28),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: width,
          height: height,
          child: MediaQuery(
            data: mq.copyWith(
              size: Size(width, height),
              padding: EdgeInsets.zero,
              viewPadding: EdgeInsets.zero,
            ),
            child: child,
          ),
        ),
      ),
    );
    if (showBackdrop) {
      panel = ColoredBox(color: cs.surfaceContainerLowest, child: panel);
    }
    if (closeOnEscape) {
      panel = CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              Navigator.of(context).maybePop(),
        },
        child: panel,
      );
    }
    return panel;
  }
}
