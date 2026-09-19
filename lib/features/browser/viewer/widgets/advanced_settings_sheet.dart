import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/data/models/media_viewer_action.dart';
import 'package:vaultexplorer/data/models/video_aspect_ratio_mode.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';
import 'package:vaultexplorer/features/browser/viewer/native_media3_controller.dart';
import 'package:vaultexplorer/features/browser/viewer/native_video_controller.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/advanced_settings_controller.dart';

class AdvancedSettingsSheet extends ConsumerStatefulWidget {
  final String? initialPage;
  final List<MediaViewerAction> actions;
  final ValueChanged<MediaViewerAction> onExecuteAction;
  final VoidCallback onCustomizeControls;
  final bool isPlaylistMode;
  final bool isImage;
  final String currentFileName;
  final int initialRotation;
  final BoxFit initialImageFit;
  final int initialSlideshowDelaySeconds;
  final double initialPlaybackSpeed;
  final VideoAspectRatioMode initialAspectRatioMode;
  final bool hasSubtitles;
  final bool initialSubtitlesEnabled;
  final double initialSubtitleFontSize;
  final double initialSubtitleVerticalPosition;
  final ValueChanged<int> onRotationChanged;
  final ValueChanged<BoxFit> onImageFitChanged;
  final ValueChanged<int> onSlideshowDelayChanged;
  final ValueChanged<double> onPlaybackSpeedChanged;
  final ValueChanged<VideoAspectRatioMode> onAspectRatioModeChanged;
  final ValueChanged<bool> onSubtitlesEnabledChanged;
  final ValueChanged<double> onSubtitleFontSizeChanged;
  final ValueChanged<double> onSubtitleVerticalPositionChanged;
  final NativeVideoController? videoController;
  final bool isMuted;

  const AdvancedSettingsSheet({
    super.key,
    this.initialPage,
    this.actions = const [],
    required this.onExecuteAction,
    required this.onCustomizeControls,
    required this.isPlaylistMode,
    required this.isImage,
    this.isMuted = false,
    required this.currentFileName,
    required this.initialRotation,
    required this.initialImageFit,
    required this.initialSlideshowDelaySeconds,
    required this.initialPlaybackSpeed,
    this.initialAspectRatioMode = VideoAspectRatioMode.bestFit,
    required this.hasSubtitles,
    required this.initialSubtitlesEnabled,
    this.initialSubtitleFontSize = 15.0,
    this.initialSubtitleVerticalPosition = 0.0,
    required this.onRotationChanged,
    required this.onImageFitChanged,
    required this.onSlideshowDelayChanged,
    required this.onPlaybackSpeedChanged,
    required this.onAspectRatioModeChanged,
    required this.onSubtitlesEnabledChanged,
    required this.onSubtitleFontSizeChanged,
    required this.onSubtitleVerticalPositionChanged,
    this.videoController,
  });

  @override
  ConsumerState<AdvancedSettingsSheet> createState() =>
      _AdvancedSettingsSheetState();
}

