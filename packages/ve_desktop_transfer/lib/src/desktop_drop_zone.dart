import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:ve_desktop_transfer/ve_desktop_transfer.dart';

/// Multi-window-aware native OS file drop target widget.
///
/// Unlike `desktop_drop`, each [DesktopDropTarget] filters incoming native drop
/// events by its owning `View.maybeOf(context)?.viewId` and retains the native
/// view registration while mounted, so peer windows created by Flutter's
/// multi-window host (`ViewCollection`) all accept OS drops independently.
class DesktopDropTarget extends StatefulWidget {
  const DesktopDropTarget({
    super.key,
    required this.child,
    this.enable = true,
    this.onDragEntered,
    this.onDragUpdated,
    this.onDragExited,
    this.onDragDone,
  });

  final Widget child;
  final bool enable;
  final ValueChanged<DesktopDropDetails>? onDragEntered;
  final ValueChanged<DesktopDropDetails>? onDragUpdated;
  final ValueChanged<DesktopDropDetails>? onDragExited;
  final ValueChanged<DesktopDropDetails>? onDragDone;

  @override
  State<DesktopDropTarget> createState() => _DesktopDropTargetState();
}

enum _DropTargetStatus { idle, entered, updated }

class _DesktopDropTargetState extends State<DesktopDropTarget> {
  _DropTargetStatus _status = _DropTargetStatus.idle;
  int? _registeredViewId;
  bool _listening = false;

  @override
  void initState() {
    super.initState();
    _syncListener();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final viewId = View.maybeOf(context)?.viewId;
    if (viewId != _registeredViewId) {
      final prev = _registeredViewId;
      _registeredViewId = viewId;
      if (prev != null) {
        unawaited(VeDesktopTransfer.instance.releaseView(prev));
      }
      if (viewId != null) {
        unawaited(VeDesktopTransfer.instance.retainView(viewId));
      }
    }
  }

  @override
  void didUpdateWidget(covariant DesktopDropTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enable != oldWidget.enable) {
      _syncListener();
      if (!widget.enable && _status != _DropTargetStatus.idle) {
        _setStatus(
          _DropTargetStatus.idle,
          localPosition: Offset.zero,
          globalPosition: Offset.zero,
        );
      }
    }
  }

  void _syncListener() {
    if (widget.enable && !_listening) {
      VeDesktopTransfer.instance.addDropListener(_onDropEvent);
      _listening = true;
    } else if (!widget.enable && _listening) {
      VeDesktopTransfer.instance.removeDropListener(_onDropEvent);
      _listening = false;
    }
  }

  Offset _scaleLogicalPoint(BuildContext context, Offset rawPoint) {
    if (Platform.isWindows) {
      final dpr = MediaQuery.devicePixelRatioOf(context);
      if (dpr > 0) return rawPoint / dpr;
    }
    return rawPoint;
  }

  void _onDropEvent(DesktopDropEvent event) {
    if (!mounted || !widget.enable) return;
    final viewId = _registeredViewId;
    if (viewId != null && event.viewId != viewId) return;

    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;

    final globalPos = _scaleLogicalPoint(context, event.location);
    final localPos = box.globalToLocal(globalPos);
    final inBounds = box.paintBounds.contains(localPos);

    switch (event.kind) {
      case DesktopDropEventKind.entered:
        if (inBounds) {
          _setStatus(
            _DropTargetStatus.entered,
            localPosition: localPos,
            globalPosition: globalPos,
          );
        }
      case DesktopDropEventKind.updated:
        if (inBounds) {
          _setStatus(
            _status == _DropTargetStatus.idle
                ? _DropTargetStatus.entered
                : _DropTargetStatus.updated,
            localPosition: localPos,
            globalPosition: globalPos,
          );
        } else if (_status != _DropTargetStatus.idle) {
          _setStatus(
            _DropTargetStatus.idle,
            localPosition: localPos,
            globalPosition: globalPos,
          );
        }
      case DesktopDropEventKind.exited:
        if (_status != _DropTargetStatus.idle) {
          _setStatus(
            _DropTargetStatus.idle,
            localPosition: localPos,
            globalPosition: globalPos,
          );
        }
      case DesktopDropEventKind.dropped:
        if (_status != _DropTargetStatus.idle) {
          _setStatus(
            _DropTargetStatus.idle,
            localPosition: localPos,
            globalPosition: globalPos,
          );
        }
        // The drop event is authoritative. Enter/update notifications can be
        // missed while a window is busy; the native target only sends usable
        // paths for an accepted format, and the bounds check keeps this zone
        // from taking drops elsewhere in the view.
        if (inBounds && event.paths.isNotEmpty) {
          widget.onDragDone?.call(
            DesktopDropDetails(
              localPosition: localPos,
              globalPosition: globalPos,
              paths: event.paths,
            ),
          );
        }
    }
  }

  void _setStatus(
    _DropTargetStatus next, {
    required Offset localPosition,
    required Offset globalPosition,
  }) {
    if (_status == next && next != _DropTargetStatus.updated) return;
    _status = next;
    final details = DesktopDropDetails(
      localPosition: localPosition,
      globalPosition: globalPosition,
    );
    switch (next) {
      case _DropTargetStatus.entered:
        widget.onDragEntered?.call(details);
      case _DropTargetStatus.updated:
        widget.onDragUpdated?.call(details);
      case _DropTargetStatus.idle:
        widget.onDragExited?.call(details);
    }
  }

  @override
  void dispose() {
    if (_listening) {
      VeDesktopTransfer.instance.removeDropListener(_onDropEvent);
      _listening = false;
    }
    final prev = _registeredViewId;
    _registeredViewId = null;
    if (prev != null) {
      unawaited(VeDesktopTransfer.instance.releaseView(prev));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
