import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';
import 'package:vaultexplorer/features/browser/viewer/native_media3_controller.dart';
import 'package:vaultexplorer/features/browser/viewer/native_video_controller.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/advanced_settings_controller.dart';

class AdvancedSettingsSheet extends ConsumerWidget {
  final bool isPlaylistMode;
  final bool isImage;
  final String currentFileName;
  final int initialRotation;
  final BoxFit initialImageFit;
  final int initialSlideshowDelaySeconds;
  final double initialPlaybackSpeed;
  final bool hasSubtitles;
  final bool initialSubtitlesEnabled;
  final double initialSubtitleFontSize;
  final double initialSubtitleVerticalPosition;
  final ValueChanged<int> onRotationChanged;
  final ValueChanged<BoxFit> onImageFitChanged;
  final ValueChanged<int> onSlideshowDelayChanged;
  final ValueChanged<double> onPlaybackSpeedChanged;
  final ValueChanged<bool> onSubtitlesEnabledChanged;
  final ValueChanged<double> onSubtitleFontSizeChanged;
  final ValueChanged<double> onSubtitleVerticalPositionChanged;
  final NativeVideoController? videoController;

  const AdvancedSettingsSheet({
    super.key,
    required this.isPlaylistMode,
    required this.isImage,
    required this.currentFileName,
    required this.initialRotation,
    required this.initialImageFit,
    required this.initialSlideshowDelaySeconds,
    required this.initialPlaybackSpeed,
    required this.hasSubtitles,
    required this.initialSubtitlesEnabled,
    this.initialSubtitleFontSize = 15.0,
    this.initialSubtitleVerticalPosition = 0.0,
    required this.onRotationChanged,
    required this.onImageFitChanged,
    required this.onSlideshowDelayChanged,
    required this.onPlaybackSpeedChanged,
    required this.onSubtitlesEnabledChanged,
    required this.onSubtitleFontSizeChanged,
    required this.onSubtitleVerticalPositionChanged,
    this.videoController,
  });

