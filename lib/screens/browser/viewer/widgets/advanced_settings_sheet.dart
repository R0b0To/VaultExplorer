import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../media_viewer_constants.dart';

class AdvancedSettingsSheet extends StatefulWidget {
  final bool isImage;
  final String currentFileName;
  final int initialRotation;
  final BoxFit initialImageFit;
  final int initialSlideshowDelaySeconds;
  final double initialPlaybackSpeed;
  final bool hasSubtitles;
  final bool initialSubtitlesEnabled;

  final ValueChanged<int> onRotationChanged;
  final ValueChanged<BoxFit> onImageFitChanged;
  final ValueChanged<int> onSlideshowDelayChanged;
  final ValueChanged<double> onPlaybackSpeedChanged;
  final ValueChanged<bool> onSubtitlesEnabledChanged;

  const AdvancedSettingsSheet({
    Key? key,
    required this.isImage,
    required this.currentFileName,
    required this.initialRotation,
    required this.initialImageFit,
    required this.initialSlideshowDelaySeconds,
    required this.initialPlaybackSpeed,
    required this.hasSubtitles,
    required this.initialSubtitlesEnabled,
    required this.onRotationChanged,
    required this.onImageFitChanged,
    required this.onSlideshowDelayChanged,
    required this.onPlaybackSpeedChanged,
    required this.onSubtitlesEnabledChanged,
  }) : super(key: key);

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

  @override
  void initState() {
    super.initState();
    _currentRotation = widget.initialRotation;
    _currentImageFit = widget.initialImageFit;
    _currentSlideshowDelaySeconds = widget.initialSlideshowDelaySeconds;
    _currentPlaybackSpeed = widget.initialPlaybackSpeed;
    _currentSubtitlesEnabled = widget.initialSubtitlesEnabled;
  }

  String _getImageFitLabel(BoxFit fit) {
    if (fit == BoxFit.contain) return 'Contain';
    if (fit == BoxFit.fitWidth) return 'Fit Width';
    if (fit == BoxFit.fitHeight) return 'Fit Height';
    return 'Contain';
  }

  Widget _buildRotationTile(ColorScheme cs) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.rotate_right_rounded),
      title: const Text('Rotate 90°'),
      trailing: Text(
        '${_currentRotation * 90}°',
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_sheetPage == 'main') ...[
                _buildHeader(cs, widget.isImage ? 'Image Settings' : 'Playback Settings', null),
                const SizedBox(height: 8),
                _buildMainPage(cs),
              ] else if (_sheetPage == 'imageFit') ...[
                _buildHeader(cs, 'Image Fit Mode', () => setState(() => _sheetPage = 'main')),
                const SizedBox(height: 8),
                _buildImageFitSubmenu(cs),
              ] else if (_sheetPage == 'slideshowDelay') ...[
                _buildHeader(cs, 'Slideshow Delay', () => setState(() => _sheetPage = 'main')),
                const SizedBox(height: 8),
                _buildSlideshowDelaySubmenu(cs),
              ] else if (_sheetPage == 'playbackSpeed') ...[
                _buildHeader(cs, 'Playback Speed', () => setState(() => _sheetPage = 'main')),
                const SizedBox(height: 8),
                _buildPlaybackSpeedSubmenu(cs),
              ],
            ],
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
            title: const Text('Image Fit Mode'),
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
          const Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.timer_outlined),
            title: const Text('Slideshow Delay'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${_currentSlideshowDelaySeconds}s',
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
            title: const Text('Playback Speed'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${_currentPlaybackSpeed}x',
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
          if (widget.hasSubtitles) ...[
            const Divider(),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.subtitles_rounded),
              title: const Text('Subtitles'),
              value: _currentSubtitlesEnabled,
              activeColor: cs.primary,
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
              : null,
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
            '${delay} seconds',
            style: TextStyle(
              color: isSelected ? cs.primary : null,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          trailing: isSelected
              ? Icon(Icons.check_rounded, color: cs.primary, size: 18)
              : null,
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
            '${speed}x${speed == 1.0 ? " (Normal)" : ""}',
            style: TextStyle(
              color: isSelected ? cs.primary : null,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          trailing: isSelected
              ? Icon(Icons.check_rounded, color: cs.primary, size: 18)
              : null,
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
}