import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/responsive.dart';
import 'package:vaultexplorer/data/models/media_viewer_action.dart';
import 'package:vaultexplorer/data/models/media_viewer_toolbar_config.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/media_viewer_action_glyph.dart';

extension _InPlaceEditorL10n on BuildContext {
  String get inPlaceDoneLabel {
    try {
      final val = (l10n as dynamic).inPlaceEditDone;
      if (val is String && val.isNotEmpty) return val;
    } catch (_) {
      // Safe: Fall back to default string if translation key is not yet present on l10n.
    }
    return 'Done';
  }

  String get inPlaceTitleLabel {
    try {
      final val = (l10n as dynamic).inPlaceEditTitle;
      if (val is String && val.isNotEmpty) return val;
    } catch (_) {
      // Safe: Fall back to default string if translation key is not yet present on l10n.
    }
    return l10n.mediaViewerCustomizeControls;
  }

  String get inPlaceHintLabel {
    try {
      final val = (l10n as dynamic).inPlaceEditHint;
      if (val is String && val.isNotEmpty) return val;
    } catch (_) {
      // Safe: Fall back to default string if translation key is not yet present on l10n.
    }
    return 'Drag actions between docks or tap to organize';
  }

  String get inPlaceTopDockLabel {
    try {
      final val = (l10n as dynamic).inPlaceEditTopDock;
      if (val is String && val.isNotEmpty) return val;
    } catch (_) {
      // Safe: Fall back to default string if translation key is not yet present on l10n.
    }
    return l10n.topBarActionsHeader;
  }

  String get inPlaceBottomDockLabel {
    try {
      final val = (l10n as dynamic).inPlaceEditBottomDock;
      if (val is String && val.isNotEmpty) return val;
    } catch (_) {
      // Safe: Fall back to default string if translation key is not yet present on l10n.
    }
    return l10n.bottomDockActionsHeader;
  }

  String get inPlaceDragToRemoveLabel {
    try {
      final val = (l10n as dynamic).inPlaceEditDragToRemove;
      if (val is String && val.isNotEmpty) return val;
    } catch (_) {
      // Safe: Fall back to default string if translation key is not yet present on l10n.
    }
    return 'Drag here to remove';
  }

  String get inPlaceAddToTopLabel {
    try {
      final val = (l10n as dynamic).inPlaceEditAddToTop;
      if (val is String && val.isNotEmpty) return val;
    } catch (_) {
      // Safe: Fall back to default string if translation key is not yet present on l10n.
    }
    return 'Add to Top Bar';
  }

  String get inPlaceAddToBottomLabel {
    try {
      final val = (l10n as dynamic).inPlaceEditAddToBottom;
      if (val is String && val.isNotEmpty) return val;
    } catch (_) {
      // Safe: Fall back to default string if translation key is not yet present on l10n.
    }
    return 'Add to Bottom Dock';
  }

  String get inPlaceMoveToMoreLabel {
    try {
      final val = (l10n as dynamic).inPlaceEditMoveToMore;
      if (val is String && val.isNotEmpty) return val;
    } catch (_) {
      // Safe: Fall back to default string if translation key is not yet present on l10n.
    }
    return 'Move to More Menu';
  }

  String get inPlaceMoveToAdvancedLabel {
    try {
      final val = (l10n as dynamic).inPlaceEditMoveToAdvanced;
      if (val is String && val.isNotEmpty) return val;
    } catch (_) {
      // Safe: Fall back to default string if translation key is not yet present on l10n.
    }
    return 'Move to Advanced Settings';
  }

  String get inPlaceHideActionLabel {
    try {
      final val = (l10n as dynamic).inPlaceEditHideAction;
      if (val is String && val.isNotEmpty) return val;
    } catch (_) {
      // Safe: Fall back to default string if translation key is not yet present on l10n.
    }
    return 'Hide Action';
  }

  String get inPlaceHiddenTabLabel {
    try {
      final val = (l10n as dynamic).inPlaceEditHidden;
      if (val is String && val.isNotEmpty) return val;
    } catch (_) {
      // Safe: Fall back to default string if translation key is not yet present on l10n.
    }
    return 'Hidden';
  }

  String get inPlaceEmptyDockLabel {
    try {
      final val = (l10n as dynamic).inPlaceEditEmptyDock;
      if (val is String && val.isNotEmpty) return val;
    } catch (_) {
      // Safe: Fall back to default string if translation key is not yet present on l10n.
    }
    return 'Drop actions here';
  }

