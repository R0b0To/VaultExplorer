import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/semantics.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/data/models/vault_list_item.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/features/dashboard/widgets/container_card.dart';

enum _OpenSide { none, start, end }

class SwipeRowGroupController extends ChangeNotifier {
  Object? _openId;
  Object? get openId => _openId;

  void notifyOpened(Object id) {
    if (_openId != id) {
      _openId = id;
      notifyListeners();
    }
  }

  void notifyClosed(Object id) {
    if (_openId == id) {
      _openId = null;
      notifyListeners();
    }
  }

  /// Closes whichever card is currently open, if any. Used when the user's
  /// swipe continues past an already-open card into opening the navigation
  /// drawer -- at that point the card reveal was never the intent, so it
  /// shouldn't stay open underneath the drawer.
  void closeAll() {
    if (_openId != null) {
      _openId = null;
      notifyListeners();
    }
  }
}

class StrictHorizontalDragGestureRecognizer extends HorizontalDragGestureRecognizer {
  StrictHorizontalDragGestureRecognizer({super.debugOwner});
  final Map<int, Offset> _startPositions = {};

  /// Called with the drag's cumulative delta so far. Return true to let a
  /// rightward drag fall through to an ancestor gesture detector instead of
  /// being claimed here -- used when the card is already fully open toward
  /// [_OpenSide.start] and there's nothing left to reveal, so a second swipe
  /// hands off to the dashboard's drawer-open gesture. Mirrors how the
  /// drawer's own swipeable rows (_CardHorizontalDragGestureRecognizer)
  /// reject a leftward drag on a closed row so the drawer can close.
  bool Function(Offset delta)? shouldYieldHorizontal;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    _startPositions[event.pointer] = event.position;
  }

  @override
  void rejectGesture(int pointer) {
    _startPositions.remove(pointer);
    super.rejectGesture(pointer);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) {
      final startPosition = _startPositions[event.pointer];
      if (startPosition != null) {
        final delta = event.position - startPosition;
        final double dx = delta.dx.abs();
        final double dy = delta.dy.abs();

        // 1. If movement is vertical, yield to ReorderableListView scrolling
        if (dy > dx && dy > kTouchSlop) {
          resolve(GestureDisposition.rejected);
          _startPositions.remove(event.pointer);
          return;
        }
        // 2. If movement is horizontal on the card, claim victory! -- unless
        // there's nothing left for this card to reveal in that direction,
        // in which case yield to whatever ancestor gesture wants it (the
        // drawer-open swipe).
        else if (dx > 8.0 && dx > dy) {
          if (shouldYieldHorizontal?.call(delta) ?? false) {
            resolve(GestureDisposition.rejected);
            _startPositions.remove(event.pointer);
            return;
          }
          resolve(GestureDisposition.accepted);
          _startPositions.remove(event.pointer);
        }
      }
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      _startPositions.remove(event.pointer);
    }
    super.handleEvent(event);
  }

  @override
  void dispose() {
    _startPositions.clear();
    super.dispose();
  }
}

class VaultCardRow extends StatefulWidget {
  final int index;
  final VaultListItem item;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<int> onLocked;
  final SwipeRowGroupController group;
  final bool isRemoving;
  final bool isInserting;
  final bool triggerNudge;
  final VoidCallback? onNudgeComplete;
  final bool swapActions;
  final bool swipeEnabled;
  final bool dragEnabled;

  const VaultCardRow({
    super.key,
    required this.index,
    required this.item,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
    required this.onLocked,
    required this.group,
    this.isRemoving = false,
    this.isInserting = false,
    this.triggerNudge = false,
    this.onNudgeComplete,
    this.swapActions = false,
    this.swipeEnabled = true,
    this.dragEnabled = true,
  });

  @override
  State<VaultCardRow> createState() => _VaultCardRowState();
}

