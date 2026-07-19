import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import '../../../models/vault_list_item.dart';
import '../../../theme.dart';
import 'container_card.dart';

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
}

class StrictHorizontalDragGestureRecognizer extends HorizontalDragGestureRecognizer {
  StrictHorizontalDragGestureRecognizer({super.debugOwner});

  final Map<int, Offset> _startPositions = {};

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    _startPositions[event.pointer] = event.position;
  }

  @override
  void handleEvent(PointerEvent event) {
    super.handleEvent(event);
    if (event is PointerMoveEvent) {
      final startPosition = _startPositions[event.pointer];
      if (startPosition != null) {
        final delta = event.position - startPosition;
        final double dx = delta.dx.abs();
        final double dy = delta.dy.abs();

        if (dy > dx && dy > 6.0) {
          rejectGesture(event.pointer);
          _startPositions.remove(event.pointer);
        } else if (dx > 12.0) {
          _startPositions.remove(event.pointer);
        }
      }
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      _startPositions.remove(event.pointer);
    }
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
  
  // Guard flag to prevent triggering the nudge multiple times within the same cycle
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

    // Handles trigger on fresh initial build
    if (widget.triggerNudge && !widget.isInserting) {
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

    // Checks for transitions when returning from other screens (like AppSettingsScreen)
    if (widget.triggerNudge && !oldWidget.triggerNudge && !_hasTriggeredNudge) {
      _hasTriggeredNudge = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _triggerPeekNudge();
      });
    } else if (!widget.triggerNudge) {
      // Reset the local trigger flag once triggerNudge becomes false
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
    debugPrint('[VaultCardRow] Nudge checks passed. Starting delayed trigger...');
    if (!mounted || _isDragging || _openSide != _OpenSide.none) return;

    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;

    debugPrint('[VaultCardRow] Executing nudge slide actions...');
    await _animatePeekTo(-100.0, const Duration(milliseconds: 500));
    await Future.delayed(const Duration(milliseconds: 650));

    await _animatePeekTo(100.0, const Duration(milliseconds: 500));
    await Future.delayed(const Duration(milliseconds: 650));

    await _animatePeekTo(0.0, const Duration(milliseconds: 500));
    
    if (mounted) {
      debugPrint('[VaultCardRow] Nudge complete, calling onNudgeComplete callback.');
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
    if (!_isDragging) return;

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

    final card = switch (widget.item) {
      MountedVaultItem(:final container) => ContainerCard(
          key: ValueKey('mounted_${widget.item.uri}'),
          container: container,
          onLocked: widget.onLocked,
          onBrowse: _handleTap,
          borderRadius: dynamicRadius,
        ),
      LockedVaultItem() => SavedContainerCard(
          key: ValueKey('locked_${widget.item.uri}'),
          name: widget.item.name,
          uri: widget.item.uri,
          onUnlock: _handleTap,
          borderRadius: dynamicRadius,
        ),
    };

    // Progress is tied to drag *position* (left slot reveals when dragging
    // right, right slot reveals when dragging left) — swapActions only
    // changes which action/icon/color sits in which slot, not the physics.
    final leftSlotProgress = (_dx / _revealExtent).clamp(0.0, 1.0);
    final rightSlotProgress = (-_dx / _revealExtent).clamp(0.0, 1.0);

    final leftIsDelete = !widget.swapActions;
    final leftIcon = leftIsDelete ? Icons.delete_outline_rounded : Icons.edit_outlined;
    final leftLabel = leftIsDelete ? 'Delete' : 'Edit';
    final leftBackground = leftIsDelete ? cs.errorContainer : cs.secondaryContainer;
    final leftForeground = leftIsDelete ? cs.onErrorContainer : cs.onSecondaryContainer;
    final leftOnTap = leftIsDelete ? _fireDelete : _fireEdit;

    final rightIsDelete = widget.swapActions;
    final rightIcon = rightIsDelete ? Icons.delete_outline_rounded : Icons.edit_outlined;
    final rightLabel = rightIsDelete ? 'Delete' : 'Edit';
    final rightBackground = rightIsDelete ? cs.errorContainer : cs.secondaryContainer;
    final rightForeground = rightIsDelete ? cs.onErrorContainer : cs.onSecondaryContainer;
    final rightOnTap = rightIsDelete ? _fireDelete : _fireEdit;

    final isHidden = widget.isRemoving || _isCurrentlyInserting;


    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 300),
        opacity: isHidden ? 0.0 : 1.0,
        child: isHidden
            ? const SizedBox(width: double.infinity, height: 0)
            : _maybeDragWrap(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Semantics(
                    customSemanticsActions: {
                      const CustomSemanticsAction(label: 'Edit'): widget.onEdit,
                      const CustomSemanticsAction(label: 'Delete'): widget.onDelete,
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.xl),
                      child: Stack(
                        children: [
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
                          RawGestureDetector(
                            gestures: <Type, GestureRecognizerFactory>{
                              StrictHorizontalDragGestureRecognizer:
                                  GestureRecognizerFactoryWithHandlers<StrictHorizontalDragGestureRecognizer>(
                                () => StrictHorizontalDragGestureRecognizer(),
                                (StrictHorizontalDragGestureRecognizer instance) {
                                  instance
                                    ..onStart = _onDragStart
                                    ..onUpdate = _onDragUpdate
                                    ..onEnd = _onDragEnd
                                    ..onCancel = _onDragCancel;
                                },
                              ),
                            },
                            child: Transform.translate(
                              offset: Offset(_dx, 0),
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 250),
                                switchInCurve: Curves.easeOutCubic,
                                switchOutCurve: Curves.easeInCubic,
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