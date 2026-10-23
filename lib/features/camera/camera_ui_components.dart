import 'dart:async';
import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'vault_camera_controller.dart' show NativeCameraLens;

class CameraPopupMenuItem<T> {
  final T value;
  final Widget child;
  final bool isSelected;

  const CameraPopupMenuItem({
    required this.value,
    required this.child,
    this.isSelected = false,
  });
}

class CameraPopupMenuButton<T> extends StatefulWidget {
  final ValueChanged<T> onSelected;
  final List<CameraPopupMenuItem<T>> items;
  final Widget child;
  final double iconTurns;

  const CameraPopupMenuButton({
    super.key,
    required this.onSelected,
    required this.items,
    required this.child,
    required this.iconTurns,
  });

  @override
  State<CameraPopupMenuButton<T>> createState() => _CameraPopupMenuButtonState<T>();
}

class _CameraPopupMenuButtonState<T> extends State<CameraPopupMenuButton<T>> {
  _CameraPopupMenuRoute<T>? _activeRoute;

  @override
  void didUpdateWidget(covariant CameraPopupMenuButton<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.iconTurns - widget.iconTurns).abs() > 0.01) {
      if (_activeRoute != null && _activeRoute!.isActive) {
        if (_activeRoute!.isCurrent) {
          _activeRoute!.navigator?.pop();
        } else {
          _activeRoute!.navigator?.removeRoute(_activeRoute!);
        }
        _activeRoute = null;
      }
    }
  }

  @override
  void dispose() {
    if (_activeRoute != null && _activeRoute!.isActive) {
      _activeRoute!.navigator?.removeRoute(_activeRoute!);
      _activeRoute = null;
    }
    super.dispose();
  }

  void _showMenu() {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;

    final buttonRect = renderBox.localToGlobal(Offset.zero) & renderBox.size;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    final screenSize = overlay?.size ?? MediaQuery.of(context).size;

    final route = _CameraPopupMenuRoute<T>(
      buttonRect: buttonRect,
      screenSize: screenSize,
      items: widget.items,
      iconTurns: widget.iconTurns,
      onSelected: widget.onSelected,
    );

    _activeRoute = route;
    Navigator.of(context).push(route).then((_) {
      if (_activeRoute == route) {
        _activeRoute = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _showMenu,
      child: widget.child,
    );
  }
}

class _CameraPopupMenuRoute<T> extends PopupRoute<void> {
  final Rect buttonRect;
  final Size screenSize;
  final List<CameraPopupMenuItem<T>> items;
  final double iconTurns;
  final ValueChanged<T> onSelected;

  _CameraPopupMenuRoute({
    required this.buttonRect,
    required this.screenSize,
    required this.items,
    required this.iconTurns,
    required this.onSelected,
  });

  @override
  Duration get transitionDuration => const Duration(milliseconds: 150);

  @override
  bool get barrierDismissible => true;

  @override
  Color? get barrierColor => Colors.black26;

  @override
  String? get barrierLabel => 'Dismiss';

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: child,
    );
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final menuContent = Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(minWidth: 100),
        decoration: BoxDecoration(
          color: const Color(0xEB1E1E1E),
          borderRadius: BorderRadius.circular(12),
          
          boxShadow: const [
            BoxShadow(
              color: Colors.black54,
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: IntrinsicWidth(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (int i = 0; i < items.length; i++) ...[
                  if (i > 0)
                    const Divider(color: Colors.white12, height: 1, thickness: 0.5),
                  InkWell(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      Navigator.of(context).pop();
                      onSelected(items[i].value);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      color: items[i].isSelected
                          ? const Color(0x26FFC107)
                          : Colors.transparent,
                      child: Center(
                        child: items[i].child,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    return CustomSingleChildLayout(
      delegate: _CameraPopupMenuLayoutDelegate(
        buttonRect: buttonRect,
        screenSize: screenSize,
        iconTurns: iconTurns,
      ),
      child: buildRotatedWidget(
        iconTurns: iconTurns,
        child: menuContent,
      ),
    );
  }
}

class _CameraPopupMenuLayoutDelegate extends SingleChildLayoutDelegate {
  final Rect buttonRect;
  final Size screenSize;
  final double iconTurns;

  _CameraPopupMenuLayoutDelegate({
    required this.buttonRect,
    required this.screenSize,
    required this.iconTurns,
  });

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return constraints.loosen();
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final angle = iconTurns * 2 * math.pi;
    final cosA = math.cos(angle).abs();
    final sinA = math.sin(angle).abs();

    final visualWidth = childSize.width * cosA + childSize.height * sinA;
    final visualHeight = childSize.width * sinA + childSize.height * cosA;

    final targetCx = buttonRect.center.dx;
    final targetCy = buttonRect.bottom + 8.0 + visualHeight / 2.0;

    final minCx = visualWidth / 2.0 + 8.0;
    final maxCx = size.width - visualWidth / 2.0 - 8.0;
    final clampedCx = minCx <= maxCx ? targetCx.clamp(minCx, maxCx) : size.width / 2.0;

    final minCy = buttonRect.bottom + 4.0 + visualHeight / 2.0;
    final maxCy = size.height - visualHeight / 2.0 - 8.0;
    final clampedCy = minCy <= maxCy ? targetCy.clamp(minCy, maxCy) : size.height / 2.0;

    return Offset(
      clampedCx - childSize.width / 2.0,
      clampedCy - childSize.height / 2.0,
    );
  }

  @override
  bool shouldRelayout(_CameraPopupMenuLayoutDelegate oldDelegate) {
    return buttonRect != oldDelegate.buttonRect ||
        screenSize != oldDelegate.screenSize ||
        iconTurns != oldDelegate.iconTurns;
  }
}

/// Clockwise quarter-turns that bring the camera preview upright.
///
/// The preview texture is delivered upright for the device's *natural*
/// orientation (Android rotates the sensor buffer by SENSOR_ORIENTATION), so
/// when the display is rotated ([displayRotation] = `Surface.ROTATION_*` as
/// 0..3, "graphics rotated clockwise by N * 90 degrees") the texture has to be
/// rotated back by the same amount, counter-clockwise.
int cameraPreviewQuarterTurns(int displayRotation) =>
    (4 - (displayRotation % 4)) % 4;

/// Converts a point normalized (0..1) in the *displayed* frame into the
/// natural-orientation frame that native focus/metering expects.
({double x, double y}) cameraDisplayPointToNatural(
  double x,
  double y,
  int displayRotation,
) {
  switch (displayRotation % 4) {
    case 1:
      return (x: 1 - y, y: x);
    case 2:
      return (x: 1 - x, y: 1 - y);
    case 3:
      return (x: y, y: 1 - x);
    default:
      return (x: x, y: y);
  }
}

/// Turns (for [buildRotatedWidget]) that keep overlay icons upright.
///
/// [deviceTurns] is the physical device rotation from the accelerometer
/// (0, 0.25, 0.5, -0.25). Whatever part of that rotation the OS already
/// applied to the UI ([displayRotation]) must not be applied a second time.
double cameraIconTurns({
  required double deviceTurns,
  required int displayRotation,
}) {
  final deviceQuarters = (deviceTurns * 4).round();
  final q = (((deviceQuarters - displayRotation) % 4) + 4) % 4;
  switch (q) {
    case 1:
      return 0.25;
    case 2:
      return 0.5;
    case 3:
      return -0.25;
    default:
      return 0.0;
  }
}

/// Camera preview cropped to [frameAspectRatio] (width / height of the
/// visible frame), rotated to match the current display rotation.
class CameraPreviewView extends StatelessWidget {
  final int textureId;
  final int previewWidth;
  final int previewHeight;
  final int sensorOrientation;
  final int displayRotation;
  final double frameAspectRatio;
  final bool showShutterFlash;

  const CameraPreviewView({
    super.key,
    required this.textureId,
    required this.previewWidth,
    required this.previewHeight,
    required this.sensorOrientation,
    required this.displayRotation,
    required this.frameAspectRatio,
    this.showShutterFlash = false,
  });

  @override
  Widget build(BuildContext context) {
    // Size of the texture as it arrives: already turned upright for the
    // natural orientation, hence width/height swap for 90/270 sensors.
    final swap = sensorOrientation % 180 != 0;
    final naturalW = (swap ? previewHeight : previewWidth).toDouble();
    final naturalH = (swap ? previewWidth : previewHeight).toDouble();

    final turns = cameraPreviewQuarterTurns(displayRotation);
    final odd = turns.isOdd;

    return AspectRatio(
      aspectRatio: frameAspectRatio,
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: odd ? naturalH : naturalW,
                height: odd ? naturalW : naturalH,
                child: RotatedBox(
                  quarterTurns: turns,
                  child: Texture(textureId: textureId),
                ),
              ),
            ),
            AnimatedOpacity(
              opacity: showShutterFlash ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 50),
              child: const ColoredBox(color: Colors.black),
            ),
          ],
        ),
      ),
    );
  }
}