class _AdvancedSettingsSheetState extends ConsumerState<AdvancedSettingsSheet> {
  @override
  void initState() {
    super.initState();
    if (widget.initialPage != null && widget.initialPage != 'main') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref
            .read(advancedSettingsControllerProvider(_buildParams()).notifier)
            .setSheetPage(widget.initialPage!);
      });
    }
  }

  AdvancedSettingsParams _buildParams() => AdvancedSettingsParams(
        initialRotation: widget.initialRotation,
        initialImageFit: widget.initialImageFit,
        initialSlideshowDelaySeconds: widget.initialSlideshowDelaySeconds,
        initialPlaybackSpeed: widget.initialPlaybackSpeed,
        initialAspectRatioMode: widget.initialAspectRatioMode,
        initialSubtitlesEnabled: widget.initialSubtitlesEnabled,
        initialSubtitleFontSize: widget.initialSubtitleFontSize,
        initialSubtitleVerticalPosition: widget.initialSubtitleVerticalPosition,
      );

  static String _getImageFitLabel(BuildContext context, BoxFit fit) {
    if (fit == BoxFit.contain) return context.l10n.imageFitContain;
    if (fit == BoxFit.fitWidth) return context.l10n.imageFitWidth;
    if (fit == BoxFit.fitHeight) return context.l10n.imageFitHeight;
    return context.l10n.imageFitContain;
  }

  Widget _buildRotationTile(
    BuildContext context,
    WidgetRef ref,
    AdvancedSettingsParams params,
    AdvancedSettingsState state,
    ColorScheme cs,
  ) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.rotate_right_rounded),
      title: Text(context.l10n.rotate90Label),
      trailing: Text(
        context.l10n.rotationDegreesValue(state.rotation * 90),
        style: TextStyle(
          color: cs.primary,
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
      ),
      onTap: () {
        HapticFeedback.mediumImpact();
        ref
            .read(advancedSettingsControllerProvider(params).notifier)
            .rotate(widget.onRotationChanged);
      },
    );
  }

  Widget _buildHeader(
      BuildContext context, ColorScheme cs, String title, VoidCallback? onBack) {
    final textTheme = context.typography;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          if (onBack != null)
            IconButton(
              icon: Icon(
                Icons.arrow_back_rounded,
                color: cs.onSurfaceVariant,
              ),
              onPressed: onBack,
            )
          else
            const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: onBack != null ? TextAlign.left : TextAlign.center,
            ),
          ),
          if (onBack != null)
            const SizedBox(width: 48)
          else
            const SizedBox(width: 8),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final params = _buildParams();
    final state = ref.watch(advancedSettingsControllerProvider(params));
    final cs = context.colors;
    final isLandscapeLayout =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final double maxSheetHeight = isLandscapeLayout
        ? MediaQuery.of(context).size.height * 0.75
        : MediaQuery.of(context).size.height * 0.9;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxSheetHeight),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.md,
            right: AppSpacing.md,
            top: AppSpacing.xs,
            bottom: AppSpacing.lg,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (state.sheetPage == 'main') ...[
                  _buildHeader(
                    context,
                    cs,
                    widget.isImage
                        ? context.l10n.imageSettingsTitle
                        : context.l10n.playbackSettingsTitle,
                    null,
                  ),
                  const SizedBox(height: 8),
                  _buildDynamicControls(context, ref, params, state, cs),
                ] else if (state.sheetPage == 'imageFit') ...[
                  _buildHeader(
                    context,
                    cs,
                    context.l10n.imageFitModeLabel,
                    () => ref
                        .read(advancedSettingsControllerProvider(params).notifier)
                        .setSheetPage('main'),
                  ),
                  const SizedBox(height: 8),
                  _buildImageFitSubmenu(context, ref, params, state, cs),
                ] else if (state.sheetPage == 'slideshowDelay') ...[
                  _buildHeader(
                    context,
                    cs,
                    context.l10n.slideshowDelayLabel,
                    () => ref
                        .read(advancedSettingsControllerProvider(params).notifier)
                        .setSheetPage('main'),
                  ),
                  const SizedBox(height: 8),
                  _buildSlideshowDelaySubmenu(context, ref, params, state, cs),
                ] else if (state.sheetPage == 'playbackSpeed') ...[
                  _buildHeader(
                    context,
                    cs,
                    context.l10n.playbackSpeedLabel,
                    () => ref
                        .read(advancedSettingsControllerProvider(params).notifier)
                        .setSheetPage('main'),
                  ),
                  const SizedBox(height: 8),
                  _buildPlaybackSpeedSubmenu(context, ref, params, state, cs),
                ] else if (state.sheetPage == 'aspectRatio') ...[
                  _buildHeader(
                    context,
                    cs,
                    context.l10n.aspectRatioModeLabel,
                    () => ref
                        .read(advancedSettingsControllerProvider(params).notifier)
                        .setSheetPage('main'),
                  ),
                  const SizedBox(height: 8),
                  _buildAspectRatioSubmenu(context, ref, params, state, cs),
                ] else if (state.sheetPage == 'audioTracks') ...[
                  _buildHeader(
                    context,
                    cs,
                    context.l10n.audioTrackTitle,
                    () => ref
                        .read(advancedSettingsControllerProvider(params).notifier)
                        .setSheetPage('main'),
                  ),
                  const SizedBox(height: 8),
                  _buildAudioTrackSubmenu(context, ref, params, cs),
                ] else if (state.sheetPage == 'subtitleTracks') ...[
                  _buildHeader(
                    context,
                    cs,
                    context.l10n.subtitlesLabel,
                    () => ref
                        .read(advancedSettingsControllerProvider(params).notifier)
                        .setSheetPage('main'),
                  ),
                  const SizedBox(height: 8),
                  _buildSubtitleTrackSubmenu(context, ref, params, state, cs),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDynamicControls(
    BuildContext context,
    WidgetRef ref,
    AdvancedSettingsParams params,
    AdvancedSettingsState state,
    ColorScheme cs,
  ) {
    final effectiveActions = widget.actions.where((a) {
      if (a == MediaViewerAction.advancedSettings) return false;
      return a.isApplicable(
        isImage: widget.isImage,
        isAudio: false,
        isPlaylistMode: widget.isPlaylistMode,
      );
    }).toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (effectiveActions.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: Text(
              'No controls assigned to Advanced Settings.',
              style: TextStyle(
                fontStyle: FontStyle.italic,
                color: cs.onSurfaceVariant,
              ),
            ),
          )
        else
          for (int i = 0; i < effectiveActions.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            _buildActionRow(context, ref, params, state, cs, effectiveActions[i]),
          ],
        const Divider(),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.dashboard_customize_rounded, color: cs.primary),
          title: Text(
            context.l10n.mediaViewerCustomizeControls,
            style: TextStyle(color: cs.primary, fontWeight: FontWeight.bold),
          ),
          onTap: () {
            Navigator.pop(context);
            widget.onCustomizeControls();
          },
        ),
      ],
    );
  }

  Widget _buildActionRow(
    BuildContext context,
    WidgetRef ref,
    AdvancedSettingsParams params,
    AdvancedSettingsState state,
    ColorScheme cs,
    MediaViewerAction action,
  ) {
    switch (action) {
      case MediaViewerAction.rotate90:
        return _buildRotationTile(context, ref, params, state, cs);
      case MediaViewerAction.imageFit:
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.aspect_ratio_rounded),
          title: Text(context.l10n.imageFitModeLabel),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _getImageFitLabel(context, state.imageFit),
                style: TextStyle(color: cs.primary, fontSize: 13),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded, size: 20),
            ],
          ),
          onTap: () {
            HapticFeedback.lightImpact();
            ref
                .read(advancedSettingsControllerProvider(params).notifier)
                .setSheetPage('imageFit');
          },
        );
      case MediaViewerAction.playbackSpeed:
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.slow_motion_video_rounded),
          title: Text(context.l10n.playbackSpeedLabel),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.l10n.playbackSpeedValue('${state.playbackSpeed}'),
                style: TextStyle(color: cs.primary, fontSize: 13),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded, size: 20),
            ],
          ),
          onTap: () {
            HapticFeedback.lightImpact();
            ref
                .read(advancedSettingsControllerProvider(params).notifier)
                .setSheetPage('playbackSpeed');
          },
        );
      case MediaViewerAction.aspectRatio:
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.aspect_ratio_rounded),
          title: Text(context.l10n.aspectRatioModeLabel),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                state.aspectRatioMode.getLocalizedLabel(context.l10n),
                style: TextStyle(color: cs.primary, fontSize: 13),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded, size: 20),
            ],
          ),
          onTap: () {
            HapticFeedback.lightImpact();
            ref
                .read(advancedSettingsControllerProvider(params).notifier)
                .setSheetPage('aspectRatio');
          },
        );
      case MediaViewerAction.slideshowDelay:
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.timer_outlined),
          title: Text(context.l10n.slideshowDelayLabel),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.l10n
                    .slideshowDelaySecondsValue(state.slideshowDelaySeconds),
                style: TextStyle(color: cs.primary, fontSize: 13),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded, size: 20),
            ],
          ),
          onTap: () {
            HapticFeedback.lightImpact();
            ref
                .read(advancedSettingsControllerProvider(params).notifier)
                .setSheetPage('slideshowDelay');
          },
        );
      case MediaViewerAction.audioTrack:
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.audiotrack_rounded),
          title: Text(context.l10n.audioTrackTitle),
          trailing: const Icon(Icons.chevron_right_rounded, size: 20),
          onTap: () {
            HapticFeedback.lightImpact();
            ref
                .read(advancedSettingsControllerProvider(params).notifier)
                .setSheetPage('audioTracks');
          },
        );
     case MediaViewerAction.subtitles:
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.subtitles_rounded),
          title: Text(context.l10n.subtitlesLabel),
          trailing: const Icon(Icons.chevron_right_rounded, size: 20),
          onTap: () {
            HapticFeedback.lightImpact();
            ref
                .read(advancedSettingsControllerProvider(params).notifier)
                .setSheetPage('subtitleTracks');
          },
        );
      case MediaViewerAction.mute:
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            widget.isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
            color: widget.isMuted ? cs.error : null,
          ),
          title: Text(
            action.getLocalizedLabel(context.l10n),
            style: widget.isMuted ? TextStyle(color: cs.error) : null,
          ),
          trailing: Switch(
            value: !widget.isMuted,
            activeColor: cs.primary,
            onChanged: (_) {
              widget.onExecuteAction(MediaViewerAction.mute);
            },
          ),
          onTap: () {
            widget.onExecuteAction(MediaViewerAction.mute);
          },
        );
      default:
        final isDelete = action == MediaViewerAction.delete;
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(action.icon, color: isDelete ? cs.error : null),
          title: Text(
            action.getLocalizedLabel(context.l10n),
            style: isDelete ? TextStyle(color: cs.error) : null,
          ),
          onTap: () {
            Navigator.pop(context);
            widget.onExecuteAction(action);
          },
        );
    }
  }

  Widget _buildImageFitSubmenu(
    BuildContext context,
    WidgetRef ref,
    AdvancedSettingsParams params,
    AdvancedSettingsState state,
    ColorScheme cs,
  ) {
    final fits = [BoxFit.contain, BoxFit.fitWidth, BoxFit.fitHeight];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: fits.map((fit) {
        final isSelected = state.imageFit == fit;
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            _getImageFitLabel(context, fit),
            style: TextStyle(
              color: isSelected ? cs.primary : null,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          trailing: isSelected
              ? Icon(Icons.check_rounded, color: cs.primary, size: 18)
              : const SizedBox(width: 18),
          onTap: () {
            HapticFeedback.lightImpact();
            ref
                .read(advancedSettingsControllerProvider(params).notifier)
                .setImageFit(fit, widget.onImageFitChanged);
            if (widget.initialPage != null && widget.initialPage != 'main') {
              Navigator.pop(context);
            } else {
              ref
                  .read(advancedSettingsControllerProvider(params).notifier)
                  .setSheetPage('main');
            }
          },
        );
      }).toList(),
    );
  }

  Widget _buildSlideshowDelaySubmenu(
    BuildContext context,
    WidgetRef ref,
    AdvancedSettingsParams params,
    AdvancedSettingsState state,
    ColorScheme cs,
  ) {
    final delays = [2, 4, 6, 8, 10];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: delays.map((delay) {
        final isSelected = state.slideshowDelaySeconds == delay;
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            context.l10n.nSecondsDelay(delay),
            style: TextStyle(
              color: isSelected ? cs.primary : null,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          trailing: isSelected
              ? Icon(Icons.check_rounded, color: cs.primary, size: 18)
              : const SizedBox(width: 18),
           onTap: () {
            HapticFeedback.lightImpact();
            ref
                .read(advancedSettingsControllerProvider(params).notifier)
                .setSlideshowDelay(delay, widget.onSlideshowDelayChanged);
            if (widget.initialPage != null && widget.initialPage != 'main') {
              Navigator.pop(context);
            } else {
              ref
                  .read(advancedSettingsControllerProvider(params).notifier)
                  .setSheetPage('main');
            }
          },
        );
      }).toList(),
    );
  }

  Widget _buildPlaybackSpeedSubmenu(
    BuildContext context,
    WidgetRef ref,
    AdvancedSettingsParams params,
    AdvancedSettingsState state,
    ColorScheme cs,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: MediaViewerConstants.playbackSpeeds.map((speed) {
        final isSelected = state.playbackSpeed == speed;
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            speed == 1.0
                ? context.l10n.playbackSpeedNormal('$speed')
                : context.l10n.playbackSpeedValue('$speed'),
            style: TextStyle(
              color: isSelected ? cs.primary : null,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          trailing: isSelected
              ? Icon(Icons.check_rounded, color: cs.primary, size: 18)
              : const SizedBox(width: 18),
          onTap: () {
            HapticFeedback.lightImpact();
            ref
                .read(advancedSettingsControllerProvider(params).notifier)
                .setPlaybackSpeed(speed, widget.onPlaybackSpeedChanged);
            if (widget.initialPage != null && widget.initialPage != 'main') {
              Navigator.pop(context);
            } else {
              ref
                  .read(advancedSettingsControllerProvider(params).notifier)
                  .setSheetPage('main');
            }
          },
        );
      }).toList(),
    );
  }

  Widget _buildAspectRatioSubmenu(
    BuildContext context,
    WidgetRef ref,
    AdvancedSettingsParams params,
    AdvancedSettingsState state,
    ColorScheme cs,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: VideoAspectRatioMode.values.map((mode) {
        final isSelected = state.aspectRatioMode == mode;
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            mode.icon,
            color: isSelected ? cs.primary : cs.onSurfaceVariant,
            size: 20,
          ),
          title: Text(
            mode.getLocalizedLabel(context.l10n),
            style: TextStyle(
              color: isSelected ? cs.primary : null,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          trailing: isSelected
              ? Icon(Icons.check_rounded, color: cs.primary, size: 18)
              : const SizedBox(width: 18),
          onTap: () {
            HapticFeedback.lightImpact();
            ref
                .read(advancedSettingsControllerProvider(params).notifier)
                .setAspectRatioMode(mode, widget.onAspectRatioModeChanged);
            if (widget.initialPage != null && widget.initialPage != 'main') {
              Navigator.pop(context);
            } else {
              ref
                  .read(advancedSettingsControllerProvider(params).notifier)
                  .setSheetPage('main');
            }
          },
        );
      }).toList(),
    );
  }

  Widget _buildAudioTrackSubmenu(
    BuildContext context,
    WidgetRef ref,
    AdvancedSettingsParams params,
    ColorScheme cs,
  ) {
    final tracks = widget.videoController?.audioTracks ?? [];
    if (tracks.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Text(context.l10n.noAudioTracksAvailable),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: tracks.map((track) {
        final label = track.label.isNotEmpty
            ? track.label
            : (track.language.isNotEmpty
                ? track.language
                : context.l10n.trackNumberLabel(track.trackIndex + 1));
        final isSelected = track.isSelected;
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            label,
            style: TextStyle(
              color: isSelected ? cs.primary : null,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          subtitle: track.mimeType.isNotEmpty
              ? Text(
                  '${track.mimeType} ${track.channelCount != null ? '(${track.channelCount} ch)' : ''}')
              : null,
          trailing: isSelected
              ? Icon(Icons.check_rounded, color: cs.primary, size: 18)
              : const SizedBox(width: 18),
          onTap: () {
            HapticFeedback.lightImpact();
            widget.videoController
                ?.selectAudioTrack(track.groupIndex, track.trackIndex);
            ref
                .read(advancedSettingsControllerProvider(params).notifier)
                .setSheetPage('main');
          },
        );
      }).toList(),
    );
  }

  Widget _buildSegmentedBar<T>({
    required BuildContext context,
    required List<(T, String)> options,
    required T selectedValue,
    required ValueChanged<T> onSelected,
    bool Function(T a, T b)? isValueEqual,
  }) {
    final cs = context.colors;
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: options.map((opt) {
          final isSelected = isValueEqual != null
              ? isValueEqual(selectedValue, opt.$1)
              : selectedValue == opt.$1;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                onSelected(opt.$1);
              },
              child: AnimatedContainer(
                duration: AppMotion.short2,
                decoration: BoxDecoration(
                  color: isSelected ? cs.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                alignment: Alignment.center,
                child: Text(
                  opt.$2,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? cs.onPrimary : cs.onSurface,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSubtitleTrackSubmenu(
    BuildContext context,
    WidgetRef ref,
    AdvancedSettingsParams params,
    AdvancedSettingsState state,
    ColorScheme cs,
  ) {
    final tracks = widget.videoController?.subtitleTracks ?? [];
    final hasActiveSelection = tracks.any((t) => t.isSelected);
    final isOff =
        !state.subtitlesEnabled || (!hasActiveSelection && !widget.hasSubtitles);

    final sizeOptions = [
      (12.0, context.l10n.subtitleSizeSmall),
      (15.0, context.l10n.subtitleSizeMedium),
      (19.0, context.l10n.subtitleSizeLarge),
      (24.0, context.l10n.subtitleSizeExtraLarge),
    ];

    final positionOptions = [
      (0.0, context.l10n.subtitlePositionBottom),
      (0.33, context.l10n.subtitlePositionLower),
      (0.66, context.l10n.subtitlePositionCenter),
      (1.0, context.l10n.subtitlePositionTop),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.subtitleSizeLabel,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              _buildSegmentedBar<double>(
                context: context,
                options: sizeOptions,
                selectedValue: state.subtitleFontSize,
                isValueEqual: (a, b) => (a - b).abs() < 0.5,
                onSelected: (val) => ref
                    .read(advancedSettingsControllerProvider(params).notifier)
                    .setSubtitleFontSize(val, widget.onSubtitleFontSizeChanged),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.subtitlePositionLabel,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              _buildSegmentedBar<double>(
                context: context,
                options: positionOptions,
                selectedValue: state.subtitleVerticalPosition,
                isValueEqual: (a, b) => (a - b).abs() < 0.18,
                onSelected: (val) => ref
                    .read(advancedSettingsControllerProvider(params).notifier)
                    .setSubtitleVerticalPosition(
                        val, widget.onSubtitleVerticalPositionChanged),
              ),
            ],
          ),
        ),
        const Divider(height: 20),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            context.l10n.offLabel,
            style: TextStyle(
              color: isOff ? cs.primary : null,
              fontWeight: isOff ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          trailing: isOff
              ? Icon(Icons.check_rounded, color: cs.primary, size: 18)
              : const SizedBox(width: 18),
          onTap: () {
            HapticFeedback.lightImpact();
            ref
                .read(advancedSettingsControllerProvider(params).notifier)
                .disableSubtitles(
                    widget.videoController, widget.onSubtitlesEnabledChanged);
          },
        ),
        if (widget.hasSubtitles)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              context.l10n.externalSubtitlesLabel,
              style: TextStyle(
                color: state.subtitlesEnabled && !hasActiveSelection
                    ? cs.primary
                    : null,
                fontWeight: state.subtitlesEnabled && !hasActiveSelection
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
            ),
            trailing: state.subtitlesEnabled && !hasActiveSelection
                ? Icon(Icons.check_rounded, color: cs.primary, size: 18)
                : const SizedBox(width: 18),
            onTap: () {
              HapticFeedback.lightImpact();
              ref
                  .read(advancedSettingsControllerProvider(params).notifier)
                  .enableExternalSubtitles(
                      widget.videoController, widget.onSubtitlesEnabledChanged);
            },
          ),
        ...tracks.map((track) {
          final label = track.label.isNotEmpty
              ? track.label
              : (track.language.isNotEmpty
                  ? track.language
                  : context.l10n
                      .subtitleTrackNumberLabel(track.trackIndex + 1));
          final isSelected = track.isSelected && state.subtitlesEnabled;
          return ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              label,
              style: TextStyle(
                color: isSelected ? cs.primary : null,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            subtitle: track.mimeType.isNotEmpty ? Text(track.mimeType) : null,
            trailing: isSelected
                ? Icon(Icons.check_rounded, color: cs.primary, size: 18)
                : const SizedBox(width: 18),
            onTap: () {
              HapticFeedback.lightImpact();
              ref
                .read(advancedSettingsControllerProvider(params).notifier)
                .selectSubtitleTrack(
                  widget.videoController,
                  track.groupIndex,
                  track.trackIndex,
                  widget.onSubtitlesEnabledChanged,
                );
            },
          );
        }),
      ],
    );
  }
}