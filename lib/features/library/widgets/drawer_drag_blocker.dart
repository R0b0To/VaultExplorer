import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/widgets/full_screen_drag_drawer.dart';

/// Keeps the side drawer from opening while a finger that started on [child]
/// drags.
///
/// The drawer opens on a right swipe from anywhere in the content area and reads
/// raw pointer events, so a horizontally scrolling strip inside the content
/// (the music bar's pills) would also slide the drawer open. A pointer that goes
/// down here blocks the drawer until it lifts or is cancelled. Outside the
/// shell (a pushed screen) there is no drawer scope and this does nothing.
class DrawerDragBlocker extends StatefulWidget {
  final Widget child;

  const DrawerDragBlocker({super.key, required this.child});

  @override
  State<DrawerDragBlocker> createState() => _DrawerDragBlockerState();
}

class _DrawerDragBlockerState extends State<DrawerDragBlocker> {
  ValueChanged<bool>? _setBlocked;
  bool _blocked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _setBlocked = FullScreenDragDrawerScope.maybeOf(context)?.setDrawerDragBlocked;
  }

  @override
  void dispose() {
    if (_blocked) _setBlocked?.call(false);
    super.dispose();
  }

  void _block(bool value) {
    _blocked = value;
    _setBlocked?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _block(true),
      onPointerUp: (_) => _block(false),
      onPointerCancel: (_) => _block(false),
      child: widget.child,
    );
  }
}
