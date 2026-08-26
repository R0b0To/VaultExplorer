import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/features/browser/viewer/native_video_controller.dart';
import 'package:vaultexplorer/features/browser/viewer/native_media3_controller.dart';

class AdvancedSettingsSheet extends StatefulWidget {
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

  @override
  State<AdvancedSettingsSheet> createState() => _AdvancedSettingsSheetState();
}

class _AdvancedSettingsSheetState extends State<AdvancedSettingsSheet> {
  String _sheetPage = 'main';
  late int _currentRotation;
  late BoxFit _currentImageFit;
  late int _currentSlideshowDelaySeconds;
  late double _currentPlaybackSpeed;
  late bool _currentSubtitlesEnabled;
  late double _currentSubtitleFontSize;
  late double _currentSubtitleVerticalPosition;

  @override
  void initState() {
    super.initState();
    _currentRotation = widget.initialRotation;
    _currentImageFit = widget.initialImageFit;
    _currentSlideshowDelaySeconds = widget.initialSlideshowDelaySeconds;
    _currentPlaybackSpeed = widget.initialPlaybackSpeed;
    _currentSubtitlesEnabled = widget.initialSubtitlesEnabled;
    _currentSubtitleFontSize = widget.initialSubtitleFontSize;
    _currentSubtitleVerticalPosition = widget.initialSubtitleVerticalPosition;
  }

  String _getImageFitLabel(BoxFit fit) {
    if (fit == BoxFit.contain) return context.l10n.imageFitContain;
    if (fit == BoxFit.fitWidth) return context.l10n.imageFitWidth;
    if (fit == BoxFit.fitHeight) return context.l10n.imageFitHeight;
    return context.l10n.imageFitContain;
  }

