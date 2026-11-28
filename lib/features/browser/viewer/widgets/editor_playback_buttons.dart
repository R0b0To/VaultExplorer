import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';

/// Mute toggle shared by the audio and video editors: a square transport-row
/// button of [box] size that is tinted while [muted].
class EditorMuteButton extends StatelessWidget {
  const EditorMuteButton({
    super.key,
    required this.muted,
    required this.onToggle,
    required this.box,
    required this.iconSize,
  });

  final bool muted;
  final VoidCallback onToggle;
  final double box;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = context.colors;
    return IconButton.filledTonal(
      style: IconButton.styleFrom(
        minimumSize: Size(box, box),
        padding: EdgeInsets.zero,
        backgroundColor: muted ? cs.primaryContainer : null,
        foregroundColor: muted ? cs.onPrimaryContainer : null,
      ),
      iconSize: iconSize,
      tooltip: muted ? l10n.unmuteTooltip : l10n.muteTooltip,
      icon: Icon(muted ? Icons.volume_off_rounded : Icons.volume_up_rounded),
      onPressed: onToggle,
    );
  }
}

/// Playback-speed picker shared by the audio and video editors: a pill that
/// shows the current [speed] and opens a menu of
/// [MediaViewerConstants.playbackSpeeds].
class EditorSpeedButton extends StatelessWidget {
  const EditorSpeedButton({
    super.key,
    required this.speed,
    required this.onSelected,
  });

  final double speed;
  final ValueChanged<double> onSelected;

  static String _speedValue(double speed) {
    final value = speed.toString();
    return value.endsWith('.0') ? value.substring(0, value.length - 2) : value;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = context.colors;
    return PopupMenuButton<double>(
      tooltip: l10n.playbackSpeedLabel,
      initialValue: speed,
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final option in MediaViewerConstants.playbackSpeeds)
          PopupMenuItem<double>(
            value: option,
            child: Text(
              option == 1.0
                  ? l10n.playbackSpeedNormal(_speedValue(option))
                  : l10n.playbackSpeedValue(_speedValue(option)),
            ),
          ),
      ],
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: speed == 1.0
              ? cs.surfaceContainerHighest
              : cs.primaryContainer,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.speed_rounded,
              size: 18,
              color: speed == 1.0 ? cs.onSurfaceVariant : cs.onPrimaryContainer,
            ),
            const SizedBox(width: 4),
            Text(
              '${_speedValue(speed)}×',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: speed == 1.0
                    ? cs.onSurfaceVariant
                    : cs.onPrimaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