  String get inPlacePlayerSettingsLabel {
    try {
      final val = (l10n as dynamic).inPlaceEditPlayerSettings;
      if (val is String && val.isNotEmpty) return val;
    } catch (_) {
      // Safe: Fall back to default string if translation key is not yet present on l10n.
    }
    return l10n.mediaPlayerControlsTitle;
  }
}

enum _PanelTab {
  more,
  advanced,
  hidden,
}

@immutable
class _DockDragData {
  final MediaViewerAction action;
  final String source; // 'top', 'bottom', 'more', 'advanced', 'hidden'
  final int? sourceIndex;

  const _DockDragData({
    required this.action,
    required this.source,
    this.sourceIndex,
  });
}

class MediaViewerInPlaceLayoutEditor extends StatefulWidget {
  final MediaViewerToolbarConfig toolbarConfig;
  final String? containerUri;
  final bool isImage;
  final bool isAudio;
  final bool isPlaylistMode;
  final ValueChanged<MediaViewerToolbarConfig> onConfigChanged;
  final VoidCallback onDone;
  final VoidCallback onOpenSettings;
  final VoidCallback onResetToDefaults;

  const MediaViewerInPlaceLayoutEditor({
    super.key,
    required this.toolbarConfig,
    this.containerUri,
    required this.isImage,
    required this.isAudio,
    required this.isPlaylistMode,
    required this.onConfigChanged,
    required this.onDone,
    required this.onOpenSettings,
    required this.onResetToDefaults,
  });

  @override
  State<MediaViewerInPlaceLayoutEditor> createState() =>
      _MediaViewerInPlaceLayoutEditorState();
}

