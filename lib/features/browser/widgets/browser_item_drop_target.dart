import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ve_desktop_transfer/ve_desktop_transfer.dart';
import 'package:vaultexplorer/features/browser/controllers/browser_drag_session.dart';
import 'package:vaultexplorer/features/browser/models/tab_id.dart';
import 'package:vaultexplorer/features/browser/widgets/browser_item_drag.dart';

/// A place dragged file-manager items can be dropped on: a folder tile, a
/// folder view, a storage location in the sidebar, a tab.
///
/// It is a `DragTarget<BrowserItemDragData>` and takes the same callbacks and
/// builder. What it adds is that it can also take the drag **back** after the
/// drag has left the window: dragging items to the edge of the window hands the
/// drag to the operating system (so they can be dropped in other programs), and
/// that drag cannot be driven by Flutter's own drag and drop. If it comes back
/// over the window while the button is still held, [OwnDragResume] finds the
/// target under the pointer and calls the same callbacks, so the drop is the
/// ordinary in-app one (Copy / Move menu, tab switching on hover, highlights)
/// and nothing has to be written to disk for it.
class BrowserItemDropTarget extends StatefulWidget {
  const BrowserItemDropTarget({
    super.key,
    required this.builder,
    this.onWillAcceptWithDetails,
    this.onAcceptWithDetails,
    this.onMove,
    this.onLeave,
  });

  final Widget Function(
    BuildContext context,
    List<BrowserItemDragData?> candidateData,
    List<dynamic> rejectedData,
  )
  builder;
  final bool Function(DragTargetDetails<BrowserItemDragData> details)?
  onWillAcceptWithDetails;
  final void Function(DragTargetDetails<BrowserItemDragData> details)?
  onAcceptWithDetails;
  final void Function(DragTargetDetails<BrowserItemDragData> details)? onMove;
  final void Function(BrowserItemDragData? data)? onLeave;

  @override
  State<BrowserItemDropTarget> createState() => _BrowserItemDropTargetState();
}

class _BrowserItemDropTargetState extends State<BrowserItemDropTarget>
    implements OwnDragDropTarget {
  /// The resumed drag that is over this target and was accepted, if any.
  BrowserItemDragData? _ownDrag;
  int? _viewId;
  RenderObject? _indexedRenderObject;

  @override
  void initState() {
    super.initState();
    OwnDragResume.instance.register(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextViewId = View.maybeOf(context)?.viewId;
    if (_viewId != nextViewId) {
      _viewId = nextViewId;
      OwnDragResume.instance.refreshTargets();
    }
  }

  @override
  void didUpdateWidget(covariant BrowserItemDropTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _refreshTargetIndexAfterFrame();
  }

  void _refreshTargetIndexAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final renderObject = context.findRenderObject();
      if (identical(_indexedRenderObject, renderObject)) return;
      _indexedRenderObject = renderObject;
      OwnDragResume.instance.refreshTargets();
    });
  }

  @override
  void dispose() {
    OwnDragResume.instance.unregister(this);
    super.dispose();
  }

  @override
  RenderObject? get dropRenderObject => mounted ? context.findRenderObject() : null;

  @override
  int? get dropViewId => _viewId;

  @override
  bool ownCanAccept(DragTargetDetails<BrowserItemDragData> details) =>
      widget.onWillAcceptWithDetails?.call(details) ?? true;

  @override
  void ownDragEnter(DragTargetDetails<BrowserItemDragData> details) {
    if (mounted) setState(() => _ownDrag = details.data);
  }

  @override
  void ownDragMove(DragTargetDetails<BrowserItemDragData> details) =>
      widget.onMove?.call(details);

  @override
  void ownDragLeave() {
    final data = _ownDrag;
    if (mounted) setState(() => _ownDrag = null);
    widget.onLeave?.call(data);
  }

  @override
  void ownDragDrop(DragTargetDetails<BrowserItemDragData> details) {
    if (mounted) setState(() => _ownDrag = null);
    widget.onAcceptWithDetails?.call(details);
  }

  @override
  Widget build(BuildContext context) {
    // Check after layout so ordinary tile rebuilds do not discard the index
    // when the hit-test render object stayed the same.
    _refreshTargetIndexAfterFrame();
    return DragTarget<BrowserItemDragData>(
      onWillAcceptWithDetails: widget.onWillAcceptWithDetails,
      onAcceptWithDetails: widget.onAcceptWithDetails,
      onMove: widget.onMove,
      onLeave: widget.onLeave,
      builder: (context, candidates, rejected) => widget.builder(
        context,
        _ownDrag == null ? candidates : <BrowserItemDragData?>[_ownDrag],
        rejected,
      ),
    );
  }
}