class _VaultCardRowState extends State<VaultCardRow>
    with SingleTickerProviderStateMixin {
  static const double _revealExtent = 96;
  static const double _flingVelocity = 1200.0;

  late final AnimationController _controller;
  double _dx = 0;
  _OpenSide _openSide = _OpenSide.none;
  _OpenSide _gestureStartSide = _OpenSide.none;
  bool _isDragging = false;
  bool _isCurrentlyInserting = false;
  bool _hasTriggeredNudge = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
    widget.group.addListener(_onGroupChanged);
    if (widget.isInserting) {
      _isCurrentlyInserting = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _isCurrentlyInserting = false;
          });
        }
      });
    }
    if (widget.triggerNudge && !widget.isInserting && widget.swipeEnabled) {
      _hasTriggeredNudge = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _triggerPeekNudge();
      });
    }
  }

  @override
  void didUpdateWidget(covariant VaultCardRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.group != widget.group) {
      oldWidget.group.removeListener(_onGroupChanged);
      widget.group.addListener(_onGroupChanged);
    }
    if (!widget.swipeEnabled && _openSide != _OpenSide.none) {
      _animateTo(_OpenSide.none);
    }
    if (widget.triggerNudge && !oldWidget.triggerNudge && !_hasTriggeredNudge && widget.swipeEnabled) {
      _hasTriggeredNudge = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _triggerPeekNudge();
      });
    } else if (!widget.triggerNudge || !widget.swipeEnabled) {
      _hasTriggeredNudge = false;
    }
  }

  @override
  void dispose() {
    widget.group.removeListener(_onGroupChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onGroupChanged() {
    if (widget.group.openId != widget.item.uri && _openSide != _OpenSide.none) {
      _animateTo(_OpenSide.none);
    }
  }

  Future<void> _triggerPeekNudge() async {

    if (!mounted || _isDragging || _openSide != _OpenSide.none || !widget.swipeEnabled) return;
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;

    await _animatePeekTo(-90.0, const Duration(milliseconds: 500));
    await Future.delayed(const Duration(milliseconds: 650));
    await _animatePeekTo(90.0, const Duration(milliseconds: 500));
    await Future.delayed(const Duration(milliseconds: 650));
    await _animatePeekTo(0.0, const Duration(milliseconds: 500));
    if (mounted) {

      widget.onNudgeComplete?.call();
    }
  }

  Future<void> _animatePeekTo(double targetDx, Duration duration) {
    final completer = Completer<void>();
    if (!mounted) return Future.value();
    _controller.stop();
    _controller.duration = duration;
    _controller.reset();
    final animation = Tween<double>(begin: _dx, end: targetDx).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic),
    );
    void listener() => setState(() => _dx = animation.value);
    animation.addListener(listener);
    _controller.forward().whenCompleteOrCancel(() {
      animation.removeListener(listener);
      completer.complete();
    });
    return completer.future;
  }

  void _animateTo(_OpenSide target) {
    final targetDx = switch (target) {
      _OpenSide.start => _revealExtent,
      _OpenSide.end => -_revealExtent,
      _OpenSide.none => 0.0,
    };
    _controller.stop();
    _controller.duration = const Duration(milliseconds: 220);
    _controller.reset();
    final animation = Tween<double>(begin: _dx, end: targetDx).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    void listener() => setState(() => _dx = animation.value);
    animation.addListener(listener);
    _controller.forward().whenCompleteOrCancel(() {
      animation.removeListener(listener);
    });
    setState(() => _openSide = target);
    if (target == _OpenSide.none) {
      widget.group.notifyClosed(widget.item.uri);
    } else {
      widget.group.notifyOpened(widget.item.uri);
    }
  }

   void _onDragStart(DragStartDetails details) {
    _isDragging = true;
    _controller.stop();
    _gestureStartSide = _openSide;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_isDragging) {
      _isDragging = true;
      _controller.stop();
      _gestureStartSide = _openSide;
    }
    setState(() {
      final next = _dx + details.delta.dx;
      _dx = switch (_gestureStartSide) {
        _OpenSide.start => next.clamp(0.0, _revealExtent),
        _OpenSide.end => next.clamp(-_revealExtent, 0.0),
        _OpenSide.none => next.clamp(-_revealExtent, _revealExtent),
      };
    });
  }

  void _onDragEnd(DragEndDetails details) {
    if (!_isDragging) return;
    _isDragging = false;
    final velocity = details.primaryVelocity ?? 0.0;
    final _OpenSide target;
    if (velocity > _flingVelocity) {
      target = _dx > 0 ? _OpenSide.start : _OpenSide.none;
    } else if (velocity < -_flingVelocity) {
      target = _dx < 0 ? _OpenSide.end : _OpenSide.none;
    } else if (_dx > _revealExtent / 2) {
      target = _OpenSide.start;
    } else if (_dx < -_revealExtent / 2) {
      target = _OpenSide.end;
    } else {
      target = _OpenSide.none;
    }
    _animateTo(target);
  }

  Widget _maybeDragWrap({required Widget child}) {
    if (!widget.dragEnabled) return child;
    return ReorderableDelayedDragStartListener(index: widget.index, child: child);
  }

  void _onDragCancel() {
    if (!_isDragging) return;
    _isDragging = false;
    _animateTo(_gestureStartSide);
  }

  void _handleTap() {
    if (_openSide != _OpenSide.none) {
      _animateTo(_OpenSide.none);
    } else {
      widget.onOpen();
    }
  }

  void _fireDelete() {
    widget.onDelete();
    _animateTo(_OpenSide.none);
  }

  void _fireEdit() {
    widget.onEdit();
    _animateTo(_OpenSide.none);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final double leftRadius = _dx > 0
        ? AppRadius.xl * (1 - (_dx / AppRadius.xl).clamp(0.0, 1.0))
        : AppRadius.xl;
    final double rightRadius = _dx < 0
        ? AppRadius.xl * (1 - (-_dx / AppRadius.xl).clamp(0.0, 1.0))
        : AppRadius.xl;
    final dynamicRadius = BorderRadius.horizontal(
      left: Radius.circular(leftRadius),
      right: Radius.circular(rightRadius),
    );

    final card = SizedBox(
      width: double.infinity,
      child: switch (widget.item) {
        MountedVaultItem(:final container) => ContainerCard(
            key: ValueKey('mounted_${widget.item.uri}'),
            container: container,
            onLocked: widget.onLocked,
            onBrowse: _handleTap,
            borderRadius: dynamicRadius,
          ),
        LockedVaultItem(:final record) => SavedContainerCard(
            key: ValueKey('locked_${widget.item.uri}'),
            name: widget.item.name,
            uri: widget.item.uri,
            containerFormat: record.containerFormat,
            onUnlock: _handleTap,
            borderRadius: dynamicRadius,
          ),
      },
    );

    final leftSlotProgress = (_dx / _revealExtent).clamp(0.0, 1.0);
    final rightSlotProgress = (-_dx / _revealExtent).clamp(0.0, 1.0);
    final leftIsDelete = !widget.swapActions;
    final leftIcon = leftIsDelete ? Icons.delete_outline_rounded : Icons.edit_outlined;
    final leftLabel = leftIsDelete ? context.l10n.remove : context.l10n.edit;
    final leftBackground = leftIsDelete ? cs.errorContainer : cs.secondaryContainer;
    final leftForeground = leftIsDelete ? cs.onErrorContainer : cs.onSecondaryContainer;
    final leftOnTap = leftIsDelete ? _fireDelete : _fireEdit;
    final rightIsDelete = widget.swapActions;
    final rightIcon = rightIsDelete ? Icons.delete_outline_rounded : Icons.edit_outlined;
    final rightLabel = rightIsDelete ? context.l10n.remove : context.l10n.edit;
    final rightBackground = rightIsDelete ? cs.errorContainer : cs.secondaryContainer;
    final rightForeground = rightIsDelete ? cs.onErrorContainer : cs.onSecondaryContainer;
    final rightOnTap = rightIsDelete ? _fireDelete : _fireEdit;
    final isHidden = widget.isRemoving || _isCurrentlyInserting;

    if (!widget.swipeEnabled) {
      return AnimatedSize(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        alignment: Alignment.topCenter,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 300),
          opacity: isHidden ? 0.0 : 1.0,
          child: isHidden
              ? const SizedBox(width: double.infinity, height: 0)
              : Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _maybeDragWrap(child: card),
                ),
        ),
      );
    }

    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 300),
        opacity: isHidden ? 0.0 : 1.0,
        child: isHidden
            ? const SizedBox(width: double.infinity, height: 0)
            : Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _maybeDragWrap(
                  child: Semantics(
                    customSemanticsActions: widget.swipeEnabled
                        ? {
                            CustomSemanticsAction(label: context.l10n.edit): widget.onEdit,
                            CustomSemanticsAction(label: context.l10n.delete): widget.onDelete,
                          }
                        : const {},
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.xl),
                      child: Stack(
                        children: [
                          if (widget.swipeEnabled)
                            Positioned.fill(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  SizedBox(
                                    width: _revealExtent,
                                    child: _SwipeActionButton(
                                      icon: leftIcon,
                                      label: leftLabel,
                                      background: leftBackground,
                                      foreground: leftForeground,
                                      progress: leftSlotProgress,
                                      onTap: leftOnTap,
                                    ),
                                  ),
                                  const Spacer(),
                                  SizedBox(
                                    width: _revealExtent,
                                    child: _SwipeActionButton(
                                      icon: rightIcon,
                                      label: rightLabel,
                                      background: rightBackground,
                                      foreground: rightForeground,
                                      progress: rightSlotProgress,
                                      onTap: rightOnTap,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    Transform.translate(
                            offset: Offset(_dx, 0),
                            child: RawGestureDetector(
                              behavior: HitTestBehavior.opaque,
                              gestures: <Type, GestureRecognizerFactory>{
                                if (widget.swipeEnabled)
                                  StrictHorizontalDragGestureRecognizer:
                                      GestureRecognizerFactoryWithHandlers<StrictHorizontalDragGestureRecognizer>(
                                    () => StrictHorizontalDragGestureRecognizer(),
                                    (StrictHorizontalDragGestureRecognizer instance) {
                                      instance
                                        ..onStart = _onDragStart
                                        ..onUpdate = _onDragUpdate
                                        ..onEnd = _onDragEnd
                                        ..onCancel = _onDragCancel
                                        ..shouldYieldHorizontal = (delta) =>
                                            _openSide == _OpenSide.start && delta.dx > 0;
                                    },
                                  ),
                              },
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 220),
                                switchInCurve: Curves.easeOutCubic,
                                switchOutCurve: Curves.easeInCubic,
                                layoutBuilder: (currentChild, previousChildren) => Stack(
                                  alignment: Alignment.topCenter,
                                  children: [
                                    ...previousChildren.map(
                                      (child) => currentChild != null
                                          ? Positioned.fill(child: child)
                                          : child,
                                    ),
                                    ?currentChild,
                                  ],
                                ),
                                transitionBuilder: (child, animation) =>
                                    FadeTransition(opacity: animation, child: child),
                                child: card,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }

    }

class _SwipeActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;
  final double progress;
  final VoidCallback onTap;
  const _SwipeActionButton({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
    required this.progress,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: progress,
      child: Material(
        color: background,
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: foreground, size: AppIconSize.standard),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}