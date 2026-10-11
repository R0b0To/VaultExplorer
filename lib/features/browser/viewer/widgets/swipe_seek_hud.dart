import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';

/// The HUD shown in the center of the video / audio playback area while the
/// user is swiping horizontally to seek.
class SwipeSeekHud extends StatelessWidget {
  final Duration targetPosition;
  final Duration totalDuration;
  final Duration delta;
  final bool showMilliseconds;

  const SwipeSeekHud({
    super.key,
    required this.targetPosition,
    required this.totalDuration,
    required this.delta,
    this.showMilliseconds = false,
  });

  @override
  Widget build(BuildContext context) {
    final isForward = !delta.isNegative;
    final sign = isForward ? '+' : '-';
    final deltaText =
        '$sign${formatClockDuration(delta.abs(), showMilliseconds: showMilliseconds)}';
    final posText = formatClockDuration(
      targetPosition,
      showMilliseconds: showMilliseconds,
    );
    final totalText = formatClockDuration(
      totalDuration,
      showMilliseconds: showMilliseconds,
    );
    final progressFactor = totalDuration.inMilliseconds > 0
        ? (targetPosition.inMilliseconds / totalDuration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Center(
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isForward
                        ? Icons.fast_forward_rounded
                        : Icons.fast_rewind_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    deltaText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '$posText / $totalText',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: 120,
                height: 3,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: progressFactor,
                    backgroundColor: Colors.white24,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