Widget buildRotatedWidget({required double iconTurns, required Widget child}) {
  return AnimatedRotation(
    turns: iconTurns,
    alignment: Alignment.center,
    duration: const Duration(milliseconds: 350),
    curve: Curves.easeOutBack,
    child: child,
  );
}

class CameraTopControlsBar extends StatelessWidget {
  final bool isVideoMode;
  final bool isRecording;
  final bool isCountingDown;
  final String timerText;
  final String videoQuality;
  final String photoResolution;
  final Map<String, String> photoResolutions;
  final Map<String, String> videoQualities;
  final String? currentPhotoResolution;
  final String? currentVideoResolution;
  final double selectedAspectRatio;
  final ValueChanged<double> onAspectRatioChanged;
  final int timerDelaySeconds;
  final String flashMode;

  /// False for cameras without a flash unit (most front cameras): the flash
  /// button is hidden instead of silently doing nothing.
  final bool hasFlash;
  final double iconTurns;
  final VoidCallback onClose;
  final ValueChanged<String> onVideoQualityChanged;
  final ValueChanged<String> onPhotoResolutionChanged;
  final VoidCallback onCycleTimerDelay;
  final VoidCallback onCycleFlashMode;

  const CameraTopControlsBar({
    super.key,
    required this.isVideoMode,
    required this.isRecording,
    required this.isCountingDown,
    required this.timerText,
    required this.videoQuality,
    required this.photoResolution,
    this.photoResolutions = const {},
    this.videoQualities = const {},
    this.currentPhotoResolution,
    this.currentVideoResolution,
    required this.selectedAspectRatio,
    required this.onAspectRatioChanged,
    required this.timerDelaySeconds,
    required this.flashMode,
    this.hasFlash = true,
    required this.iconTurns,
    required this.onClose,
    required this.onVideoQualityChanged,
    required this.onPhotoResolutionChanged,
    required this.onCycleTimerDelay,
    required this.onCycleFlashMode,
  });