  Widget _buildRotationTile(ColorScheme cs) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.rotate_right_rounded),
      title: Text(context.l10n.rotate90Label),
      trailing: Text(
        context.l10n.rotationDegreesValue(_currentRotation * 90),
        style: TextStyle(
          color: cs.primary,
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
      ),
      onTap: () {
        HapticFeedback.mediumImpact();
        setState(() {
          _currentRotation = (_currentRotation + 1) % 4;
        });
        widget.onRotationChanged(_currentRotation);
      },
    );
  }

  Widget _buildHeader(ColorScheme cs, String title, VoidCallback? onBack) {
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
  Widget build(BuildContext context) {
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
                if (_sheetPage == 'main') ...[
                  _buildHeader(cs, widget.isImage ? context.l10n.imageSettingsTitle : context.l10n.playbackSettingsTitle, null),
                  const SizedBox(height: 8),
                  _buildMainPage(cs),
                ] else if (_sheetPage == 'imageFit') ...[
                  _buildHeader(cs, context.l10n.imageFitModeLabel, () => setState(() => _sheetPage = 'main')),
                  const SizedBox(height: 8),
                  _buildImageFitSubmenu(cs),
                ] else if (_sheetPage == 'slideshowDelay') ...[
                  _buildHeader(cs, context.l10n.slideshowDelayLabel, () => setState(() => _sheetPage = 'main')),
                  const SizedBox(height: 8),
                  _buildSlideshowDelaySubmenu(cs),
                ] else if (_sheetPage == 'playbackSpeed') ...[
                  _buildHeader(cs, context.l10n.playbackSpeedLabel, () => setState(() => _sheetPage = 'main')),
                  const SizedBox(height: 8),
                  _buildPlaybackSpeedSubmenu(cs),
                ] else if (_sheetPage == 'audioTracks') ...[
                  _buildHeader(cs, context.l10n.audioTrackTitle, () => setState(() => _sheetPage = 'main')),
                  const SizedBox(height: 8),
                  _buildAudioTrackSubmenu(cs),
                ] else if (_sheetPage == 'subtitleTracks') ...[
                  _buildHeader(cs, context.l10n.subtitlesLabel, () => setState(() => _sheetPage = 'main')),
                  const SizedBox(height: 8),
                  _buildSubtitleTrackSubmenu(cs),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMainPage(ColorScheme cs) {
    if (widget.isImage) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildRotationTile(cs),
          const Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.aspect_ratio_rounded),
            title: Text(context.l10n.imageFitModeLabel),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _getImageFitLabel(_currentImageFit),
                  style: TextStyle(color: cs.primary, fontSize: 13),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded, size: 20),
              ],
            ),
            onTap: () {
              HapticFeedback.lightImpact();
              setState(() => _sheetPage = 'imageFit');
            },
          ),
          if (widget.isPlaylistMode) ...[
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.timer_outlined),
              title: Text(context.l10n.slideshowDelayLabel),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.l10n.slideshowDelaySecondsValue(_currentSlideshowDelaySeconds),
                    style: TextStyle(color: cs.primary, fontSize: 13),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right_rounded, size: 20),
                ],
              ),
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() => _sheetPage = 'slideshowDelay');
              },
            ),
          ],
        ],
      );
    } else {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildRotationTile(cs),
          const Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.slow_motion_video_rounded),
            title: Text(context.l10n.playbackSpeedLabel),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  context.l10n.playbackSpeedValue('$_currentPlaybackSpeed'),
                  style: TextStyle(color: cs.primary, fontSize: 13),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded, size: 20),
              ],
            ),
            onTap: () {
              HapticFeedback.lightImpact();
              setState(() => _sheetPage = 'playbackSpeed');
            },
          ),
          if (widget.videoController != null) ...[
            ValueListenableBuilder<List<AudioTrackInfo>>(
              valueListenable: widget.videoController!.audioTracksNotifier,
              builder: (context, audioTracks, _) {
                if (audioTracks.length <= 1) return const SizedBox.shrink();
                final selected = audioTracks.firstWhere(
                  (t) => t.isSelected,
                  orElse: () => audioTracks.first,
                );
                final selectedLabel = selected.label.isNotEmpty
                    ? selected.label
                    : (selected.language.isNotEmpty ? selected.language : context.l10n.trackNumberLabel(selected.trackIndex + 1));
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
                        setState(() => _sheetPage = 'audioTracks');
                      },
                    ),
                  ],
                );
              },
            ),
            ValueListenableBuilder<List<SubtitleTrackInfo>>(
              valueListenable: widget.videoController!.subtitleTracksNotifier,
              builder: (context, subTracks, _) {
                final hasSubTracks = subTracks.isNotEmpty;
                if (!hasSubTracks && !widget.hasSubtitles) return const SizedBox.shrink();

                final selectedSub = subTracks.firstWhere(
                  (t) => t.isSelected,
                  orElse: () => const SubtitleTrackInfo(
                    groupIndex: -1, trackIndex: -1, isSelected: false, language: '', label: '', mimeType: '', id: ''
                  ),
                );
                final label = (selectedSub.isSelected && _currentSubtitlesEnabled)
                    ? (selectedSub.label.isNotEmpty
                        ? selectedSub.label
                        : (selectedSub.language.isNotEmpty ? selectedSub.language : context.l10n.subtitleTrackNumberLabel(selectedSub.trackIndex + 1)))
                    : (_currentSubtitlesEnabled && widget.hasSubtitles ? context.l10n.externalLabel : context.l10n.offLabel);

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
                        setState(() => _sheetPage = 'subtitleTracks');
                      },
                    ),
                  ],
                );
              },
            ),
          ] else if (widget.hasSubtitles) ...[
            const Divider(),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.subtitles_rounded),
              title: Text(context.l10n.subtitlesLabel),
              value: _currentSubtitlesEnabled,
              activeThumbColor: cs.primary,
              onChanged: (val) {
                HapticFeedback.lightImpact();
                setState(() => _currentSubtitlesEnabled = val);
                widget.onSubtitlesEnabledChanged(val);
              },
            ),
          ],
        ],
      );
    }
  }

  Widget _buildImageFitSubmenu(ColorScheme cs) {
    final fits = [BoxFit.contain, BoxFit.fitWidth, BoxFit.fitHeight];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: fits.map((fit) {
        final isSelected = _currentImageFit == fit;
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            _getImageFitLabel(fit),
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
            setState(() {
              _currentImageFit = fit;
              _sheetPage = 'main';
            });
            widget.onImageFitChanged(fit);
          },
        );
      }).toList(),
    );
  }

  Widget _buildSlideshowDelaySubmenu(ColorScheme cs) {
    final delays = [2, 4, 6, 8, 10];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: delays.map((delay) {
        final isSelected = _currentSlideshowDelaySeconds == delay;
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
            setState(() {
              _currentSlideshowDelaySeconds = delay;
              _sheetPage = 'main';
            });
            widget.onSlideshowDelayChanged(delay);
          },
        );
      }).toList(),
    );
  }

  Widget _buildPlaybackSpeedSubmenu(ColorScheme cs) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: MediaViewerConstants.playbackSpeeds.map((speed) {
        final isSelected = _currentPlaybackSpeed == speed;
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
            setState(() {
              _currentPlaybackSpeed = speed;
              _sheetPage = 'main';
            });
            widget.onPlaybackSpeedChanged(speed);
          },
        );
      }).toList(),
    );
  }

  Widget _buildAudioTrackSubmenu(ColorScheme cs) {
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
            : (track.language.isNotEmpty ? track.language : context.l10n.trackNumberLabel(track.trackIndex + 1));
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
            widget.videoController?.selectAudioTrack(track.groupIndex, track.trackIndex);
            setState(() => _sheetPage = 'main');
          },
        );
      }).toList(),
    );
  }

