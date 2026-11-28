import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/data/models/media_viewer_action.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/media_viewer_action_button.dart';

/// The volume control of a desktop media viewer: the speaker button (it mutes
/// and unmutes) with a slider that slides out beside it while the pointer is
/// over the control or the slider is being dragged. The mouse wheel over the
/// control steps the volume too.
class MediaViewerVolumeControl extends StatefulWidget {
  const MediaViewerVolumeControl({
    super.key,
    required this.level,
    required this.isMuted,
    required this.onToggleMute,
    required this.onChanged,
    this.onInteraction,
    this.buttonSize = 32,
    this.iconSize = 18,
  });

  /// The volume, 0-100, without regard to mute.
  final ValueListenable<int> level;
  final bool isMuted;
  final VoidCallback onToggleMute;

  /// The person set the volume with the pointer.
  final ValueChanged<int> onChanged;

  /// Any use of the control, so the viewer keeps its controls on screen.
  final VoidCallback? onInteraction;
  final double buttonSize;
  final double iconSize;

  static const double _sliderWidth = 96;
  static const int _wheelStep = 5;

  @override
  State<MediaViewerVolumeControl> createState() =>
      _MediaViewerVolumeControlState();
}

class _MediaViewerVolumeControlState extends State<MediaViewerVolumeControl> {
  bool _hovering = false;
  bool _dragging = false;

  bool get _expanded => _hovering || _dragging;

  IconData _icon(int effective) {
    if (effective == 0) return Icons.volume_off_rounded;
    if (effective < 34) return Icons.volume_mute_rounded;
    if (effective < 67) return Icons.volume_down_rounded;
    return Icons.volume_up_rounded;
  }

  void _onWheel(PointerSignalEvent event, int effective) {
    if (event is! PointerScrollEvent) return;
    widget.onInteraction?.call();
    // Wheel up (negative dy) raises the volume.
    final step = event.scrollDelta.dy < 0
        ? MediaViewerVolumeControl._wheelStep
        : -MediaViewerVolumeControl._wheelStep;
    widget.onChanged((effective + step).clamp(0, 100));
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: widget.level,
      builder: (context, level, _) {
        final effective = widget.isMuted ? 0 : level;
        return MouseRegion(
          onEnter: (_) => setState(() => _hovering = true),
          onExit: (_) => setState(() => _hovering = false),
          child: Listener(
            onPointerSignal: (event) => _onWheel(event, effective),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                MediaViewerActionButton(
                  action: MediaViewerAction.mute,
                  size: widget.buttonSize,
                  iconSize: widget.iconSize,
                  isHighlighted: widget.isMuted,
                  highlightColor: Theme.of(context).colorScheme.error,
                  customIcon: _icon(effective),
                  onTap: widget.onToggleMute,
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOut,
                  width: _expanded ? MediaViewerVolumeControl._sliderWidth : 0,
                  // A fixed height: the OverflowBox below takes the largest
                  // size it is allowed, which in a toolbar row is infinite.
                  height: widget.buttonSize,
                  clipBehavior: Clip.hardEdge,
                  decoration: const BoxDecoration(),
                  child: OverflowBox(
                    alignment: Alignment.centerLeft,
                    minWidth: MediaViewerVolumeControl._sliderWidth,
                    maxWidth: MediaViewerVolumeControl._sliderWidth,
                    minHeight: widget.buttonSize,
                    maxHeight: widget.buttonSize,
                    // Keyboard focus stays with the viewer, whose arrow keys
                    // already change the volume.
                    child: Focus(
                      canRequestFocus: false,
                      descendantsAreFocusable: false,
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3,
                          activeTrackColor: Colors.white,
                          inactiveTrackColor: Colors.white24,
                          thumbColor: Colors.white,
                          overlayColor: Colors.white12,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 5,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 12,
                          ),
                          trackShape: const RoundedRectSliderTrackShape(),
                        ),
                        child: Slider(
                          min: 0,
                          max: 100,
                          value: effective.toDouble(),
                          onChangeStart: (_) {
                            widget.onInteraction?.call();
                            setState(() => _dragging = true);
                          },
                          onChanged: (v) {
                            widget.onInteraction?.call();
                            widget.onChanged(v.round());
                          },
                          onChangeEnd: (_) => setState(() => _dragging = false),
                        ),
                      ),
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
}