  String _formatVideoResolution(String quality) {
    final exact = videoQualities[quality];
    if (exact != null && exact.isNotEmpty) return exact;
    if (quality == videoQuality &&
        currentVideoResolution != null &&
        currentVideoResolution!.isNotEmpty) {
      return currentVideoResolution!;
    }
    return switch (quality) {
      'uhd' => '3840x2160',
      'fhd' => '1920x1080',
      'hd' => '1280x720',
      'sd' => '720x480',
      _ => quality.toUpperCase(),
    };
  }


  /// The tiers the camera reports, largest first. The native side leaves out a
  /// tier that would repeat another one's size; before it has reported
  /// anything, all four are listed.
  List<String> get _photoResolutionKeys {
    const order = ['max', 'high', 'med', 'low'];
    if (photoResolutions.isEmpty) return order;
    final available = [
      for (final key in order)
        if (photoResolutions.containsKey(key)) key,
    ];
    return available.isEmpty ? order : available;
  }

  String _formatPhotoResolution(String res) {
    final exact = photoResolutions[res];
    if (exact != null && exact.isNotEmpty) return exact;
    if (res == photoResolution &&
        currentPhotoResolution != null &&
        currentPhotoResolution!.isNotEmpty) {
      return currentPhotoResolution!;
    }
    return switch (res) {
      'max' => '4000x3000',
      'high' => '2560x1920',
      'med' => '1920x1440',
      'low' => '1280x960',
      _ => res.toUpperCase(),
    };
  }

