import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/models/media_decoder_mode.dart';
import 'package:vaultexplorer/data/models/media_viewer_action.dart';
import 'package:vaultexplorer/data/models/media_viewer_toolbar_config.dart';
import 'package:vaultexplorer/data/models/resume_playback_mode.dart';
import 'package:vaultexplorer/data/models/scrub_preview_style.dart';
import 'package:vaultexplorer/data/models/thumbnail_generation_strategy.dart';
import 'package:vaultexplorer/data/models/video_aspect_ratio_mode.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';
import 'package:vaultexplorer/features/settings/file_manager_toolbar_settings_controller.dart';

class MediaViewerToolbarSettingsScreen extends ConsumerStatefulWidget {
  final int initialTab;

  const MediaViewerToolbarSettingsScreen({
    super.key,
    this.initialTab = 0,
  });

  @override
  ConsumerState<MediaViewerToolbarSettingsScreen> createState() =>
      _MediaViewerToolbarSettingsScreenState();
}

class _MediaViewerToolbarSettingsScreenState
    extends ConsumerState<MediaViewerToolbarSettingsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  bool _isSearching = false;
  String _searchQuery = '';
  String _activeSectionFilter = 'all';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 2),
    );
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _reorderSection(
    WidgetRef ref, {
    required String sectionName,
    required int oldIndex,
    required int newIndex,
  }) {
    final state = ref.read(fileManagerToolbarSettingsProvider(null));
    final mediaConfig = state.config.mediaViewerToolbarConfig;
    final controller = ref.read(
      fileManagerToolbarSettingsProvider(null).notifier,
    );

    final top = List<MediaViewerAction>.from(mediaConfig.topBarActions);
    final bottom = List<MediaViewerAction>.from(mediaConfig.bottomBarActions);
    final more = List<MediaViewerAction>.from(mediaConfig.moreMenuActions);
    final advanced = List<MediaViewerAction>.from(
      mediaConfig.advancedSettingsActions,
    );

    switch (sectionName) {
      case 'top':
        final item = top.removeAt(oldIndex);
        top.insert(newIndex, item);
        break;
      case 'bottom':
        final item = bottom.removeAt(oldIndex);
        bottom.insert(newIndex, item);
        break;
      case 'more':
        final item = more.removeAt(oldIndex);
        more.insert(newIndex, item);
        break;
      case 'advanced':
        final item = advanced.removeAt(oldIndex);
        advanced.insert(newIndex, item);
        break;
    }

    final updated = mediaConfig.copyWith(
      topBarActions: top,
      bottomBarActions: bottom,
      moreMenuActions: more,
      advancedSettingsActions: advanced,
    );
    unawaited(controller.updateMediaViewerConfig(updated));
    HapticFeedback.mediumImpact();
  }

  void _moveAction(
    WidgetRef ref, {
    required MediaViewerAction action,
    required String fromSection,
    required String toSection,
  }) {
    if (fromSection == toSection) return;

    final state = ref.read(fileManagerToolbarSettingsProvider(null));
    final mediaConfig = state.config.mediaViewerToolbarConfig;
    final controller = ref.read(
      fileManagerToolbarSettingsProvider(null).notifier,
    );

    final top = List<MediaViewerAction>.from(mediaConfig.topBarActions);
    final bottom = List<MediaViewerAction>.from(mediaConfig.bottomBarActions);
    final more = List<MediaViewerAction>.from(mediaConfig.moreMenuActions);
    final advanced = List<MediaViewerAction>.from(
      mediaConfig.advancedSettingsActions,
    );

    switch (fromSection) {
      case 'top':
        top.remove(action);
        break;
      case 'bottom':
        bottom.remove(action);
        break;
      case 'more':
        more.remove(action);
        break;
      case 'advanced':
        advanced.remove(action);
        break;
    }

    switch (toSection) {
      case 'top':
        top.add(action);
        break;
      case 'bottom':
        bottom.add(action);
        break;
      case 'more':
        more.add(action);
        break;
      case 'advanced':
        advanced.add(action);
        break;
    }

    final updated = mediaConfig.copyWith(
      topBarActions: top,
      bottomBarActions: bottom,
      moreMenuActions: more,
      advancedSettingsActions: advanced,
    );
    unawaited(controller.updateMediaViewerConfig(updated));
    HapticFeedback.mediumImpact();
  }

  void _startSearch() {
    setState(() {
      _isSearching = true;
    });
  }

  void _stopSearch() {
    setState(() {
      _isSearching = false;
      _searchQuery = '';
      _searchController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(fileManagerToolbarSettingsProvider(null));
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final mediaConfig = state.config.mediaViewerToolbarConfig;
    final controller = ref.read(
      fileManagerToolbarSettingsProvider(null).notifier,
    );
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        leading: _isSearching
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                onPressed: _stopSearch,
              )
            : null,
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: textTheme.titleMedium,
                decoration: InputDecoration(
                  hintText: 'Search video settings & controls…',
                  hintStyle: textTheme.titleMedium?.copyWith(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                  border: InputBorder.none,
                ),
                onChanged: (val) => setState(() => _searchQuery = val.trim()),
              )
            : Text(
                l10n.mediaPlayerControlsTitle,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
        actions: [
          if (_isSearching) ...[
            if (_searchQuery.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.clear_rounded),
                onPressed: () {
                  setState(() {
                    _searchQuery = '';
                    _searchController.clear();
                  });
                },
              ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.search_rounded),
              tooltip: 'Search settings',
              onPressed: _startSearch,
            ),
            IconButton(
              icon: const Icon(Icons.restart_alt_rounded),
              tooltip: l10n.resetToDefaultsTooltip,
              onPressed: () {
                unawaited(controller.resetMediaViewerConfigToDefaults());
                showAppSnackBar(
                  context,
                  message: l10n.mediaControlsResetSuccess,
                  tone: AppBannerTone.success,
                );
              },
            ),
          ],
          const SizedBox(width: AppSpacing.xs),
        ],
        bottom: _isSearching
            ? null
            : TabBar(
                controller: _tabController,
                indicatorWeight: 3,
                tabs: [
                  Tab(
                    icon: const Icon(Icons.touch_app_rounded, size: 20),
                    text: l10n.playbackSettingsTitle,
                  ),
                  Tab(
                    icon: const Icon(Icons.dashboard_customize_rounded, size: 20),
                    text: l10n.toolbarLayoutSectionHeader,
                  ),
                  Tab(
                    icon: const Icon(Icons.tune_rounded, size: 20),
                    text: l10n.advancedOptionsTitle,
                  ),
                ],
              ),
      ),
      body: state.loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2.5))
          : SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: _isSearching && _searchQuery.isNotEmpty
                      ? _buildSearchResults(
                          context,
                          mediaConfig,
                          controller,
                          state.config.showMediaCarousel,
                          cs,
                          textTheme,
                        )
                      : TabBarView(
                          controller: _tabController,
                          children: [
                            _buildPlaybackTab(
                              context,
                              mediaConfig,
                              controller,
                              state.config.showMediaCarousel,
                              cs,
                              textTheme,
                            ),
                            _buildToolbarsTab(
                              context,
                              mediaConfig,
                              cs,
                              textTheme,
                            ),
                            _buildAudioAndEngineTab(
                              context,
                              mediaConfig,
                              controller,
                              cs,
                              textTheme,
                            ),
                          ],
                        ),
                ),
              ),
            ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // TAB 1: PLAYBACK & GESTURES
  // ─────────────────────────────────────────────────────────────────────────────

  Widget _buildPlaybackTab(
    BuildContext context,
    MediaViewerToolbarConfig mediaConfig,
    FileManagerToolbarSettings controller,
    bool showMediaCarousel,
    ColorScheme cs,
    TextTheme textTheme,
  ) {
    final l10n = context.l10n;

    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      children: [
        // 1. Playback & Display
        SectionHeader(l10n.playbackAndDisplayHeader),
        SectionCard(
          children: [
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              value: mediaConfig.showProgressBar,
              onChanged: controller.setMediaViewerShowProgressBar,
              title: Text(
                l10n.showProgressBarTitle,
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                l10n.showProgressBarSubtitle,
                style: textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              secondary: Icon(
                Icons.linear_scale_rounded,
                color: cs.primary,
              ),
            ),
            OptionPickerTile<ScrubPreviewStyle>(
              label: l10n.scrubPreviewStyleTitle,
              value: mediaConfig.scrubPreviewStyle,
              prefixIcon: mediaConfig.scrubPreviewStyle.icon,
              enabled: mediaConfig.showProgressBar,
              options: ScrubPreviewStyle.values.map((style) {
                return SelectOption(
                  value: style,
                  label: style.getLocalizedLabel(l10n),
                  subtitle: style.getLocalizedDescription(l10n),
                );
              }).toList(),
              onChanged: controller.setMediaViewerScrubPreviewStyle,
            ),
            OptionPickerTile<ResumePlaybackMode>(
              label: l10n.resumePlaybackTitle,
              value: mediaConfig.resumePlaybackMode,
              prefixIcon: Icons.history_rounded,
              options: ResumePlaybackMode.values.map((mode) {
                return SelectOption(
                  value: mode,
                  label: switch (mode) {
                    ResumePlaybackMode.askEveryTime =>
                      l10n.resumePlaybackAskEveryTime,
                    ResumePlaybackMode.never => l10n.resumePlaybackNever,
                    ResumePlaybackMode.always => l10n.resumePlaybackAlways,
                  },
                );
              }).toList(),
              onChanged: controller.setMediaViewerResumePlaybackMode,
            ),
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              value: mediaConfig.showCenterTransportForImages,
              onChanged: (val) {
                unawaited(
                  controller.updateMediaViewerConfig(
                    mediaConfig.copyWith(showCenterTransportForImages: val),
                  ),
                );
              },
              title: Text(
                l10n.showTransportControlsOnPhotosTitle,
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                l10n.showTransportControlsOnPhotosSubtitle,
                style: textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              secondary: Icon(
                Icons.slideshow_rounded,
                color: cs.primary,
              ),
            ),
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              value: mediaConfig.showStatusBadge,
              onChanged: controller.setMediaViewerShowStatusBadge,
              title: Text(
                l10n.statusBadgeTitle,
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                l10n.statusBadgeSubtitle,
                style: textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              secondary: Icon(
                Icons.badge_outlined,
                color: cs.primary,
              ),
            ),
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              value: showMediaCarousel,
              onChanged: controller.setShowMediaCarousel,
              title: Text(
                l10n.showPlaylistCarouselLabel,
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                l10n.showPlaylistCarouselDesc,
                style: textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              secondary: Icon(
                Icons.view_carousel_rounded,
                color: cs.primary,
              ),
            ),
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              value: mediaConfig.loopPlaylist,
              onChanged: controller.setMediaViewerLoopPlaylist,
              title: Text(
                l10n.loopPlaylistTitle,
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                l10n.loopPlaylistSubtitle,
                style: textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              secondary: Icon(
                Icons.repeat_rounded,
                color: cs.primary,
              ),
            ),
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              value: mediaConfig.tapEdgesToNavigate,
              onChanged: controller.setMediaViewerTapEdgesToNavigate,
              title: Text(
                l10n.tapEdgesToNavigateTitle,
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                l10n.tapEdgesToNavigateSubtitle,
                style: textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              secondary: Icon(
                Icons.swap_horiz_rounded,
                color: cs.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // 2. Video Gestures & Seeking
        SectionHeader(l10n.videoGesturesHeader),
        SectionCard(
          children: [
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              value: mediaConfig.swipeToSeekEnabled,
              onChanged: controller.setMediaViewerSwipeToSeekEnabled,
              title: Text(
                l10n.swipeToSeekTitle,
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                l10n.swipeToSeekSubtitle,
                style: textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              secondary: Icon(Icons.swipe_rounded, color: cs.primary),
            ),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              leading: Icon(
                Icons.fast_forward_rounded,
                color: cs.primary,
              ),
              title: Text(
                l10n.seekGestureSensitivityTitle,
                style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              subtitle: _SettingsSlider(
                value: mediaConfig.seekSensitivity,
                min: 0.25,
                max: 2.0,
                divisions: 7,
                labelBuilder: (v) =>
                    '${v.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '')}x',
                onChangeEnd: (v) => unawaited(controller.setMediaViewerSeekSensitivity(v)),
              ),
            ),
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              value: mediaConfig.edgeSwipeBrightnessEnabled,
              onChanged: controller.setMediaViewerEdgeSwipeBrightnessEnabled,
              title: Text(
                l10n.edgeSwipeBrightnessTitle,
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                l10n.edgeSwipeBrightnessSubtitle,
                style: textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              secondary: Icon(
                Icons.wb_sunny_rounded,
                color: cs.primary,
              ),
            ),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              leading: Icon(
                Icons.wb_sunny_outlined,
                color: cs.primary,
              ),
              title: Text(
                l10n.brightnessGestureSensitivityTitle,
                style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              subtitle: _SettingsSlider(
                value: mediaConfig.brightnessGestureSensitivity,
                min: 0.25,
                max: 2.0,
                divisions: 7,
                labelBuilder: (v) =>
                    '${v.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '')}x',
                onChangeEnd: (v) => unawaited(
                  controller.setMediaViewerBrightnessGestureSensitivity(v),
                ),
              ),
            ),
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              value: mediaConfig.edgeSwipeVolumeEnabled,
              onChanged: controller.setMediaViewerEdgeSwipeVolumeEnabled,
              title: Text(
                l10n.edgeSwipeVolumeTitle,
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                l10n.edgeSwipeVolumeSubtitle,
                style: textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              secondary: Icon(
                Icons.volume_up_rounded,
                color: cs.primary,
              ),
            ),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              leading: Icon(
                Icons.volume_down_rounded,
                color: cs.primary,
              ),
              title: Text(
                l10n.volumeGestureSensitivityTitle,
                style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              subtitle: _SettingsSlider(
                value: mediaConfig.volumeGestureSensitivity,
                min: 0.25,
                max: 2.0,
                divisions: 7,
                labelBuilder: (v) =>
                    '${v.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '')}x',
                onChangeEnd: (v) => unawaited(
                  controller.setMediaViewerVolumeGestureSensitivity(v),
                ),
              ),
            ),
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              value: mediaConfig.edgeSwipeHudEnabled,
              onChanged: controller.setMediaViewerEdgeSwipeHudEnabled,
              title: Text(
                l10n.edgeSwipeHudTitle,
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                l10n.edgeSwipeHudSubtitle,
                style: textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              secondary: Icon(
                Icons.picture_in_picture_alt_rounded,
                color: cs.primary,
              ),
            ),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              leading: Icon(
                Icons.swipe_vertical_rounded,
                color: cs.primary,
              ),
              title: Text(
                l10n.edgeSwipeWidthTitle,
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: _SettingsSlider(
                value: mediaConfig.edgeSwipeWidthFraction,
                min: MediaViewerConstants.edgeSwipeWidthMin,
                max: MediaViewerConstants.edgeSwipeWidthMax,
                divisions: 10,
                labelBuilder: (v) => '${(v * 100).round()}%',
                onChangeEnd: (v) => unawaited(
                  controller.setMediaViewerEdgeSwipeWidthFraction(v),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // 3. Zoom & Video Aspect Ratio
        SectionHeader(l10n.aspectRatioModeLabel),
        SectionCard(
          children: [
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              value: mediaConfig.pinchZoomOutEnabled,
              onChanged: controller.setMediaViewerPinchZoomOutEnabled,
              title: Text(
                l10n.pinchZoomOutTitle,
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                l10n.pinchZoomOutSubtitle,
                style: textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              secondary: Icon(
                Icons.zoom_out_map_rounded,
                color: cs.primary,
              ),
            ),
            if (mediaConfig.pinchZoomOutEnabled)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                leading: Icon(
                  Icons.photo_size_select_small_rounded,
                  color: cs.primary,
                ),
                title: Text(
                  l10n.minZoomTitle,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: _SettingsSlider(
                  value: mediaConfig.minVideoZoomScale,
                  min: MediaViewerConstants.minVideoZoomFloor,
                  max: 1.0,
                  divisions: 18,
                  labelBuilder: (v) => '${v.toStringAsFixed(2)}x',
                  onChangeEnd: (v) => unawaited(
                    controller.setMediaViewerMinVideoZoomScale(v),
                  ),
                ),
              ),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              leading: Icon(
                mediaConfig.holdToSpeedMultiplier < 1.0
                    ? Icons.slow_motion_video_rounded
                    : Icons.speed_rounded,
                color: cs.primary,
              ),
              title: Text(
                l10n.holdSpeedMultiplierTitle,
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.holdSpeedMultiplierSubtitle,
                    style: textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  _SettingsSlider(
                    value: mediaConfig.holdToSpeedMultiplier,
                    min: 0.25,
                    max: 4.0,
                    divisions: 15,
                    labelBuilder: (v) =>
                        '${v.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '')}x',
                    onChangeEnd: (v) => unawaited(
                      controller.setMediaViewerHoldToSpeedMultiplier(v),
                    ),
                  ),
                ],
              ),
            ),
            OptionPickerTile<VideoAspectRatioMode>(
              label: l10n.defaultAspectRatioTitle,
              value: mediaConfig.defaultAspectRatioMode,
              prefixIcon: mediaConfig.defaultAspectRatioMode.icon,
              options: VideoAspectRatioMode.values.map((mode) {
                return SelectOption(
                  value: mode,
                  label: mode.getLocalizedLabel(l10n),
                );
              }).toList(),
              onChanged: controller.setMediaViewerDefaultAspectRatioMode,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // TAB 2: CONTROLS & TOOLBARS
  // ─────────────────────────────────────────────────────────────────────────────

  Widget _buildToolbarsTab(
    BuildContext context,
    MediaViewerToolbarConfig mediaConfig,
    ColorScheme cs,
    TextTheme textTheme,
  ) {
    final l10n = context.l10n;

    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      children: [
        // 1. Visual Player Layout Preview Mockup
        _buildPlayerMockup(mediaConfig, cs, textTheme),
        const SizedBox(height: 12),

        // 2. Section Selector Filter Chips
        _buildSectionFilterChips(mediaConfig, cs, textTheme),
        const SizedBox(height: 12),

        // 3. Section Content based on filter
        if (_activeSectionFilter == 'all') ...[
          // Top Bar Actions
          _buildSectionHeaderWithBadge(
            title: l10n.topBarActionsHeader,
            count: mediaConfig.topBarActions.length,
            cs: cs,
          ),
          _buildReorderableSection(
            context: context,
            ref: ref,
            sectionName: 'top',
            actions: mediaConfig.topBarActions,
            emptyHint: l10n.topBarActionsEmptyHint,
            cs: cs,
            textTheme: textTheme,
          ),
          const SizedBox(height: 16),

          // Bottom Dock Actions
          _buildSectionHeaderWithBadge(
            title: l10n.bottomDockActionsHeader,
            count: mediaConfig.bottomBarActions.length,
            cs: cs,
          ),
          _buildReorderableSection(
            context: context,
            ref: ref,
            sectionName: 'bottom',
            actions: mediaConfig.bottomBarActions,
            emptyHint: l10n.bottomDockActionsEmptyHint,
            cs: cs,
            textTheme: textTheme,
          ),
          const SizedBox(height: 16),

          // More Menu Actions
          _buildSectionHeaderWithBadge(
            title: l10n.moreMenuActionsHeader,
            count: mediaConfig.moreMenuActions.length,
            cs: cs,
          ),
          _buildReorderableSection(
            context: context,
            ref: ref,
            sectionName: 'more',
            actions: mediaConfig.moreMenuActions,
            emptyHint: l10n.moreMenuActionsEmptyHint,
            cs: cs,
            textTheme: textTheme,
          ),
          const SizedBox(height: 16),

          // Advanced Settings Actions
          _buildSectionHeaderWithBadge(
            title: l10n.advancedSettingsActionsHeader,
            count: mediaConfig.advancedSettingsActions.length,
            cs: cs,
          ),
          _buildReorderableSection(
            context: context,
            ref: ref,
            sectionName: 'advanced',
            actions: mediaConfig.advancedSettingsActions,
            emptyHint: l10n.advancedSettingsActionsEmptyHint,
            cs: cs,
            textTheme: textTheme,
          ),
        ] else ...[
          // Single focused section view
          _buildFocusedSectionView(
            context: context,
            sectionName: _activeSectionFilter,
            mediaConfig: mediaConfig,
            cs: cs,
            textTheme: textTheme,
          ),
        ],

        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }

  Widget _buildSectionHeaderWithBadge({
    required String title,
    required int count,
    required ColorScheme cs,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: cs.primary,
                letterSpacing: -0.1,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: cs.onPrimaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerMockup(
    MediaViewerToolbarConfig mediaConfig,
    ColorScheme cs,
    TextTheme textTheme,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Mock Top Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.arrow_back, size: 16, color: cs.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'video_01.mp4',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ...mediaConfig.topBarActions.take(5).map(
                  (a) => Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(a.icon, size: 16, color: cs.primary),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.more_vert, size: 16, color: cs.onSurfaceVariant),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Mock Video Display Canvas
          Container(
            height: 76,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  cs.surfaceContainerHighest.withValues(alpha: 0.5),
                  cs.surfaceContainerHigh.withValues(alpha: 0.8),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.play_arrow_rounded,
                  size: 28,
                  color: cs.primary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Mock Seekbar & Bottom Dock
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                if (mediaConfig.showProgressBar) ...[
                  Row(
                    children: [
                      Text(
                        '01:14',
                        style: textTheme.labelSmall?.copyWith(
                          fontSize: 10,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: 0.35,
                            minHeight: 3,
                            backgroundColor:
                                cs.outlineVariant.withValues(alpha: 0.4),
                            color: cs.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '03:45',
                        style: textTheme.labelSmall?.copyWith(
                          fontSize: 10,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: mediaConfig.bottomBarActions
                      .map(
                        (a) => Icon(a.icon, size: 18, color: cs.primary),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionFilterChips(
    MediaViewerToolbarConfig mediaConfig,
    ColorScheme cs,
    TextTheme textTheme,
  ) {
    final l10n = context.l10n;

    Widget chip({
      required String key,
      required String label,
      required IconData icon,
      required int count,
    }) {
      final selected = _activeSectionFilter == key;
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: FilterChip(
          selected: selected,
          avatar: Icon(
            icon,
            size: 16,
            color: selected ? cs.onPrimary : cs.primary,
          ),
          label: Text(
            count >= 0 ? '$label ($count)' : label,
            style: TextStyle(
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              fontSize: 12,
              color: selected ? cs.onPrimary : cs.onSurface,
            ),
          ),
          selectedColor: cs.primary,
          showCheckmark: false,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          onSelected: (_) {
            setState(() {
              _activeSectionFilter = key;
            });
            HapticFeedback.lightImpact();
          },
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          chip(
            key: 'all',
            label: 'All Sections',
            icon: Icons.layers_outlined,
            count: mediaConfig.topBarActions.length +
                mediaConfig.bottomBarActions.length +
                mediaConfig.moreMenuActions.length +
                mediaConfig.advancedSettingsActions.length,
          ),
          chip(
            key: 'top',
            label: l10n.topBarActionsHeader,
            icon: Icons.vertical_align_top_rounded,
            count: mediaConfig.topBarActions.length,
          ),
          chip(
            key: 'bottom',
            label: l10n.bottomDockActionsHeader,
            icon: Icons.vertical_align_bottom_rounded,
            count: mediaConfig.bottomBarActions.length,
          ),
          chip(
            key: 'more',
            label: l10n.moreMenuActionsHeader,
            icon: Icons.more_horiz_rounded,
            count: mediaConfig.moreMenuActions.length,
          ),
          chip(
            key: 'advanced',
            label: l10n.advancedSettingsActionsHeader,
            icon: Icons.tune_rounded,
            count: mediaConfig.advancedSettingsActions.length,
          ),
        ],
      ),
    );
  }

  Widget _buildFocusedSectionView({
    required BuildContext context,
    required String sectionName,
    required MediaViewerToolbarConfig mediaConfig,
    required ColorScheme cs,
    required TextTheme textTheme,
  }) {
    final l10n = context.l10n;

    final (String title, List<MediaViewerAction> actions, String emptyHint) =
        switch (sectionName) {
      'top' => (
          l10n.topBarActionsHeader,
          mediaConfig.topBarActions,
          l10n.topBarActionsEmptyHint,
        ),
      'bottom' => (
          l10n.bottomDockActionsHeader,
          mediaConfig.bottomBarActions,
          l10n.bottomDockActionsEmptyHint,
        ),
      'more' => (
          l10n.moreMenuActionsHeader,
          mediaConfig.moreMenuActions,
          l10n.moreMenuActionsEmptyHint,
        ),
      _ => (
          l10n.advancedSettingsActionsHeader,
          mediaConfig.advancedSettingsActions,
          l10n.advancedSettingsActionsEmptyHint,
        ),
    };

    final allActions = MediaViewerAction.values;
    final availableToAdd =
        allActions.where((a) => !actions.contains(a)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionHeaderWithBadge(
          title: title,
          count: actions.length,
          cs: cs,
        ),
        _buildReorderableSection(
          context: context,
          ref: ref,
          sectionName: sectionName,
          actions: actions,
          emptyHint: emptyHint,
          cs: cs,
          textTheme: textTheme,
        ),
        const SizedBox(height: 24),
        if (availableToAdd.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                Icon(Icons.add_circle_outline_rounded,
                    size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Add to $title',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${availableToAdd.length} available',
                  style: textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          SectionCard(
            children: availableToAdd.map((action) {
              final currentSec = _findCurrentSection(action, mediaConfig);
              return ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(action.icon, size: 20, color: cs.primary),
                ),
                title: Text(
                  action.getLocalizedLabel(l10n),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  'Currently in: ${_sectionDisplayName(currentSec, l10n)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                trailing: IconButton.filledTonal(
                  icon: const Icon(Icons.add_rounded, size: 20),
                  tooltip: 'Add',
                  onPressed: () {
                    _moveAction(
                      ref,
                      action: action,
                      fromSection: currentSec,
                      toSection: sectionName,
                    );
                  },
                ),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }

  String _findCurrentSection(
      MediaViewerAction action, MediaViewerToolbarConfig config) {
    if (config.topBarActions.contains(action)) return 'top';
    if (config.bottomBarActions.contains(action)) return 'bottom';
    if (config.moreMenuActions.contains(action)) return 'more';
    return 'advanced';
  }

  String _sectionDisplayName(String section, dynamic l10n) {
    return switch (section) {
      'top' => l10n.topBarActionsHeader,
      'bottom' => l10n.bottomDockActionsHeader,
      'more' => l10n.moreMenuActionsHeader,
      _ => l10n.advancedSettingsActionsHeader,
    };
  }

  Widget _buildReorderableSection({
    required BuildContext context,
    required WidgetRef ref,
    required String sectionName,
    required List<MediaViewerAction> actions,
    required String emptyHint,
    required ColorScheme cs,
    required TextTheme textTheme,
  }) {
    final l10n = context.l10n;

    if (actions.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.2)),
        ),
        child: Center(
          child: Text(
            emptyHint,
            style: textTheme.bodySmall?.copyWith(
              fontStyle: FontStyle.italic,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: actions.length,
      onReorderItem: (oldIndex, newIndex) {
        _reorderSection(
          ref,
          sectionName: sectionName,
          oldIndex: oldIndex,
          newIndex: newIndex,
        );
      },
      itemBuilder: (context, i) {
        final action = actions[i];

        return Padding(
          key: ValueKey('${sectionName}_${action.name}'),
          padding: const EdgeInsets.only(bottom: 2),
          child: Material(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(i == 0 ? 20 : 4),
              bottom: Radius.circular(i == actions.length - 1 ? 20 : 4),
            ),
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 2,
              ),
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(action.icon, size: 20, color: cs.primary),
              ),
              title: Text(
                action.getLocalizedLabel(l10n),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildMoveMenu(
                    context: context,
                    ref: ref,
                    action: action,
                    currentSection: sectionName,
                    cs: cs,
                    l10n: l10n,
                  ),
                  if (sectionName != 'advanced') ...[
                    const SizedBox(width: 2),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      icon: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: cs.error,
                      ),
                      tooltip: l10n.moveToAdvancedSettingsTooltip,
                      onPressed: () {
                        _moveAction(
                          ref,
                          action: action,
                          fromSection: sectionName,
                          toSection: 'advanced',
                        );
                      },
                    ),
                  ],
                  const SizedBox(width: 4),
                  ReorderableDragStartListener(
                    index: i,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest.withValues(
                          alpha: 0.5,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.drag_handle_rounded,
                        color: cs.onSurfaceVariant,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMoveMenu({
    required BuildContext context,
    required WidgetRef ref,
    required MediaViewerAction action,
    required String currentSection,
    required ColorScheme cs,
    required dynamic l10n,
  }) {
    final isAdvanced = currentSection == 'advanced';

    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 180, maxWidth: 320),
      icon: Icon(
        isAdvanced
            ? Icons.add_circle_outline_rounded
            : Icons.drive_file_move_outlined,
        size: 19,
        color: isAdvanced ? cs.primary : cs.onSurfaceVariant,
      ),
      tooltip: isAdvanced ? 'Add to toolbar' : 'Move to section',
      onSelected: (targetSection) {
        _moveAction(
          ref,
          action: action,
          fromSection: currentSection,
          toSection: targetSection,
        );
      },
      itemBuilder: (context) => [
        if (currentSection != 'top')
          PopupMenuItem(
            value: 'top',
            child: Row(
              children: [
                Icon(
                  Icons.vertical_align_top_rounded,
                  size: 18,
                  color: cs.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n.topBarActionsHeader,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        if (currentSection != 'bottom')
          PopupMenuItem(
            value: 'bottom',
            child: Row(
              children: [
                Icon(
                  Icons.vertical_align_bottom_rounded,
                  size: 18,
                  color: cs.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n.bottomDockActionsHeader,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        if (currentSection != 'more')
          PopupMenuItem(
            value: 'more',
            child: Row(
              children: [
                Icon(Icons.more_horiz_rounded, size: 18, color: cs.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n.moreMenuActionsHeader,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        if (currentSection != 'advanced')
          PopupMenuItem(
            value: 'advanced',
            child: Row(
              children: [
                Icon(Icons.tune_rounded, size: 18, color: cs.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n.advancedSettingsActionsHeader,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // TAB 3: AUDIO & ENGINE
  // ─────────────────────────────────────────────────────────────────────────────

  Widget _buildAudioAndEngineTab(
    BuildContext context,
    MediaViewerToolbarConfig mediaConfig,
    FileManagerToolbarSettings controller,
    ColorScheme cs,
    TextTheme textTheme,
  ) {
    final l10n = context.l10n;

    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      children: [
        // 1. Volume Boost
        SectionHeader(l10n.volumeBoostHeader),
        SectionCard(
          children: [
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              value: mediaConfig.volumeBoostEnabled,
              onChanged: controller.setMediaViewerVolumeBoostEnabled,
              title: Text(
                l10n.volumeBoostTitle,
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                l10n.volumeBoostSubtitle,
                style: textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              secondary: Icon(
                Icons.volume_up_rounded,
                color: cs.primary,
              ),
            ),
            if (mediaConfig.volumeBoostEnabled)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                leading: Icon(
                  Icons.graphic_eq_rounded,
                  color: cs.primary,
                ),
                title: Text(
                  l10n.volumeBoostGainTitle,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: _SettingsSlider(
                  value: mediaConfig.volumeBoostGainMb.toDouble(),
                  min: 0,
                  max: 2000,
                  divisions: 20,
                  labelBuilder: (v) => '+${(v / 100).round()} dB',
                  onChangeEnd: (v) => unawaited(
                    controller.setMediaViewerVolumeBoostGain(v.round()),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),

        // 2. Hardware Decoder Selection
        SectionHeader(l10n.decoderSelectionHeader),
        SectionCard(
          children: [
            OptionPickerTile<MediaDecoderMode>(
              label: l10n.videoDecoderTitle,
              value: mediaConfig.videoDecoderMode,
              prefixIcon: Icons.memory_rounded,
              options: [
                SelectOption(
                  value: MediaDecoderMode.auto,
                  label: l10n.decoderAutoOption,
                ),
                SelectOption(
                  value: MediaDecoderMode.hardware,
                  label: l10n.decoderHardwareOption,
                ),
                SelectOption(
                  value: MediaDecoderMode.software,
                  label: l10n.decoderSoftwareOption,
                ),
                SelectOption(
                  value: MediaDecoderMode.ffmpeg,
                  label: l10n.decoderFfmpegOption,
                ),
              ],
              onChanged: controller.setMediaViewerVideoDecoderMode,
            ),
            OptionPickerTile<MediaDecoderMode>(
              label: l10n.audioDecoderTitle,
              value: mediaConfig.audioDecoderMode,
              prefixIcon: Icons.audiotrack_rounded,
              options: [
                SelectOption(
                  value: MediaDecoderMode.auto,
                  label: l10n.decoderAutoOption,
                ),
                SelectOption(
                  value: MediaDecoderMode.hardware,
                  label: l10n.decoderHardwareOption,
                ),
                SelectOption(
                  value: MediaDecoderMode.software,
                  label: l10n.decoderSoftwareOption,
                ),
                SelectOption(
                  value: MediaDecoderMode.ffmpeg,
                  label: l10n.decoderFfmpegOption,
                ),
              ],
              onChanged: controller.setMediaViewerAudioDecoderMode,
            ),
          ],
        ),
        const SizedBox(height: 16),

        // 3. Thumbnail Generation
        SectionHeader(l10n.thumbnailSettingsHeader),
        SectionCard(
          children: [
            OptionPickerTile<ThumbnailGenerationStrategy>(
              label: l10n.thumbnailGenerationStrategyTitle,
              value: mediaConfig.thumbnailGenerationStrategy,
              prefixIcon: Icons.video_library_outlined,
              options: [
                SelectOption(
                  value: ThumbnailGenerationStrategy.firstFrame,
                  label: l10n.thumbnailFirstFrameOption,
                ),
                SelectOption(
                  value: ThumbnailGenerationStrategy.frameAtPercentage,
                  label: l10n.thumbnailPercentageFrameOption,
                ),
                SelectOption(
                  value: ThumbnailGenerationStrategy.hybrid,
                  label: l10n.thumbnailHybridOption,
                ),
              ],
              onChanged: controller.setThumbnailGenerationStrategy,
            ),
            if (mediaConfig.thumbnailGenerationStrategy !=
                ThumbnailGenerationStrategy.firstFrame)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                leading: Icon(
                  Icons.timelapse_rounded,
                  color: cs.primary,
                ),
                title: Text(
                  l10n.thumbnailFramePositionTitle,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: _SettingsSlider(
                  value: mediaConfig.thumbnailFramePosition,
                  min: 0.05,
                  max: 0.90,
                  divisions: 17,
                  labelBuilder: (v) => '${(v * 100).round()}%',
                  onChangeEnd: (v) => unawaited(
                    controller.setThumbnailFramePosition(v),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // SEARCH RESULTS VIEW
  // ─────────────────────────────────────────────────────────────────────────────

  Widget _buildSearchResults(
    BuildContext context,
    MediaViewerToolbarConfig mediaConfig,
    FileManagerToolbarSettings controller,
    bool showMediaCarousel,
    ColorScheme cs,
    TextTheme textTheme,
  ) {
    final l10n = context.l10n;
    final query = _searchQuery.toLowerCase();

    // Check actions match
    final matchingActions = MediaViewerAction.values.where((a) {
      return a.getLocalizedLabel(l10n).toLowerCase().contains(query) ||
          a.name.toLowerCase().contains(query);
    }).toList();

    // Matching general settings items
    final matchingSettings = <Widget>[];

    if ('progress bar scrubber timeline'.contains(query) ||
        l10n.showProgressBarTitle.toLowerCase().contains(query)) {
      matchingSettings.add(
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          value: mediaConfig.showProgressBar,
          onChanged: controller.setMediaViewerShowProgressBar,
          title: Text(l10n.showProgressBarTitle),
          subtitle: Text(l10n.showProgressBarSubtitle),
          secondary: Icon(Icons.linear_scale_rounded, color: cs.primary),
        ),
      );
    }

    if ('scrub preview thumbnail'.contains(query) ||
        l10n.scrubPreviewStyleTitle.toLowerCase().contains(query)) {
      matchingSettings.add(
        OptionPickerTile<ScrubPreviewStyle>(
          label: l10n.scrubPreviewStyleTitle,
          value: mediaConfig.scrubPreviewStyle,
          prefixIcon: mediaConfig.scrubPreviewStyle.icon,
          enabled: mediaConfig.showProgressBar,
          options: ScrubPreviewStyle.values.map((style) {
            return SelectOption(
              value: style,
              label: style.getLocalizedLabel(l10n),
              subtitle: style.getLocalizedDescription(l10n),
            );
          }).toList(),
          onChanged: controller.setMediaViewerScrubPreviewStyle,
        ),
      );
    }

    if ('resume playback history remember position'.contains(query) ||
        l10n.resumePlaybackTitle.toLowerCase().contains(query)) {
      matchingSettings.add(
        OptionPickerTile<ResumePlaybackMode>(
          label: l10n.resumePlaybackTitle,
          value: mediaConfig.resumePlaybackMode,
          prefixIcon: Icons.history_rounded,
          options: ResumePlaybackMode.values.map((mode) {
            return SelectOption(
              value: mode,
              label: switch (mode) {
                ResumePlaybackMode.askEveryTime =>
                  l10n.resumePlaybackAskEveryTime,
                ResumePlaybackMode.never => l10n.resumePlaybackNever,
                ResumePlaybackMode.always => l10n.resumePlaybackAlways,
              },
            );
          }).toList(),
          onChanged: controller.setMediaViewerResumePlaybackMode,
        ),
      );
    }

    if ('swipe seek gesture horizontal'.contains(query) ||
        l10n.swipeToSeekTitle.toLowerCase().contains(query)) {
      matchingSettings.add(
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          value: mediaConfig.swipeToSeekEnabled,
          onChanged: controller.setMediaViewerSwipeToSeekEnabled,
          title: Text(l10n.swipeToSeekTitle),
          subtitle: Text(l10n.swipeToSeekSubtitle),
          secondary: Icon(Icons.swipe_rounded, color: cs.primary),
        ),
      );
      matchingSettings.add(
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          leading: Icon(Icons.fast_forward_rounded, color: cs.primary),
          title: Text(l10n.seekGestureSensitivityTitle),
          subtitle: _SettingsSlider(
            value: mediaConfig.seekSensitivity,
            min: 0.25,
            max: 2.0,
            divisions: 7,
            labelBuilder: (v) =>
                '${v.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '')}x',
            onChangeEnd: (v) => unawaited(controller.setMediaViewerSeekSensitivity(v)),
          ),
        ),
      );
    }

    if ('brightness edge swipe light screen'.contains(query) ||
        l10n.edgeSwipeBrightnessTitle.toLowerCase().contains(query)) {
      matchingSettings.add(
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          value: mediaConfig.edgeSwipeBrightnessEnabled,
          onChanged: controller.setMediaViewerEdgeSwipeBrightnessEnabled,
          title: Text(l10n.edgeSwipeBrightnessTitle),
          subtitle: Text(l10n.edgeSwipeBrightnessSubtitle),
          secondary: Icon(Icons.wb_sunny_rounded, color: cs.primary),
        ),
      );
    }

    if ('volume edge swipe sound audio'.contains(query) ||
        l10n.edgeSwipeVolumeTitle.toLowerCase().contains(query)) {
      matchingSettings.add(
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          value: mediaConfig.edgeSwipeVolumeEnabled,
          onChanged: controller.setMediaViewerEdgeSwipeVolumeEnabled,
          title: Text(l10n.edgeSwipeVolumeTitle),
          subtitle: Text(l10n.edgeSwipeVolumeSubtitle),
          secondary: Icon(Icons.volume_up_rounded, color: cs.primary),
        ),
      );
    }

    if ('volume boost gain db amplifier sound quiet'.contains(query) ||
        l10n.volumeBoostTitle.toLowerCase().contains(query)) {
      matchingSettings.add(
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          value: mediaConfig.volumeBoostEnabled,
          onChanged: controller.setMediaViewerVolumeBoostEnabled,
          title: Text(l10n.volumeBoostTitle),
          subtitle: Text(l10n.volumeBoostSubtitle),
          secondary: Icon(Icons.volume_up_rounded, color: cs.primary),
        ),
      );
      if (mediaConfig.volumeBoostEnabled) {
        matchingSettings.add(
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            leading: Icon(Icons.graphic_eq_rounded, color: cs.primary),
            title: Text(l10n.volumeBoostGainTitle),
            subtitle: _SettingsSlider(
              value: mediaConfig.volumeBoostGainMb.toDouble(),
              min: 0,
              max: 2000,
              divisions: 20,
              labelBuilder: (v) => '+${(v / 100).round()} dB',
              onChangeEnd: (v) => unawaited(
                controller.setMediaViewerVolumeBoostGain(v.round()),
              ),
            ),
          ),
        );
      }
    }

    if ('decoder hardware software ffmpeg video audio engine'
            .contains(query) ||
        l10n.videoDecoderTitle.toLowerCase().contains(query)) {
      matchingSettings.add(
        OptionPickerTile<MediaDecoderMode>(
          label: l10n.videoDecoderTitle,
          value: mediaConfig.videoDecoderMode,
          prefixIcon: Icons.memory_rounded,
          options: [
            SelectOption(
              value: MediaDecoderMode.auto,
              label: l10n.decoderAutoOption,
            ),
            SelectOption(
              value: MediaDecoderMode.hardware,
              label: l10n.decoderHardwareOption,
            ),
            SelectOption(
              value: MediaDecoderMode.software,
              label: l10n.decoderSoftwareOption,
            ),
            SelectOption(
              value: MediaDecoderMode.ffmpeg,
              label: l10n.decoderFfmpegOption,
            ),
          ],
          onChanged: controller.setMediaViewerVideoDecoderMode,
        ),
      );
    }

    if ('aspect ratio fit fill 16:9 4:3 zoom'.contains(query) ||
        l10n.defaultAspectRatioTitle.toLowerCase().contains(query)) {
      matchingSettings.add(
        OptionPickerTile<VideoAspectRatioMode>(
          label: l10n.defaultAspectRatioTitle,
          value: mediaConfig.defaultAspectRatioMode,
          prefixIcon: mediaConfig.defaultAspectRatioMode.icon,
          options: VideoAspectRatioMode.values.map((mode) {
            return SelectOption(
              value: mode,
              label: mode.getLocalizedLabel(l10n),
            );
          }).toList(),
          onChanged: controller.setMediaViewerDefaultAspectRatioMode,
        ),
      );
    }

    if ('speed hold fast forward'.contains(query) ||
        l10n.holdSpeedMultiplierTitle.toLowerCase().contains(query)) {
      matchingSettings.add(
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          leading: Icon(Icons.speed_rounded, color: cs.primary),
          title: Text(l10n.holdSpeedMultiplierTitle),
          subtitle: _SettingsSlider(
            value: mediaConfig.holdToSpeedMultiplier,
            min: 0.25,
            max: 4.0,
            divisions: 15,
            labelBuilder: (v) =>
                '${v.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '')}x',
            onChangeEnd: (v) => unawaited(
              controller.setMediaViewerHoldToSpeedMultiplier(v),
            ),
          ),
        ),
      );
    }

    if ('thumbnail strategy frame position'.contains(query) ||
        l10n.thumbnailGenerationStrategyTitle.toLowerCase().contains(query)) {
      matchingSettings.add(
        OptionPickerTile<ThumbnailGenerationStrategy>(
          label: l10n.thumbnailGenerationStrategyTitle,
          value: mediaConfig.thumbnailGenerationStrategy,
          prefixIcon: Icons.video_library_outlined,
          options: [
            SelectOption(
              value: ThumbnailGenerationStrategy.firstFrame,
              label: l10n.thumbnailFirstFrameOption,
            ),
            SelectOption(
              value: ThumbnailGenerationStrategy.frameAtPercentage,
              label: l10n.thumbnailPercentageFrameOption,
            ),
            SelectOption(
              value: ThumbnailGenerationStrategy.hybrid,
              label: l10n.thumbnailHybridOption,
            ),
          ],
          onChanged: controller.setThumbnailGenerationStrategy,
        ),
      );
    }

    if (matchingSettings.isEmpty && matchingActions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search_off_rounded,
                size: 48,
                color: cs.onSurfaceVariant.withValues(alpha: 0.6),
              ),
              const SizedBox(height: 16),
              Text(
                'No matching settings or actions found',
                style: textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      children: [
        if (matchingSettings.isNotEmpty) ...[
          SectionHeader('Settings (${matchingSettings.length})'),
          SectionCard(children: matchingSettings),
          const SizedBox(height: 16),
        ],
        if (matchingActions.isNotEmpty) ...[
          SectionHeader('Toolbar Actions (${matchingActions.length})'),
          SectionCard(
            children: matchingActions.map((action) {
              final sec = _findCurrentSection(action, mediaConfig);
              return ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(action.icon, size: 20, color: cs.primary),
                ),
                title: Text(
                  action.getLocalizedLabel(l10n),
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  'Location: ${_sectionDisplayName(sec, l10n)}',
                  style: textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                trailing: _buildMoveMenu(
                  context: context,
                  ref: ref,
                  action: action,
                  currentSection: sec,
                  cs: cs,
                  l10n: l10n,
                ),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }
}

/// A [Slider] that tracks the drag locally for a responsive knob, and only
/// calls back (persisting through the settings controller) once the
/// person releases it -- persisting on every intermediate `onChanged` tick
/// would mean an async load+save round trip per pixel of drag.
class _SettingsSlider extends StatefulWidget {
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String Function(double value) labelBuilder;
  final ValueChanged<double> onChangeEnd;

  const _SettingsSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.labelBuilder,
    required this.onChangeEnd,
    this.divisions,
  });

  @override
  State<_SettingsSlider> createState() => _SettingsSliderState();
}

class _SettingsSliderState extends State<_SettingsSlider> {
  late double _liveValue = widget.value;

  @override
  void didUpdateWidget(covariant _SettingsSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _liveValue = widget.value;
    }
  }

  @override
  Widget build(BuildContext context) {
    final clamped = _liveValue.clamp(widget.min, widget.max);
    return Row(
      children: [
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(trackHeight: 3),
            child: Slider(
              value: clamped,
              min: widget.min,
              max: widget.max,
              divisions: widget.divisions,
              onChanged: (v) => setState(() => _liveValue = v),
              onChangeEnd: widget.onChangeEnd,
            ),
          ),
        ),
        SizedBox(
          width: 52,
          child: Text(
            widget.labelBuilder(clamped),
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
      ],
    );
  }
}