Widget _buildSegmentedBar<T>({
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

  Widget _buildSubtitleTrackSubmenu(ColorScheme cs) {
    final tracks = widget.videoController?.subtitleTracks ?? [];
    final hasActiveSelection = tracks.any((t) => t.isSelected);
    final isOff = !_currentSubtitlesEnabled || (!hasActiveSelection && !widget.hasSubtitles);

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
                options: sizeOptions,
                selectedValue: _currentSubtitleFontSize,
                isValueEqual: (a, b) => (a - b).abs() < 0.5,
                onSelected: (val) {
                  setState(() => _currentSubtitleFontSize = val);
                  widget.onSubtitleFontSizeChanged(val);
                },
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
                options: positionOptions,
                selectedValue: _currentSubtitleVerticalPosition,
                isValueEqual: (a, b) => (a - b).abs() < 0.18,
                onSelected: (val) {
                  setState(() => _currentSubtitleVerticalPosition = val);
                  widget.onSubtitleVerticalPositionChanged(val);
                },
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
            widget.videoController?.disableSubtitleTrack();
            setState(() {
              _currentSubtitlesEnabled = false;
              _sheetPage = 'main';
            });
            widget.onSubtitlesEnabledChanged(false);
          },
        ),
        if (widget.hasSubtitles)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              context.l10n.externalSubtitlesLabel,
              style: TextStyle(
                color: _currentSubtitlesEnabled && !hasActiveSelection ? cs.primary : null,
                fontWeight: _currentSubtitlesEnabled && !hasActiveSelection ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            trailing: _currentSubtitlesEnabled && !hasActiveSelection
                ? Icon(Icons.check_rounded, color: cs.primary, size: 18)
                : const SizedBox(width: 18),
            onTap: () {
              HapticFeedback.lightImpact();
              widget.videoController?.disableSubtitleTrack();
              setState(() {
                _currentSubtitlesEnabled = true;
                _sheetPage = 'main';
              });
              widget.onSubtitlesEnabledChanged(true);
            },
          ),
        ...tracks.map((track) {
          final label = track.label.isNotEmpty
              ? track.label
              : (track.language.isNotEmpty ? track.language : context.l10n.subtitleTrackNumberLabel(track.trackIndex + 1));
          final isSelected = track.isSelected && _currentSubtitlesEnabled;
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
              widget.videoController?.selectSubtitleTrack(track.groupIndex, track.trackIndex);
              setState(() {
                _currentSubtitlesEnabled = true;
                _sheetPage = 'main';
              });
              widget.onSubtitlesEnabledChanged(true);
            },
          );
        }),
      ],
    );
  }
}