/// What [OwnDragResume] needs from a target. Implemented by
/// [BrowserItemDropTarget].
abstract interface class OwnDragDropTarget {
  /// The render object that a hit test on the target reports (the one of its
  /// `DragTarget`), and the view it is in.
  RenderObject? get dropRenderObject;
  int? get dropViewId;

  /// Whether the target takes the drag, as `onWillAcceptWithDetails` says.
  bool ownCanAccept(DragTargetDetails<BrowserItemDragData> details);

  void ownDragEnter(DragTargetDetails<BrowserItemDragData> details);
  void ownDragMove(DragTargetDetails<BrowserItemDragData> details);
  void ownDragLeave();
  void ownDragDrop(DragTargetDetails<BrowserItemDragData> details);
}

/// Carries on an in-app drag that was handed to the operating system when it
/// reached the edge of the window, if it comes back over the window with the
/// button still held.
///
/// The operating system's drag is modal and replaces Flutter's: while it runs,
/// the app gets no pointer events and the in-app drop targets see nothing. The
/// Windows runner recognises this app's own drag when it is over one of the
/// app's windows and reports where it is instead of treating it as files
/// dropped from another program (which would decrypt them to a temporary
/// folder and import them back). This turns those reports into what an
/// in-app drag does: it finds the [BrowserItemDropTarget] under the pointer,
/// highlights it, and on release hands the drop to it, so it ends in the
/// usual Copy / Move menu.
///
/// The drag session is restarted for as long as the drag is over the window, so
/// the other panes behave as drop targets only, as in any in-app drag.
class OwnDragResume {
  OwnDragResume._();

  static final OwnDragResume instance = OwnDragResume._();

  final Set<OwnDragDropTarget> _targets = <OwnDragDropTarget>{};
  final Map<int, Map<RenderObject, OwnDragDropTarget>> _targetsByView =
      <int, Map<RenderObject, OwnDragDropTarget>>{};

  _HandedOffDrag? _active;
  OwnDragDropTarget? _hover;
  bool _sessionBegun = false;

  void register(OwnDragDropTarget target) {
    if (_targets.add(target)) refreshTargets();
  }

  /// Invalidates the render-object index after targets attach, detach or
  /// rebuild. The next pointer update rebuilds it once for that view.
  void refreshTargets() => _targetsByView.clear();

  void unregister(OwnDragDropTarget target) {
    _targets.remove(target);
    refreshTargets();
    if (identical(_hover, target)) _hover = null;
  }

  /// Called just before [data] is handed to the operating system. It must be
  /// matched by [end] once the system's drag is over.
  void begin({
    required BrowserItemDragData data,
    required ProviderContainer container,
    required TabId sourceTab,
    required Offset startPosition,
  }) {
    end();
    _active = _HandedOffDrag(data, container, sourceTab, startPosition);
    VeDesktopTransfer.instance.addOwnDragListener(_onEvent);
  }

  /// The system's drag is over, however it ended.
  void end() {
    VeDesktopTransfer.instance.removeOwnDragListener(_onEvent);
    _leaveHover();
    _endSession();
    _active = null;
  }