  AdvancedSettingsParams _buildParams() => AdvancedSettingsParams(
    initialRotation: initialRotation,
    initialImageFit: initialImageFit,
    initialSlideshowDelaySeconds: initialSlideshowDelaySeconds,
    initialPlaybackSpeed: initialPlaybackSpeed,
    initialSubtitlesEnabled: initialSubtitlesEnabled,
    initialSubtitleFontSize: initialSubtitleFontSize,
    initialSubtitleVerticalPosition: initialSubtitleVerticalPosition,
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
            .rotate(onRotationChanged);
      },
    );
  }

  Widget _buildHeader(BuildContext context, ColorScheme cs, String title, VoidCallback? onBack) {
    final textTheme = Theme.of(context).textTheme;
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
          if (onBack != null) const SizedBox(width: 48) else const SizedBox(width: 8),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final params = _buildParams();
    final state = ref.watch(advancedSettingsControllerProvider(params));
    final cs = Theme.of(context).colorScheme;
    final isLandscapeLayout = MediaQuery.of(context).orientation == Orientation.landscape;
    final double maxSheetHeight = isLandscapeLayout
        ? MediaQuery.of(context).size.height * 0.72
        : MediaQuery.of(context).size.height * 0.9;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxSheetHeight),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(
            left: 20,
            right: 20,
            top: 4,
            bottom: 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (state.sheetPage == 'main') ...[
                  _buildHeader(
                    context,
                    cs,
                    isImage ? context.l10n.imageSettingsTitle : context.l10n.playbackSettingsTitle,
                    null,
                  ),
                  const SizedBox(height: 8),
                  _buildMainPage(context, ref, params, state, cs),
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

  Widget _buildMainPage(
    BuildContext context,
    WidgetRef ref,
    AdvancedSettingsParams params,
    AdvancedSettingsState state,
    ColorScheme cs,
  ) {
    if (isImage) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildRotationTile(context, ref, params, state, cs),
          const Divider(),
          ListTile(
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
          ),
          if (isPlaylistMode) ...[
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.timer_outlined),
              title: Text(context.l10n.slideshowDelayLabel),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.l10n.slideshowDelaySecondsValue(state.slideshowDelaySeconds),
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
            ),
          ],
        ],
      );
    } else {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildRotationTile(context, ref, params, state, cs),
          const Divider(),
          ListTile(
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
          ),
          if (videoController != null) ...[
            ValueListenableBuilder<List<AudioTrackInfo>>(
              valueListenable: videoController!.audioTracksNotifier,
              builder: (context, audioTracks, _) {
                if (audioTracks.length <= 1) return const SizedBox.shrink();
                final selected = audioTracks.firstWhere(
                  (t) => t.isSelected,
                  orElse: () => audioTracks.first,
                );
                final selectedLabel = selected.label.isNotEmpty
                    ? selected.label
                    : (selected.language.isNotEmpty
                        ? selected.language
                        : context.l10n.trackNumberLabel(selected.trackIndex + 1));
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Divider(),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.audiotrack_rounded),
                      title: Text(context.l10n.audioTrackTitle),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            selectedLabel,
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
                            .setSheetPage('audioTracks');
                      },
                    ),
                  ],
                );
              },
            ),
            ValueListenableBuilder<List<SubtitleTrackInfo>>(
              valueListenable: videoController!.subtitleTracksNotifier,
              builder: (context, subTracks, _) {
                final hasSubTracks = subTracks.isNotEmpty;
                if (!hasSubTracks && !hasSubtitles) return const SizedBox.shrink();

                final selectedSub = subTracks.firstWhere(
                  (t) => t.isSelected,
                  orElse: () => const SubtitleTrackInfo(
                    groupIndex: -1,
                    trackIndex: -1,
                    isSelected: false,
                    language: '',
                    label: '',
                    mimeType: '',
                    id: '',
                  ),
                );
                final label = (selectedSub.isSelected && state.subtitlesEnabled)
                    ? (selectedSub.label.isNotEmpty
                        ? selectedSub.label
                        : (selectedSub.language.isNotEmpty
                            ? selectedSub.language
                            : context.l10n.subtitleTrackNumberLabel(selectedSub.trackIndex + 1)))
                    : (state.subtitlesEnabled && hasSubtitles ? context.l10n.externalLabel : context.l10n.offLabel);

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Divider(),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.subtitles_rounded),
                      title: Text(context.l10n.subtitlesLabel),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            label,
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
                            .setSheetPage('subtitleTracks');
                      },
                    ),
                  ],
                );
              },
            ),
          ] else if (hasSubtitles) ...[
            const Divider(),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.subtitles_rounded),
              title: Text(context.l10n.subtitlesLabel),
              value: state.subtitlesEnabled,
              activeThumbColor: cs.primary,
              onChanged: (val) {
                HapticFeedback.lightImpact();
                ref
                    .read(advancedSettingsControllerProvider(params).notifier)
                    .setSubtitlesEnabled(val, onSubtitlesEnabledChanged);
              },
            ),
          ],
        ],
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
                .setImageFit(fit, onImageFitChanged);
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
                .setSlideshowDelay(delay, onSlideshowDelayChanged);
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
                .setPlaybackSpeed(speed, onPlaybackSpeedChanged);
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
    final tracks = videoController?.audioTracks ?? [];
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
              ? Text('${track.mimeType} ${track.channelCount != null ? '(${track.channelCount} ch)' : ''}')
              : null,
          trailing: isSelected
              ? Icon(Icons.check_rounded, color: cs.primary, size: 18)
              : const SizedBox(width: 18),
          onTap: () {
            HapticFeedback.lightImpact();
            videoController?.selectAudioTrack(track.groupIndex, track.trackIndex);
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
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
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
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  color: isSelected ? cs.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text(
                  opt.$2,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
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
    final tracks = videoController?.subtitleTracks ?? [];
    final hasActiveSelection = tracks.any((t) => t.isSelected);
    final isOff = !state.subtitlesEnabled || (!hasActiveSelection && !hasSubtitles);

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
                    .setSubtitleFontSize(val, onSubtitleFontSizeChanged),
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
                    .setSubtitleVerticalPosition(val, onSubtitleVerticalPositionChanged),
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
                .disableSubtitles(videoController, onSubtitlesEnabledChanged);
          },
        ),
        if (hasSubtitles)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              context.l10n.externalSubtitlesLabel,
              style: TextStyle(
                color: state.subtitlesEnabled && !hasActiveSelection ? cs.primary : null,
                fontWeight: state.subtitlesEnabled && !hasActiveSelection ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            trailing: state.subtitlesEnabled && !hasActiveSelection
                ? Icon(Icons.check_rounded, color: cs.primary, size: 18)
                : const SizedBox(width: 18),
            onTap: () {
              HapticFeedback.lightImpact();
              ref
                  .read(advancedSettingsControllerProvider(params).notifier)
                  .enableExternalSubtitles(videoController, onSubtitlesEnabledChanged);
            },
          ),
        ...tracks.map((track) {
          final label = track.label.isNotEmpty
              ? track.label
              : (track.language.isNotEmpty
                  ? track.language
                  : context.l10n.subtitleTrackNumberLabel(track.trackIndex + 1));
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
                    videoController,
                    track.groupIndex,
                    track.trackIndex,
                    onSubtitlesEnabledChanged,
                  );
            },
          );
        }),
      ],
    );
  }
}