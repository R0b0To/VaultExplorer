import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';

/// Full-screen touch shield shown while the media viewer's controls are
/// locked (the "screen lock" of video players).
///
/// Every touch is swallowed here, so nothing underneath -- the media, its
/// gestures, the top and bottom bars -- can react to a stray tap, swipe or
/// pinch. A touch only reveals a lock button for a few seconds; the controls
/// come back when that button is pressed and held for [holdDuration]. A plain
/// tap is not enough, which is the point: it is the misstap this guards
/// against.
class MediaViewerLockOverlay extends StatefulWidget {
  const MediaViewerLockOverlay({
    super.key,
    required this.onUnlock,
    this.nudge,
  });

  /// Called once, when the lock button has been held long enough.
  final VoidCallback onUnlock;

  /// When this notifies (the back button was pressed, say) the lock button is
  /// revealed, the same as for a touch.
  final Listenable? nudge;

  /// How long the lock button must stay pressed to unlock.
  static const Duration holdDuration = Duration(milliseconds: 700);

  /// How long the lock button stays visible after the last touch.
  static const Duration hintDuration = Duration(seconds: 3);

  @override
  State<MediaViewerLockOverlay> createState() => _MediaViewerLockOverlayState();
}

class _MediaViewerLockOverlayState extends State<MediaViewerLockOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _hold;
  Timer? _hintTimer;
  bool _hintVisible = true;
  bool _unlocked = false;
  int? _holdPointer;

  @override
  void initState() {
    super.initState();
    _hold =
        AnimationController(
          vsync: this,
          duration: MediaViewerLockOverlay.holdDuration,
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed) _finishUnlock();
        });
    widget.nudge?.addListener(_showHint);
    // The lock button is shown right away so it is clear how to get out.
    _startHintTimer();
  }

  @override
  void didUpdateWidget(MediaViewerLockOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nudge != widget.nudge) {
      oldWidget.nudge?.removeListener(_showHint);
      widget.nudge?.addListener(_showHint);
    }
  }

  @override
  void dispose() {
    widget.nudge?.removeListener(_showHint);
    _hintTimer?.cancel();
    _hold.dispose();
    super.dispose();
  }

  void _startHintTimer() {
    _hintTimer?.cancel();
    _hintTimer = Timer(MediaViewerLockOverlay.hintDuration, () {
      if (mounted && _holdPointer == null) {
        setState(() => _hintVisible = false);
      }
    });
  }

  void _showHint() {
    if (!mounted || _unlocked) return;
    if (!_hintVisible) setState(() => _hintVisible = true);
    // While the button is held it must not fade out from under the finger.
    if (_holdPointer == null) _startHintTimer();
  }

  void _onHoldStart(PointerDownEvent event) {
    if (_holdPointer != null || _unlocked) return;
    _holdPointer = event.pointer;
    _hintTimer?.cancel();
    HapticFeedback.selectionClick();
    _hold.forward(from: 0.0);
  }

  void _onHoldEnd(PointerEvent event) {
    if (event.pointer != _holdPointer) return;
    _holdPointer = null;
    if (_unlocked) return;
    _hold.reverse();
    _startHintTimer();
  }

  void _finishUnlock() {
    if (_unlocked) return;
    _unlocked = true;
    _holdPointer = null;
    _hintTimer?.cancel();
    HapticFeedback.mediumImpact();
    widget.onUnlock();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => _showHint(),
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.only(bottom: 40.0 + bottomInset),
                // A hidden button can't be hit, so the first touch only ever
                // reveals it.
                child: IgnorePointer(
                  ignoring: !_hintVisible,
                  child: AnimatedOpacity(
                    opacity: _hintVisible ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 180),
                    child: Semantics(
                      container: true,
                      button: true,
                      label: l10n.mediaViewerHoldToUnlock,
                      onLongPress: _finishUnlock,
                      child: ExcludeSemantics(
                        child: _buildButton(l10n.mediaViewerHoldToUnlock),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildButton(String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _onHoldStart,
          onPointerUp: _onHoldEnd,
          onPointerCancel: _onHoldEnd,
          child: SizedBox(
            width: 72,
            height: 72,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withValues(alpha: 0.6),
                  ),
                  child: const Icon(
                    Icons.lock_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
                AnimatedBuilder(
                  animation: _hold,
                  builder: (context, _) => SizedBox(
                    width: 64,
                    height: 64,
                    child: CircularProgressIndicator(
                      value: _hold.value,
                      strokeWidth: 3,
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
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