class _MediaViewerInPlaceLayoutEditorState
    extends State<MediaViewerInPlaceLayoutEditor> {
  _DockDragData? _activeDrag;
  bool _isPickerExpanded = true;
  _PanelTab _selectedTab = _PanelTab.more;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<MediaViewerAction> get _topActions => widget.toolbarConfig.topBarActions;
  List<MediaViewerAction> get _bottomActions =>
      widget.toolbarConfig.bottomBarActions;
  List<MediaViewerAction> get _moreActions =>
      widget.toolbarConfig.moreMenuActions;
  List<MediaViewerAction> get _advancedActions =>
      widget.toolbarConfig.advancedSettingsActions;
  Set<MediaViewerAction> get _hiddenActions =>
      widget.toolbarConfig.hiddenActions;

  List<MediaViewerAction> _actionsForTab(_PanelTab tab) {
    final list = switch (tab) {
      _PanelTab.more => _moreActions,
      _PanelTab.advanced => _advancedActions,
      _PanelTab.hidden => _hiddenActions.toList(),
    };
    if (_searchQuery.isEmpty) return list;
    final q = _searchQuery.toLowerCase();
    return list.where((a) {
      final label = a.getLocalizedLabel(context.l10n).toLowerCase();
      return label.contains(q) || a.name.toLowerCase().contains(q);
    }).toList();
  }

  void _applyConfig({
    List<MediaViewerAction>? top,
    List<MediaViewerAction>? bottom,
    List<MediaViewerAction>? more,
    List<MediaViewerAction>? advanced,
    Set<MediaViewerAction>? hidden,
  }) {
    final updated = widget.toolbarConfig.copyWith(
      topBarActions: top ?? _topActions,
      bottomBarActions: bottom ?? _bottomActions,
      moreMenuActions: more ?? _moreActions,
      advancedSettingsActions: advanced ?? _advancedActions,
      hiddenActions: hidden ?? _hiddenActions,
    );
    widget.onConfigChanged(updated);
  }

  void _moveAction({
    required MediaViewerAction action,
    required String targetSection, // 'top', 'bottom', 'more', 'advanced', 'hidden'
    int? targetIndex,
  }) {
    final top = List<MediaViewerAction>.from(_topActions);
    final bottom = List<MediaViewerAction>.from(_bottomActions);
    final more = List<MediaViewerAction>.from(_moreActions);
    final advanced = List<MediaViewerAction>.from(_advancedActions);
    final hidden = Set<MediaViewerAction>.from(_hiddenActions);

    top.remove(action);
    bottom.remove(action);
    more.remove(action);
    advanced.remove(action);
    hidden.remove(action);

    switch (targetSection) {
      case 'top':
        if (targetIndex != null && targetIndex >= 0 && targetIndex <= top.length) {
          top.insert(targetIndex, action);
        } else {
          top.add(action);
        }
        break;
      case 'bottom':
        if (targetIndex != null &&
            targetIndex >= 0 &&
            targetIndex <= bottom.length) {
          bottom.insert(targetIndex, action);
        } else {
          bottom.add(action);
        }
        break;
      case 'more':
        more.add(action);
        break;
      case 'advanced':
        advanced.add(action);
        break;
      case 'hidden':
        hidden.add(action);
        break;
    }

    _applyConfig(
      top: top,
      bottom: bottom,
      more: more,
      advanced: advanced,
      hidden: hidden,
    );
    HapticFeedback.mediumImpact();
  }

  Widget _buildDragFeedback(MediaViewerAction action, ColorScheme cs) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: cs.primaryContainer,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 12,
              spreadRadius: 2,
            ),
          ],
          border: Border.all(color: cs.primary, width: 2),
        ),
        child: Center(
          child: MediaViewerActionGlyph(
            action: action,
            size: 24,
            color: cs.onPrimaryContainer,
          ),
        ),
      ),
    );
  }

  void _showActionContextMenu(
    BuildContext itemContext,
    MediaViewerAction action,
    String currentSection,
  ) {
    final RenderBox? overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    final RenderBox? renderBox =
        itemContext.findRenderObject() as RenderBox?;
    if (overlay == null || renderBox == null) return;

    final pos = renderBox.localToGlobal(Offset.zero);

    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        pos & renderBox.size,
        Offset.zero & overlay.size,
      ),
      items: [
        if (currentSection != 'top')
          PopupMenuItem<String>(
            value: 'top',
            child: Row(
              children: [
                const Icon(Icons.vertical_align_top_rounded, size: 18),
                const SizedBox(width: 8),
                Text(context.inPlaceAddToTopLabel),
              ],
            ),
          ),
        if (currentSection != 'bottom')
          PopupMenuItem<String>(
            value: 'bottom',
            child: Row(
              children: [
                const Icon(Icons.vertical_align_bottom_rounded, size: 18),
                const SizedBox(width: 8),
                Text(context.inPlaceAddToBottomLabel),
              ],
            ),
          ),
        if (currentSection != 'more')
          PopupMenuItem<String>(
            value: 'more',
            child: Row(
              children: [
                const Icon(Icons.more_horiz_rounded, size: 18),
                const SizedBox(width: 8),
                Text(context.inPlaceMoveToMoreLabel),
              ],
            ),
          ),
        if (currentSection != 'advanced')
          PopupMenuItem<String>(
            value: 'advanced',
            child: Row(
              children: [
                const Icon(Icons.tune_rounded, size: 18),
                const SizedBox(width: 8),
                Text(context.inPlaceMoveToAdvancedLabel),
              ],
            ),
          ),
        if (currentSection != 'hidden')
          PopupMenuItem<String>(
            value: 'hidden',
            child: Row(
              children: [
                const Icon(Icons.visibility_off_outlined, size: 18),
                const SizedBox(width: 8),
                Text(context.inPlaceHideActionLabel),
              ],
            ),
          ),
      ],
    ).then((selection) {
      if (selection != null) {
        _moveAction(action: action, targetSection: selection);
      }
    });
  }

  Widget _buildDockItem({
    required MediaViewerAction action,
    required String dockName,
    required int index,
    required ColorScheme cs,
  }) {
    final isHeroPlay = action == MediaViewerAction.playPause;
    final itemSize = isHeroPlay ? 44.0 : 40.0;
    final dragData = _DockDragData(
      action: action,
      source: dockName,
      sourceIndex: index,
    );

    return Builder(
      builder: (itemContext) {
        final buttonWidget = Container(
          width: itemSize,
          height: itemSize,
          decoration: BoxDecoration(
            color: isHeroPlay
                ? cs.primary
                : Colors.white.withValues(alpha: 0.14),
            shape: BoxShape.circle,
            border: Border.all(
              color: isHeroPlay ? cs.primary : Colors.white24,
              width: 1,
            ),
          ),
          child: Center(
            child: MediaViewerActionGlyph(
              action: action,
              size: isHeroPlay ? 26 : AppIconSize.standard,
              color: isHeroPlay ? cs.onPrimary : Colors.white,
            ),
          ),
        );

        return DragTarget<_DockDragData>(
          onWillAcceptWithDetails: (details) => true,
          onAcceptWithDetails: (details) {
            _moveAction(
              action: details.data.action,
              targetSection: dockName,
              targetIndex: index,
            );
          },
          builder: (context, candidateData, rejectedData) {
            final isHoverTarget = candidateData.isNotEmpty;

            return AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: isHoverTarget
                  ? BoxDecoration(
                      border: Border(
                        left: BorderSide(color: cs.primary, width: 3),
                      ),
                    )
                  : null,
              child: LongPressDraggable<_DockDragData>(
                data: dragData,
                delay: const Duration(milliseconds: 120),
                hapticFeedbackOnStart: true,
                onDragStarted: () => setState(() => _activeDrag = dragData),
                onDragEnd: (_) => setState(() => _activeDrag = null),
                feedback: _buildDragFeedback(action, cs),
                childWhenDragging: Opacity(
                  opacity: 0.25,
                  child: buttonWidget,
                ),
                child: Tooltip(
                  message: action.getLocalizedLabel(context.l10n),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(itemSize),
                    onTap: () => _showActionContextMenu(
                      itemContext,
                      action,
                      dockName,
                    ),
                    child: buttonWidget,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDockZone({
    required String title,
    required IconData icon,
    required String dockName,
    required List<MediaViewerAction> actions,
    required ColorScheme cs,
  }) {
    return DragTarget<_DockDragData>(
      onWillAcceptWithDetails: (details) => true,
      onAcceptWithDetails: (details) {
        _moveAction(
          action: details.data.action,
          targetSection: dockName,
          targetIndex: null,
        );
      },
      builder: (context, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty;

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isHovering
                ? cs.primaryContainer.withValues(alpha: 0.25)
                : Colors.black.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: isHovering
                  ? cs.primary
                  : Colors.white.withValues(alpha: 0.2),
              width: isHovering ? 2 : 1,
            ),
            boxShadow: isHovering
                ? [
                    BoxShadow(
                      color: cs.primary.withValues(alpha: 0.3),
                      blurRadius: 14,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(icon, size: 14, color: cs.primary),
                  const SizedBox(width: 6),
                  Text(
                    title,
                    style: TextStyle(
                      color: cs.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${actions.length}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (actions.isEmpty)
                Container(
                  height: 48,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.15),
                      style: BorderStyle.solid,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      context.inPlaceEmptyDockLabel,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                )
              else
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (int i = 0; i < actions.length; i++)
                        _buildDockItem(
                          action: actions[i],
                          dockName: dockName,
                          index: i,
                          cs: cs,
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTabButton({
    required _PanelTab tab,
    required String label,
    required int count,
    required IconData icon,
    required ColorScheme cs,
  }) {
    final isSelected = _selectedTab == tab;
    final sectionName = tab.name;

    return DragTarget<_DockDragData>(
      onWillAcceptWithDetails: (details) => true,
      onAcceptWithDetails: (details) {
        _moveAction(
          action: details.data.action,
          targetSection: sectionName,
        );
      },
      builder: (context, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty;

        return InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            setState(() {
              _selectedTab = tab;
            });
            HapticFeedback.lightImpact();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isHovering
                  ? cs.primaryContainer.withValues(alpha: 0.4)
                  : (isSelected
                      ? cs.primary.withValues(alpha: 0.2)
                      : Colors.transparent),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isHovering
                    ? cs.primary
                    : (isSelected
                        ? cs.primary.withValues(alpha: 0.6)
                        : Colors.white12),
                width: isHovering ? 2 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 14,
                  color: isSelected ? cs.primary : Colors.white70,
                ),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected ? cs.primary : Colors.white70,
                  ),
                ),
                const SizedBox(width: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? cs.primary
                        : Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? cs.onPrimary : Colors.white70,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPanelActionCard(
    MediaViewerAction action,
    String sectionName,
    ColorScheme cs,
  ) {
    final dragData = _DockDragData(action: action, source: sectionName);

    return Builder(
      builder: (cardContext) {
        final label = action.getLocalizedLabel(context.l10n);

        return LongPressDraggable<_DockDragData>(
          data: dragData,
          delay: const Duration(milliseconds: 120),
          hapticFeedbackOnStart: true,
          onDragStarted: () => setState(() => _activeDrag = dragData),
          onDragEnd: (_) => setState(() => _activeDrag = null),
          feedback: _buildDragFeedback(action, cs),
          childWhenDragging: Opacity(
            opacity: 0.3,
            child: _buildCardContent(action, label, cs, cardContext, sectionName),
          ),
          child: _buildCardContent(action, label, cs, cardContext, sectionName),
        );
      },
    );
  }

 Widget _buildCardContent(
    MediaViewerAction action,
    String label,
    ColorScheme cs,
    BuildContext cardContext,
    String sectionName,
  ) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _showActionContextMenu(cardContext, action, sectionName),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: cs.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            MediaViewerActionGlyph(
              action: action,
              size: 19,
              color: cs.primary,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.more_vert_rounded,
              size: 15,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPickerPanel(ColorScheme cs, {required bool isSidebar}) {
    final actions = _actionsForTab(_selectedTab);
    final sectionName = _selectedTab.name;

    return DragTarget<_DockDragData>(
      onWillAcceptWithDetails: (details) => true,
      onAcceptWithDetails: (details) {
        _moveAction(
          action: details.data.action,
          targetSection: sectionName,
        );
      },
      builder: (context, candidateData, rejectedData) {
        final isHoverTarget = candidateData.isNotEmpty;

        return Container(
          decoration: BoxDecoration(
            color: isHoverTarget
                ? cs.primaryContainer.withValues(alpha: 0.2)
                : Colors.black.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: isHoverTarget
                  ? cs.primary
                  : Colors.white.withValues(alpha: 0.2),
              width: isHoverTarget ? 2 : 1,
            ),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Tabs Header row
              Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildTabButton(
                            tab: _PanelTab.more,
                            label: 'More Menu',
                            count: _moreActions.length,
                            icon: Icons.more_horiz_rounded,
                            cs: cs,
                          ),
                          const SizedBox(width: 6),
                          _buildTabButton(
                            tab: _PanelTab.advanced,
                            label: 'Advanced',
                            count: _advancedActions.length,
                            icon: Icons.tune_rounded,
                            cs: cs,
                          ),
                          const SizedBox(width: 6),
                          _buildTabButton(
                            tab: _PanelTab.hidden,
                            label: context.inPlaceHiddenTabLabel,
                            count: _hiddenActions.length,
                            icon: Icons.visibility_off_outlined,
                            cs: cs,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (!isSidebar)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      icon: Icon(
                        _isPickerExpanded
                            ? Icons.keyboard_arrow_down_rounded
                            : Icons.keyboard_arrow_up_rounded,
                        color: Colors.white70,
                      ),
                      onPressed: () {
                        setState(() {
                          _isPickerExpanded = !_isPickerExpanded;
                        });
                      },
                    ),
                ],
              ),
              if (_isPickerExpanded || isSidebar) ...[
                const SizedBox(height: 8),
                SizedBox(
                  height: 34,
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(fontSize: 12, color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Search actions…',
                      hintStyle: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.45),
                      ),
                      prefixIcon: const Icon(Icons.search_rounded, size: 16),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 16),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      contentPadding: EdgeInsets.zero,
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.08),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (val) =>
                        setState(() => _searchQuery = val.trim()),
                  ),
                ),
                const SizedBox(height: 10),
                if (actions.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Center(
                      child: Text(
                        _searchQuery.isEmpty
                            ? 'No actions in this category'
                            : 'No matching actions',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.45),
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  )
                else if (isSidebar)
                  Expanded(
                    child: ListView.separated(
                      padding: EdgeInsets.zero,
                      itemCount: actions.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (context, i) =>
                          _buildPanelActionCard(actions[i], sectionName, cs),
                    ),
                  )
                  else
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: (MediaQuery.sizeOf(context).height * 0.28)
                          .clamp(170.0, 240.0),
                    ),
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: actions
                            .map((a) =>
                                _buildPanelActionCard(a, sectionName, cs))
                            .toList(),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildCenterRemoveDropZone(ColorScheme cs) {
    final showZone =
        _activeDrag != null &&
        (_activeDrag!.source == 'top' || _activeDrag!.source == 'bottom');

    return DragTarget<_DockDragData>(
      onWillAcceptWithDetails: (details) =>
          details.data.source == 'top' || details.data.source == 'bottom',
      onAcceptWithDetails: (details) => _moveAction(
        action: details.data.action,
        targetSection: 'hidden',
      ),
      builder: (context, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty;

        return IgnorePointer(
          ignoring: !showZone,
          child: AnimatedOpacity(
            opacity: showZone ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 150),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: isHovering
                      ? cs.errorContainer.withValues(alpha: 0.9)
                      : Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  border: Border.all(
                    color: isHovering ? cs.error : Colors.white30,
                    width: isHovering ? 2 : 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.visibility_off_outlined,
                      color: isHovering
                          ? cs.onErrorContainer
                          : Colors.white70,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      context.inPlaceDragToRemoveLabel,
                      style: TextStyle(
                        color: isHovering
                            ? cs.onErrorContainer
                            : Colors.white70,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTopHeaderBar(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.75),
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.12),
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            tooltip: context.inPlaceDoneLabel,
            onPressed: widget.onDone,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  context.inPlaceTitleLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                Text(
                  context.inPlaceHintLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.65),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.restart_alt_rounded, color: Colors.white70),
            tooltip: context.l10n.resetToDefaultsTooltip,
            onPressed: widget.onResetToDefaults,
          ),
          IconButton(
            icon: const Icon(Icons.tune_rounded, color: Colors.white70),
            tooltip: context.inPlacePlayerSettingsLabel,
            onPressed: widget.onOpenSettings,
          ),
          const SizedBox(width: 4),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: cs.primary,
              foregroundColor: cs.onPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              minimumSize: const Size(0, 36),
            ),
            icon: const Icon(Icons.check_rounded, size: 16),
            label: Text(
              context.inPlaceDoneLabel,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            onPressed: widget.onDone,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isLandscape = context.screen.isLandscape;
    final topInset = MediaQuery.paddingOf(context).top;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Material(
      color: Colors.transparent,
      child: SafeArea(
        top: false,
        bottom: false,
        child: isLandscape
            ? _buildLandscapeLayout(cs, topInset, bottomInset)
            : _buildPortraitLayout(cs, topInset, bottomInset),
      ),
    );
  }

  Widget _buildPortraitLayout(
    ColorScheme cs,
    double topInset,
    double bottomInset,
  ) {
    // Generous clearance above the Android 10+ gesture bar (at least 44-48dp)
    final safeBottomClearance = math.max(bottomInset, 24.0) + 20.0;

    return Stack(
      children: [
        // Drop-to-remove target in the live video center
        Positioned.fill(
          child: _buildCenterRemoveDropZone(cs),
        ),

        // Top Area: Header bar + Top Dock
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: topInset),
              _buildTopHeaderBar(cs),
              const SizedBox(height: 8),
              _buildDockZone(
                title: context.inPlaceTopDockLabel,
                icon: Icons.vertical_align_top_rounded,
                dockName: 'top',
                actions: _topActions,
                cs: cs,
              ),
            ],
          ),
        ),

        // Bottom Area: Panel + Bottom Dock (lifted well above gesture bar)
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.95),
                  Colors.black.withValues(alpha: 0.65),
                  Colors.transparent,
                ],
              ),
            ),
            padding: EdgeInsets.only(bottom: safeBottomClearance),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                  ),
                  child: _buildPickerPanel(cs, isSidebar: false),
                ),
                const SizedBox(height: 10),
                _buildDockZone(
                  title: context.inPlaceBottomDockLabel,
                  icon: Icons.vertical_align_bottom_rounded,
                  dockName: 'bottom',
                  actions: _bottomActions,
                  cs: cs,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLandscapeLayout(
    ColorScheme cs,
    double topInset,
    double bottomInset,
  ) {
    final safeBottomClearance = math.max(bottomInset, 20.0) + 12.0;
    const sidebarWidth = 340.0;

    return Stack(
      children: [
        // Left Area: Top Bar & Bottom Dock over live preview
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          right: sidebarWidth + 12,
          child: Stack(
            children: [
              Positioned.fill(
                child: _buildCenterRemoveDropZone(cs),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(height: topInset),
                    _buildTopHeaderBar(cs),
                    const SizedBox(height: 8),
                    _buildDockZone(
                      title: context.inPlaceTopDockLabel,
                      icon: Icons.vertical_align_top_rounded,
                      dockName: 'top',
                      actions: _topActions,
                      cs: cs,
                    ),
                  ],
                ),
              ),
              Positioned(
                bottom: safeBottomClearance,
                left: 0,
                right: 0,
                child: _buildDockZone(
                  title: context.inPlaceBottomDockLabel,
                  icon: Icons.vertical_align_bottom_rounded,
                  dockName: 'bottom',
                  actions: _bottomActions,
                  cs: cs,
                ),
              ),
            ],
          ),
        ),

        // Right Area: Dedicated Actions Column
        Positioned(
          top: topInset + 4,
          bottom: bottomInset + 4,
          right: 8,
          width: sidebarWidth,
          child: _buildPickerPanel(cs, isSidebar: true),
        ),
      ],
    );
  }
}