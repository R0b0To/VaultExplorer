import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/utils/platform_features.dart';

/// Opens a context menu on a right-click (secondary button press).
///
/// The press does not compete with the child's own taps, so a tile or card
/// keeps its normal click behaviour. Pair it with [touchOnlyLongPress] on the
/// child so that, on desktop, the menu comes from the right button alone and
/// a held click no longer opens it.
class ContextMenuRegion extends StatelessWidget {
  const ContextMenuRegion({
    super.key,
    required this.onOpen,
    required this.child,
  });

  /// Called with the global position of the click. `null` leaves the child as
  /// it is.
  final void Function(Offset globalPosition)? onOpen;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final open = onOpen;
    if (open == null) return child;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onSecondaryTapDown: (details) => open(details.globalPosition),
      child: child,
    );
  }
}

/// A long-press handler for touch platforms only.
///
/// On desktop the same actions live behind a right-click
/// ([ContextMenuRegion]), so the long-press is dropped there.
VoidCallback? touchOnlyLongPress(VoidCallback? onLongPress) =>
    PlatformFeatures.isDesktop ? null : onLongPress;
