import 'package:desktop_drop/desktop_drop.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/utils/platform_features.dart';

/// Lets files and folders be dragged in from the operating system's file
/// manager (Windows Explorer, Nautilus, Dolphin, ...) and dropped on [child].
///
/// This is separate from the in-app drag and drop between panes
/// (`browser_item_drag.dart`): that one moves vault entries, this one brings
/// things in from outside the app. The two do not interfere -- an OS drag is
/// delivered by the platform runner, not by Flutter's gesture system.
///
/// While something is dragged over [child] a tinted frame with [label] fades
/// in; with [blockedReason] set it shows that text in the error tone instead
/// (read-only vault, archive view, ...), so the person learns why before they
/// let go. [onDropped] receives the dropped host paths when the drop is
/// accepted; it is not called when [blockedReason] is set -- the caller is
/// expected to have its own explanation ready for that case, because the
/// frame disappears the moment the drop happens.
///
/// Outside desktop this returns [child] untouched. The platform never changes
/// while the app runs, so the tree under [child] is never re-parented; [enabled]
/// likewise only switches the listener off, it does not change the tree.
class ExternalFileDropZone extends StatefulWidget {
  final Widget child;

  /// Called with the dropped host paths (files and folders, as the OS gave
  /// them). Never called with an empty list.
  final void Function(List<String> paths) onDropped;

  /// Called instead of [onDropped] when a drop lands while [blockedReason] is
  /// set, so the owner can show its own message.
  final VoidCallback? onBlockedDrop;

  /// Overlay text while a drag is over [child].
  final String label;

  /// When non-null the overlay shows this in the error tone and a drop is
  /// reported through [onBlockedDrop] rather than [onDropped].
  final String? blockedReason;

  /// Switches the listener off (no overlay, no drop) without changing the
  /// widget tree.
  final bool enabled;

  /// Extra gate evaluated when a drag enters and when it is dropped. Hidden
  /// tabs stay mounted, so a pane that is not on screen answers `false` here
  /// and ignores the drag.
  final bool Function()? isActive;

  const ExternalFileDropZone({
    super.key,
    required this.child,
    required this.onDropped,
    required this.label,
    this.onBlockedDrop,
    this.blockedReason,
    this.enabled = true,
    this.isActive,
  });

  @override
  State<ExternalFileDropZone> createState() => _ExternalFileDropZoneState();
}

class _ExternalFileDropZoneState extends State<ExternalFileDropZone> {
  bool _hovering = false;

  /// The route this zone lives on. Read in [build] (where depending on it is
  /// allowed) and consulted when a drag arrives: a viewer, dialog or sheet on
  /// top of the pane must not take a drop meant for what it covers -- the
  /// native drop event knows nothing about Flutter's route stack.
  ModalRoute<Object?>? _route;

  bool get _active =>
      (_route?.isCurrent ?? true) && (widget.isActive?.call() ?? true);

  void _setHovering(bool value) {
    if (_hovering == value || !mounted) return;
    setState(() => _hovering = value);
  }

  void _handleDone(DropDoneDetails details) {
    _setHovering(false);
    if (!_active) return;
    final paths = <String>[
      for (final file in details.files)
        if (file.path.isNotEmpty) file.path,
    ];
    if (paths.isEmpty) return;
    if (widget.blockedReason != null) {
      widget.onBlockedDrop?.call();
      return;
    }
    widget.onDropped(paths);
  }

  @override
  Widget build(BuildContext context) {
    if (!PlatformFeatures.isDesktop) return widget.child;
    _route = ModalRoute.of(context);

    final cs = Theme.of(context).colorScheme;
    final blocked = widget.blockedReason != null;
    final accent = blocked ? cs.error : cs.primary;
    final cardColor = blocked ? cs.errorContainer : cs.primaryContainer;
    final onCard = blocked ? cs.onErrorContainer : cs.onPrimaryContainer;

    return DropTarget(
      enable: widget.enabled,
      onDragEntered: (_) {
        if (_active) _setHovering(true);
      },
      onDragExited: (_) => _setHovering(false),
      onDragDone: _handleDone,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          widget.child,
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _hovering ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 150),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.10),
                    border: Border.all(color: accent, width: 2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Material(
                      color: cardColor,
                      elevation: 3,
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              blocked
                                  ? Icons.block_rounded
                                  : Icons.file_download_outlined,
                              color: onCard,
                            ),
                            const SizedBox(width: 12),
                            Flexible(
                              child: Text(
                                widget.blockedReason ?? widget.label,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(color: onCard),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
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
