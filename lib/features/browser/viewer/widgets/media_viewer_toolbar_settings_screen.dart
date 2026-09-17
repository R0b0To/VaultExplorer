import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/models/media_viewer_action.dart';
import 'package:vaultexplorer/features/settings/file_manager_toolbar_settings_controller.dart';
import 'dart:async';

class _DragActionPayload {
  final MediaViewerAction action;
  final String fromSection; // 'top', 'bottom', 'more', 'advanced'
  final int fromIndex;

  const _DragActionPayload({
    required this.action,
    required this.fromSection,
    required this.fromIndex,
  });
}

class MediaViewerToolbarSettingsScreen extends ConsumerStatefulWidget {
  const MediaViewerToolbarSettingsScreen({super.key});

  @override
  ConsumerState<MediaViewerToolbarSettingsScreen> createState() =>
      _MediaViewerToolbarSettingsScreenState();
}



class _MediaViewerToolbarSettingsScreenState
    extends ConsumerState<MediaViewerToolbarSettingsScreen> {
  late final ScrollController _scrollController;
  Timer? _autoScrollTimer;
  double _autoScrollDelta = 0.0;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _stopAutoScroll();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    final screenHeight = MediaQuery.of(context).size.height;
    final dy = details.globalPosition.dy;
    const edgeThreshold = 120.0;
    const maxScrollStep = 15.0;

    if (dy < edgeThreshold) {
      final intensity = (edgeThreshold - dy) / edgeThreshold;
      _startAutoScroll(-maxScrollStep * intensity.clamp(0.2, 1.0));
    } else if (dy > screenHeight - edgeThreshold) {
      final intensity =
          (dy - (screenHeight - edgeThreshold)) / edgeThreshold;
      _startAutoScroll(maxScrollStep * intensity.clamp(0.2, 1.0));
    } else {
      _stopAutoScroll();
    }
  }

  void _startAutoScroll(double delta) {
    _autoScrollDelta = delta;
    if (_autoScrollTimer != null && _autoScrollTimer!.isActive) return;
    _autoScrollTimer =
        Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!_scrollController.hasClients) return;
      final target =
          (_scrollController.offset + _autoScrollDelta).clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );
      if (target != _scrollController.offset) {
        _scrollController.jumpTo(target);
      }
    });
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
  }

  void _onActionDropped({
    required _DragActionPayload payload,
    required String targetSection, // 'top', 'bottom', 'more', 'advanced'
    int? targetIndex,
  }) {
    final state = ref.read(fileManagerToolbarSettingsProvider(null));
    final mediaConfig = state.config.mediaViewerToolbarConfig;
    final controller =
        ref.read(fileManagerToolbarSettingsProvider(null).notifier);

    final top = List<MediaViewerAction>.from(mediaConfig.topBarActions);
    final bottom = List<MediaViewerAction>.from(mediaConfig.bottomBarActions);
    final more = List<MediaViewerAction>.from(mediaConfig.moreMenuActions);
    final advanced =
        List<MediaViewerAction>.from(mediaConfig.advancedSettingsActions);

    if (payload.fromSection == targetSection &&
        payload.fromIndex == targetIndex) {
      return;
    }

    // 1. Remove from source
    switch (payload.fromSection) {
      case 'top':
        if (payload.fromIndex < top.length) top.removeAt(payload.fromIndex);
        break;
      case 'bottom':
        if (payload.fromIndex < bottom.length) bottom.removeAt(payload.fromIndex);
        break;
      case 'more':
        if (payload.fromIndex < more.length) more.removeAt(payload.fromIndex);
        break;
      case 'advanced':
        if (payload.fromIndex < advanced.length) {
          advanced.removeAt(payload.fromIndex);
        }
        break;
    }

    // 2. Insert into target
    switch (targetSection) {
      case 'top':
        final idx = (targetIndex ?? top.length).clamp(0, top.length);
        top.insert(idx, payload.action);
        break;
      case 'bottom':
        final idx = (targetIndex ?? bottom.length).clamp(0, bottom.length);
        bottom.insert(idx, payload.action);
        break;
      case 'more':
        final idx = (targetIndex ?? more.length).clamp(0, more.length);
        more.insert(idx, payload.action);
        break;
      case 'advanced':
        final idx = (targetIndex ?? advanced.length).clamp(0, advanced.length);
        advanced.insert(idx, payload.action);
        break;
    }

    // 3. Atomically update all four sections together
    final updated = mediaConfig.copyWith(
      topBarActions: top,
      bottomBarActions: bottom,
      moreMenuActions: more,
      advancedSettingsActions: advanced,
    );
    controller.updateMediaViewerConfig(updated);
    HapticFeedback.mediumImpact();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(fileManagerToolbarSettingsProvider(null));
    final cs = context.colors;
    final textTheme = context.typography;
    final mediaConfig = state.config.mediaViewerToolbarConfig;
    final controller =
        ref.read(fileManagerToolbarSettingsProvider(null).notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Media Player Controls',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.restart_alt_rounded),
            tooltip: context.l10n.resetToDefaultsTooltip,
            onPressed: () {
              controller.resetMediaViewerConfigToDefaults();
              showAppSnackBar(
                context,
                message: 'Media controls reset to defaults',
                tone: AppBannerTone.success,
              );
            },
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: state.loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2.5))
          : SafeArea(
              child: ListView(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                children: [
                  const SectionHeader('Playback & Display'),
                  SectionCard(
                    children: [
                      SwitchListTile(
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 16),
                        value: mediaConfig.showProgressBar,
                        onChanged: controller.setMediaViewerShowProgressBar,
                        title: Text(
                          'Show Progress Bar (Scrubber)',
                          style: textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          'Timeline slider for videos and audio',
                          style: textTheme.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                        secondary: Icon(Icons.linear_scale_rounded,
                            color: cs.primary),
                      ),                
                      SwitchListTile(
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 16),
                        value: mediaConfig.showCenterTransportForImages,
                        onChanged: (val) {
                          controller.updateMediaViewerConfig(
                            mediaConfig.copyWith(
                                showCenterTransportForImages: val),
                          );
                        },
                        title: Text(
                          'Show Transport Controls on Photos',
                          style: textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          'Enable slideshow controls on images (off for minimalist view)',
                          style: textTheme.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                        secondary: Icon(Icons.slideshow_rounded,
                            color: cs.primary),
                      ),
                      SwitchListTile(
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 16),
                        value: mediaConfig.showStatusBadge,
                        onChanged: controller.setMediaViewerShowStatusBadge,
                        title: Text(
                          'Status Badge',
                          style: textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          'Shows slideshow timer or static photo indicator',
                          style: textTheme.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                        secondary:
                            Icon(Icons.badge_outlined, color: cs.primary),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const SectionHeader('Top Bar Actions'),
                  _buildSectionDropArea(
                    context: context,
                    sectionName: 'top',
                    actions: mediaConfig.topBarActions,
                    cs: cs,
                    textTheme: textTheme,
                    emptyHint: 'Drag actions here to pin to Top Bar',
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const SectionHeader('Bottom Dock Actions'),
                  _buildSectionDropArea(
                    context: context,
                    sectionName: 'bottom',
                    actions: mediaConfig.bottomBarActions,
                    cs: cs,
                    textTheme: textTheme,
                    emptyHint: 'Drag actions here to pin to Bottom Dock',
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const SectionHeader('More Menu (•••) Actions'),
                  _buildSectionDropArea(
                    context: context,
                    sectionName: 'more',
                    actions: mediaConfig.moreMenuActions,
                    cs: cs,
                    textTheme: textTheme,
                    emptyHint: 'Drag actions here for Top Bar dropdown menu',
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const SectionHeader('Advanced Settings Actions (Overflow)'),
                  _buildSectionDropArea(
                    context: context,
                    sectionName: 'advanced',
                    actions: mediaConfig.advancedSettingsActions,
                    cs: cs,
                    textTheme: textTheme,
                    emptyHint: 'Drag actions here for Advanced Settings sheet',
                  ),
                  const SizedBox(height: AppSpacing.xl),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionDropArea({
    required BuildContext context,
    required String sectionName,
    required List<MediaViewerAction> actions,
    required ColorScheme cs,
    required TextTheme textTheme,
    required String emptyHint,
  }) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          if (actions.isEmpty)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Text(
                emptyHint,
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                  color: cs.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
            )
          else
            ...actions.asMap().entries.map((entry) {
              final idx = entry.key;
              final action = entry.value;
              return _buildDraggableTile(
                context: context,
                action: action,
                sectionName: sectionName,
                index: idx,
                cs: cs,
                textTheme: textTheme,
              );
            }),
          DragTarget<_DragActionPayload>(
            onWillAcceptWithDetails: (_) => true,
            onAcceptWithDetails: (details) {
              _onActionDropped(
                payload: details.data,
                targetSection: sectionName,
                targetIndex: actions.length,
              );
            },
            builder: (ctx, candidates, _) {
              final isTargetingEnd = candidates.isNotEmpty;
              return Container(
                height: 38,
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  color: isTargetingEnd
                      ? cs.primary.withValues(alpha: 0.25)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                    color: isTargetingEnd
                        ? cs.primary
                        : cs.outlineVariant.withValues(alpha: 0.25),
                    style: BorderStyle.solid,
                  ),
                ),
                child: Center(
                  child: Text(
                    isTargetingEnd
                        ? 'Drop here at end'
                        : '+ Drag items here to add to this section',
                    style: TextStyle(
                      fontSize: 11,
                      color: isTargetingEnd ? cs.primary : cs.onSurfaceVariant,
                      fontWeight: isTargetingEnd
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDraggableTile({
    required BuildContext context,
    required MediaViewerAction action,
    required String sectionName,
    required int index,
    required ColorScheme cs,
    required TextTheme textTheme,
  }) {
    final payload = _DragActionPayload(
      action: action,
      fromSection: sectionName,
      fromIndex: index,
    );

    final tileContent = Material(
      color: cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: ListTile(
        dense: true,
        leading: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: cs.primaryContainer.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Icon(action.icon, size: 18, color: cs.primary),
        ),
        title: Text(
          action.getLocalizedLabel(context.l10n),
          style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (sectionName != 'advanced')
              IconButton(
                icon: Icon(Icons.close_rounded, size: 18, color: cs.error),
                tooltip: 'Move to Advanced Settings',
                onPressed: () {
                  _onActionDropped(
                    payload: payload,
                    targetSection: 'advanced',
                  );
                },
              ),
            Icon(Icons.drag_indicator_rounded,
                color: cs.onSurfaceVariant, size: 20),
          ],
        ),
      ),
    );

    return DragTarget<_DragActionPayload>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) {
        _onActionDropped(
          payload: details.data,
          targetSection: sectionName,
          targetIndex: index,
        );
      },
      builder: (context, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty;

        return AnimatedContainer(
          duration: AppMotion.short1,
          margin: const EdgeInsets.only(bottom: 4),
          decoration: BoxDecoration(
            border: isHovering
                ? Border(top: BorderSide(color: cs.primary, width: 3))
                : null,
          ),
         child: LongPressDraggable<_DragActionPayload>(
            data: payload,
            feedback: _buildDragFeedback(context, action, cs, textTheme),
            onDragUpdate: _handleDragUpdate,
            onDragEnd: (_) => _stopAutoScroll(),
            onDraggableCanceled: (_, __) => _stopAutoScroll(),
            childWhenDragging: Opacity(opacity: 0.35, child: tileContent),
            child: tileContent,
          ),
        );
      },
    );
  }

  Widget _buildDragFeedback(
    BuildContext context,
    MediaViewerAction action,
    ColorScheme cs,
    TextTheme textTheme,
  ) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: cs.primary, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(action.icon, color: cs.primary, size: 20),
            const SizedBox(width: AppSpacing.sm),
            Text(
              action.getLocalizedLabel(context.l10n),
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: cs.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}