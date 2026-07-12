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
  }

  @override
  void didUpdateWidget(covariant VaultCardRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.group != widget.group) {
      oldWidget.group.removeListener(_onGroupChanged);
      widget.group.addListener(_onGroupChanged);
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

  void _animateTo(_OpenSide target) {
    final targetDx = switch (target) {
      _OpenSide.start => _revealExtent,
      _OpenSide.end => -_revealExtent,
      _OpenSide.none => 0.0,
    };

    _controller.stop();
    _controller.reset();
    final animation = Tween<double>(begin: _dx, end: targetDx).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    void listener() => setState(() => _dx = animation.value);
    animation.addListener(listener);
    _controller.forward().whenCompleteOrCancel(() => animation.removeListener(listener));

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

    final deleteProgress = (_dx / _revealExtent).clamp(0.0, 1.0);
    final editProgress = (-_dx / _revealExtent).clamp(0.0, 1.0);

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
            : ReorderableDelayedDragStartListener(
                index: widget.index,
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
                                    icon: Icons.delete_outline_rounded,
                                    label: 'Delete',
                                    background: cs.errorContainer,
                                    foreground: cs.onErrorContainer,
                                    progress: deleteProgress,
                                    onTap: _fireDelete,
                                  ),
                                ),
                                const Spacer(),
                                SizedBox(
                                  width: _revealExtent,
                                  child: _SwipeActionButton(
                                    icon: Icons.edit_outlined,
                                    label: 'Edit',
                                    background: cs.secondaryContainer,
                                    foreground: cs.onSecondaryContainer,
                                    progress: editProgress,
                                    onTap: _fireEdit,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          GestureDetector(
                            onHorizontalDragStart: _onDragStart,
                            onHorizontalDragUpdate: _onDragUpdate,
                            onHorizontalDragEnd: _onDragEnd,
                            onHorizontalDragCancel: _onDragCancel,
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