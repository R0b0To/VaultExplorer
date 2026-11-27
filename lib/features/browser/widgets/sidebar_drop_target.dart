import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/widgets/browser_item_drag.dart';
import 'package:vaultexplorer/features/browser/widgets/browser_item_drop_target.dart';

/// Lets a sidebar entry (a storage, a vault, a bookmarked folder) take files
/// and folders dragged out of a file-manager pane.
///
/// The drop goes through the same path as dropping on a folder tile
/// ([handleBrowserItemDrop]): Copy / Move / Cancel is asked at the drop point
/// (Move is left out where it would do nothing), then the pane the drag came
/// from runs the transfer -- across vaults and storages too, with its usual
/// conflict sheet and progress.
///
/// [container] is where the items land and [path] the folder inside it ('' is
/// the root). A null [container] -- a locked vault, a bookmarked file -- makes
/// the entry refuse every drag. The tree stays the same either way, so an entry
/// that flips between accepting and refusing (a vault being unlocked) never
/// re-parents [child]. A read-only container, or a folder dropped into itself,
/// is refused by [BrowserItemDragData.canDropInto].
///
/// While a drag that would be accepted is over the entry, a frame in the
/// primary colour fades in around it, as on folder tiles in the file views.
class SidebarDropTarget extends StatelessWidget {
  final Widget child;
  final MountedContainer? container;
  final String path;

  /// Corner radius of the hover frame; match the entry's own shape.
  final BorderRadius borderRadius;

  const SidebarDropTarget({
    super.key,
    required this.child,
    required this.container,
    this.path = '',
    this.borderRadius = const BorderRadius.all(Radius.circular(10)),
  });

  @override
  Widget build(BuildContext context) {
    final target = container;
    final primary = Theme.of(context).colorScheme.primary;
    return BrowserItemDropTarget(
      onWillAcceptWithDetails: (details) =>
          target != null && details.data.canDropInto(target, path),
      onAcceptWithDetails: (details) {
        if (target == null) return;
        unawaited(handleBrowserItemDrop(context, details, target, path));
      },
      builder: (context, candidates, rejected) => Stack(
        fit: StackFit.passthrough,
        children: [
          child,
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: candidates.isNotEmpty ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 120),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.12),
                    border: Border.all(color: primary, width: 2),
                    borderRadius: borderRadius,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