  void _onEvent(DesktopDropEvent event) {
    final active = _active;
    if (active == null) return;
    switch (event.kind) {
      case DesktopDropEventKind.entered:
      case DesktopDropEventKind.updated:
        _beginSession(active);
        _update(active, event);
      case DesktopDropEventKind.exited:
        _leaveHover();
        _endSession();
      case DesktopDropEventKind.dropped:
        _update(active, event);
        final target = _hover;
        if (target != null) {
          _hover = null;
          target.ownDragDrop(_detailsFor(active, event));
        }
        _endSession();
    }
  }

  Offset _logical(DesktopDropEvent event) {
    final view = WidgetsBinding.instance.platformDispatcher.view(
      id: event.viewId,
    );
    final dpr = (view?.devicePixelRatio ?? 1.0) > 0
        ? (view?.devicePixelRatio ?? 1.0)
        : 1.0;
    return event.location / dpr;
  }

  DragTargetDetails<BrowserItemDragData> _detailsFor(
    _HandedOffDrag active,
    DesktopDropEvent event,
  ) => DragTargetDetails<BrowserItemDragData>(
    data: active.data,
    offset: _logical(event),
  );

  void _beginSession(_HandedOffDrag active) {
    final session = active.container.read(browserDragSessionProvider.notifier);
    if (!_sessionBegun) {
      _sessionBegun = session.tryBegin(active.sourceTab, active.startPosition);
    }
  }

  void _endSession() {
    final active = _active;
    if (!_sessionBegun || active == null) {
      _sessionBegun = false;
      return;
    }
    _sessionBegun = false;
    active.container.read(browserDragSessionProvider.notifier).end();
  }

  /// Finds the target under the pointer and keeps it highlighted.
  void _update(_HandedOffDrag active, DesktopDropEvent event) {
    final details = _detailsFor(active, event);
    active.container
        .read(browserDragSessionProvider.notifier)
        .updatePointer(details.offset);

    // The first target under the pointer that takes the drag, innermost first,
    // as with Flutter's own drag and drop.
    OwnDragDropTarget? best;
    for (final target in _targetsAt(details.offset, event.viewId)) {
      if (target.ownCanAccept(details)) {
        best = target;
        break;
      }
    }
    if (identical(best, _hover)) {
      _hover?.ownDragMove(details);
      return;
    }
    _hover?.ownDragLeave();
    _hover = best;
    best?.ownDragEnter(details);
  }

  /// The registered targets under [position] in [viewId], innermost first.
  List<OwnDragDropTarget> _targetsAt(Offset position, int viewId) {
    final byRenderObject = _targetsByView.putIfAbsent(
      viewId,
      () => _buildTargetIndex(viewId),
    );
    if (byRenderObject.isEmpty) return const <OwnDragDropTarget>[];
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(result, position, viewId);
    final found = <OwnDragDropTarget>[];
    for (final entry in result.path) {
      final target = entry.target;
      if (target is! RenderObject) continue;
      final match = byRenderObject[target];
      if (match != null) found.add(match);
    }
    return found;
  }

  Map<RenderObject, OwnDragDropTarget> _buildTargetIndex(int viewId) {
    final byRenderObject = <RenderObject, OwnDragDropTarget>{};
    for (final target in _targets) {
      if (target.dropViewId != viewId) continue;
      final renderObject = target.dropRenderObject;
      if (renderObject != null && renderObject.attached) {
        byRenderObject[renderObject] = target;
      }
    }
    return byRenderObject;
  }

  void _leaveHover() {
    final hover = _hover;
    _hover = null;
    hover?.ownDragLeave();
  }
}

class _HandedOffDrag {
  const _HandedOffDrag(
    this.data,
    this.container,
    this.sourceTab,
    this.startPosition,
  );

  final BrowserItemDragData data;
  final ProviderContainer container;
  final TabId sourceTab;
  final Offset startPosition;
}
