import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';

/// A minimalist seek HUD shown in the center of the video / audio playback area
/// while the user is swiping horizontally to seek.
///
/// Designed to disrupt the view minimally: renders just a bold white text
/// with a drop shadow, without any background container, icons, or progress bars.
class SwipeSeekHud extends StatelessWidget {
  final Duration targetPosition;
  final Duration totalDuration;
  final Duration? delta;
  final bool showMilliseconds;

  const SwipeSeekHud({
    super.key,
    required this.targetPosition,
    required this.totalDuration,
    this.delta,
    this.showMilliseconds = false,
  });

  @override
  Widget build(BuildContext context) {
    final posText = formatClockDuration(
      targetPosition,
      showMilliseconds: showMilliseconds,
    );
    final totalText = formatClockDuration(
      totalDuration,
      showMilliseconds: showMilliseconds &&
          (totalDuration < const Duration(seconds: 10) ||
              totalDuration.inMilliseconds % 1000 != 0),
    );
    final displayText = totalDuration > Duration.zero
        ? '$posText / $totalText'
        : posText;

    return Center(
      child: IgnorePointer(
        child: Text(
          displayText,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
            shadows: [
              Shadow(
                blurRadius: 6,
                color: Colors.black,
                offset: Offset(0, 1),
              ),
              Shadow(
                blurRadius: 12,
                color: Colors.black87,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