  @override
  Widget build(BuildContext context) {

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black54, Colors.transparent],
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SafeArea(
        bottom: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            buildRotatedWidget(
              iconTurns: iconTurns,
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                onPressed: onClose,
              ),
            ),
            if (isRecording || isCountingDown)
              buildRotatedWidget(
                iconTurns: iconTurns,
                child: Text(
                  timerText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            else
              Row(
                children: [
                  // Aspect Ratio Selector
                  CameraPopupMenuButton<double>(
                    iconTurns: iconTurns,
                    onSelected: onAspectRatioChanged,
                    items: [
                      CameraPopupMenuItem(
                        value: 4 / 3,
                        isSelected: (selectedAspectRatio - 4 / 3).abs() < 0.05,
                        child: Text(
                          '4:3',
                          style: TextStyle(
                            color: (selectedAspectRatio - 4 / 3).abs() < 0.05 ? Colors.amber : Colors.white,
                            fontWeight: (selectedAspectRatio - 4 / 3).abs() < 0.05 ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                      CameraPopupMenuItem(
                        value: 16 / 9,
                        isSelected: (selectedAspectRatio - 16 / 9).abs() < 0.05,
                        child: Text(
                          '16:9',
                          style: TextStyle(
                            color: (selectedAspectRatio - 16 / 9).abs() < 0.05 ? Colors.amber : Colors.white,
                            fontWeight: (selectedAspectRatio - 16 / 9).abs() < 0.05 ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                      CameraPopupMenuItem(
                        value: 1.0,
                        isSelected: (selectedAspectRatio - 1.0).abs() < 0.05,
                        child: Text(
                          '1:1',
                          style: TextStyle(
                            color: (selectedAspectRatio - 1.0).abs() < 0.05 ? Colors.amber : Colors.white,
                            fontWeight: (selectedAspectRatio - 1.0).abs() < 0.05 ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                    ],
                    child: Padding(
                      padding: const EdgeInsets.all(6.0),
                      child: buildRotatedWidget(
                        iconTurns: iconTurns,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            color: Colors.black45,
                            border: Border.all(color: Colors.white30),
                          ),
                          child: Text(
                            (selectedAspectRatio - 4 / 3).abs() < 0.05
                                ? '4:3'
                                : (selectedAspectRatio - 16 / 9).abs() < 0.05
                                    ? '16:9'
                                    : '1:1',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Video Mode Resolution Menu
                  if (isVideoMode)
                    CameraPopupMenuButton<String>(
                      iconTurns: iconTurns,
                      onSelected: onVideoQualityChanged,
                      items: [
                        for (final q in const ['uhd', 'fhd', 'hd', 'sd'])
                          CameraPopupMenuItem(
                            value: q,
                            isSelected: videoQuality == q,
                            child: Text(
                              _formatVideoResolution(q),
                              style: TextStyle(
                                color: videoQuality == q ? Colors.amber : Colors.white,
                                fontWeight: videoQuality == q ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ),
                      ],
                      child: Padding(
                        padding: const EdgeInsets.all(6.0),
                        child: buildRotatedWidget(
                          iconTurns: iconTurns,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: Colors.black45,
                              border: Border.all(color: Colors.white30),
                            ),
                            child: Text(
                              _formatVideoResolution(videoQuality),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                            ),
                          ),
                        ),
                      ),
                    )
                  // Photo Mode Resolution Menu
                  else
                    CameraPopupMenuButton<String>(
                      iconTurns: iconTurns,
                      onSelected: onPhotoResolutionChanged,
                      items: [
                        for (final r in _photoResolutionKeys)
                          CameraPopupMenuItem(
                            value: r,
                            isSelected: photoResolution == r,
                            child: Text(
                              _formatPhotoResolution(r),
                              style: TextStyle(
                                color: photoResolution == r ? Colors.amber : Colors.white,
                                fontWeight: photoResolution == r ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ),
                      ],
                      child: Padding(
                        padding: const EdgeInsets.all(6.0),
                        child: buildRotatedWidget(
                          iconTurns: iconTurns,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: Colors.black45,
                              border: Border.all(color: Colors.white30),
                            ),
                            child: Text(
                              _formatPhotoResolution(photoResolution),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                            ),
                          ),
                        ),
                      ),
                    ),

                  if (!isVideoMode) ...[
                    buildRotatedWidget(
                      iconTurns: iconTurns,
                      child: IconButton(
                        icon: Icon(
                          timerDelaySeconds == 3
                              ? Icons.timer_3_rounded
                              : timerDelaySeconds == 10
                              ? Icons.timer_10_rounded
                              : Icons.timer_off_rounded,
                          color: timerDelaySeconds > 0 ? Colors.amber : Colors.white,
                        ),
                        onPressed: onCycleTimerDelay,
                      ),
                    ),
                  ],
                  // Photo: auto / on / off. Video: torch on / off.
                  if (hasFlash)
                    buildRotatedWidget(
                      iconTurns: iconTurns,
                      child: IconButton(
                        icon: Icon(
                          flashMode == 'auto'
                              ? Icons.flash_auto_rounded
                              : (flashMode == 'on' || flashMode == 'torch')
                              ? Icons.flash_on_rounded
                              : Icons.flash_off_rounded,
                          color: flashMode == 'off' ? Colors.white : Colors.amber,
                        ),
                        onPressed: onCycleFlashMode,
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// "1x", "2.3x", "0.5x" -- whole values without a decimal.
String formatCameraZoom(double zoom) {
  final rounded = (zoom * 10).round() / 10;
  return rounded == rounded.roundToDouble()
      ? '${rounded.round()}x'
      : '${rounded.toStringAsFixed(1)}x';
}

/// Single pill showing the live zoom level. Follows pinch zoom; tapping it
/// jumps back to 1x.
class CameraZoomIndicator extends StatelessWidget {
  final double currentZoom;
  final double minZoom;
  final double maxZoom;
  final double iconTurns;
  final Future<void> Function(double zoom) onSetZoom;

  const CameraZoomIndicator({
    super.key,
    required this.currentZoom,
    required this.minZoom,
    required this.maxZoom,
    required this.iconTurns,
    required this.onSetZoom,
  });

  @override
  Widget build(BuildContext context) {
    // No zoom range (fixed-focal-length camera): nothing worth showing.
    if (maxZoom - minZoom < 0.05) return const SizedBox.shrink();

    final atOneX = (currentZoom - 1.0).abs() < 0.05;

    return Center(
      child: GestureDetector(
        onTap: () async {
          HapticFeedback.selectionClick();
          await onSetZoom(1.0.clamp(minZoom, maxZoom));
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: atOneX ? Colors.black45 : Colors.amber,
          ),
          child: buildRotatedWidget(
            iconTurns: iconTurns,
            child: Text(
              formatCameraZoom(currentZoom),
              style: TextStyle(
                color: atOneX ? Colors.white : Colors.black,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Lens picker (0.5x / 1x / 3x ...) for cameras with more than one lens. The
/// active stop shows the live zoom (follows pinch zoom); the others jump to
/// their lens when tapped.
class CameraLensSelector extends StatelessWidget {
  final List<NativeCameraLens> stops;
  final String selectedCameraId;

  /// Zoom as the user reads it (zoom ratio x the lens' intrinsic ratio).
  final double displayZoom;
  final double iconTurns;
  final Future<void> Function(NativeCameraLens stop) onSelect;

  const CameraLensSelector({
    super.key,
    required this.stops,
    required this.selectedCameraId,
    required this.displayZoom,
    required this.iconTurns,
    required this.onSelect,
  });

  /// The stop whose field of view is closest (in log space) to what is shown.
  int _activeIndex() {
    final shown = math.log(displayZoom.clamp(0.1, 100.0));
    var best = 0;
    var bestDistance = double.infinity;
    for (var i = 0; i < stops.length; i++) {
      final d = (math.log(stops[i].relativeZoom.clamp(0.1, 100.0)) - shown).abs();
      if (d < bestDistance) {
        bestDistance = d;
        best = i;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final active = _activeIndex();

    return Center(
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: Colors.black45,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < stops.length; i++)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: i == active ? null : () => onSelect(stops[i]),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  constraints: const BoxConstraints(minWidth: 38, minHeight: 34),
                  alignment: Alignment.center,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    color: i == active ? Colors.amber : Colors.transparent,
                  ),
                  child: buildRotatedWidget(
                    iconTurns: iconTurns,
                    child: Text(
                      i == active ? formatCameraZoom(displayZoom) : stops[i].displayName,
                      style: TextStyle(
                        color: i == active ? Colors.black : Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
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
}

class CameraFocusExposureOverlay extends StatelessWidget {
  final Offset? focusPoint;
  final bool showExposureSlider;
  final double currentExposureEv;
  final double minExposureEv;
  final double maxExposureEv;
  final ValueChanged<double> onExposureChanged;

  const CameraFocusExposureOverlay({
    super.key,
    required this.focusPoint,
    required this.showExposureSlider,
    required this.currentExposureEv,
    required this.minExposureEv,
    required this.maxExposureEv,
    required this.onExposureChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (!showExposureSlider || focusPoint == null) return const SizedBox.shrink();

    return Stack(
      children: [
        Positioned(
          left: focusPoint!.dx - 30,
          top: focusPoint!.dy - 30,
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.amber, width: 1.5),
            ),
          ),
        ),
        if (minExposureEv < maxExposureEv)
          Positioned(
            right: 16,
            top: MediaQuery.of(context).size.height * 0.3,
            child: RotatedBox(
              quarterTurns: 3,
              child: SizedBox(
                width: MediaQuery.of(context).size.height * 0.4,
                child: Slider(
                  value: currentExposureEv,
                  min: minExposureEv,
                  max: maxExposureEv,
                  activeColor: Colors.amber,
                  onChanged: onExposureChanged,
                ),
              ),
            ),
          ),
      ],
    );
  }
}