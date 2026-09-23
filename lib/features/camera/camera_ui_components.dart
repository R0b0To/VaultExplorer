import 'dart:async';
import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'vault_camera_controller.dart';

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
  final double selectedAspectRatio;
  final ValueChanged<double> onAspectRatioChanged;
  final int timerDelaySeconds;
  final String flashMode;
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
    required this.selectedAspectRatio,
    required this.onAspectRatioChanged,
    required this.timerDelaySeconds,
    required this.flashMode,
    required this.iconTurns,
    required this.onClose,
    required this.onVideoQualityChanged,
    required this.onPhotoResolutionChanged,
    required this.onCycleTimerDelay,
    required this.onCycleFlashMode,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

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
                        CameraPopupMenuItem(
                          value: 'sd',
                          isSelected: videoQuality == 'sd',
                          child: Text(
                            l10n.cameraQualitySd,
                            style: TextStyle(
                              color: videoQuality == 'sd' ? Colors.amber : Colors.white,
                              fontWeight: videoQuality == 'sd' ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ),
                        CameraPopupMenuItem(
                          value: 'hd',
                          isSelected: videoQuality == 'hd',
                          child: Text(
                            l10n.cameraQualityHd,
                            style: TextStyle(
                              color: videoQuality == 'hd' ? Colors.amber : Colors.white,
                              fontWeight: videoQuality == 'hd' ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ),
                        CameraPopupMenuItem(
                          value: 'fhd',
                          isSelected: videoQuality == 'fhd',
                          child: Text(
                            l10n.cameraQualityFhd,
                            style: TextStyle(
                              color: videoQuality == 'fhd' ? Colors.amber : Colors.white,
                              fontWeight: videoQuality == 'fhd' ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ),
                        CameraPopupMenuItem(
                          value: 'uhd',
                          isSelected: videoQuality == 'uhd',
                          child: Text(
                            l10n.cameraQualityUhd,
                            style: TextStyle(
                              color: videoQuality == 'uhd' ? Colors.amber : Colors.white,
                              fontWeight: videoQuality == 'uhd' ? FontWeight.bold : FontWeight.normal,
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
                              videoQuality.toUpperCase(),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
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
                        CameraPopupMenuItem(
                          value: 'max',
                          isSelected: photoResolution == 'max',
                          child: Text(
                            l10n.cameraPhotoResMax,
                            style: TextStyle(
                              color: photoResolution == 'max' ? Colors.amber : Colors.white,
                              fontWeight: photoResolution == 'max' ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ),
                        CameraPopupMenuItem(
                          value: 'high',
                          isSelected: photoResolution == 'high',
                          child: Text(
                            l10n.cameraPhotoResHigh,
                            style: TextStyle(
                              color: photoResolution == 'high' ? Colors.amber : Colors.white,
                              fontWeight: photoResolution == 'high' ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ),
                        CameraPopupMenuItem(
                          value: 'med',
                          isSelected: photoResolution == 'med',
                          child: Text(
                            l10n.cameraPhotoResMedium,
                            style: TextStyle(
                              color: photoResolution == 'med' ? Colors.amber : Colors.white,
                              fontWeight: photoResolution == 'med' ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ),
                        CameraPopupMenuItem(
                          value: 'low',
                          isSelected: photoResolution == 'low',
                          child: Text(
                            l10n.cameraPhotoResLow,
                            style: TextStyle(
                              color: photoResolution == 'low' ? Colors.amber : Colors.white,
                              fontWeight: photoResolution == 'low' ? FontWeight.bold : FontWeight.normal,
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
                              photoResolution == 'max' ? 'MAX' : photoResolution.toUpperCase(),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
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
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class CameraLensSelectorBar extends StatelessWidget {
  final List<NativeCameraLens> lenses;
  final String selectedCameraId;
  final double currentZoom;
  final double minZoom;
  final double maxZoom;
  final double iconTurns;
  final Future<void> Function(String cameraId) onSwitchLens;
  final Future<void> Function(double zoom) onSetZoom;

  const CameraLensSelectorBar({
    super.key,
    required this.lenses,
    required this.selectedCameraId,
    required this.currentZoom,
    required this.minZoom,
    required this.maxZoom,
    required this.iconTurns,
    required this.onSwitchLens,
    required this.onSetZoom,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final currentLens = lenses.firstWhere(
      (l) => l.cameraId == selectedCameraId,
      orElse: () => lenses.firstOrNull ?? const NativeCameraLens(
        cameraId: '',
        facing: 'back',
        isLogical: false,
        zoomMin: 1.0,
        zoomMax: 1.0,
      ),
    );
    final isBackCamera = currentLens.facing == 'back';

    final List<({String label, double zoom, String? switchCameraId})> options = [];

    if (isBackCamera) {
      final backLenses = lenses.where((l) => l.facing == 'back').toList();
      if (backLenses.length > 1) {
        for (final lens in backLenses) {
          final localizedLabel = switch (lens.lensType) {
            'wide' => l10n.cameraLensWide,
            'infrared' => l10n.cameraLensInfrared,
            'front' => l10n.cameraLensFront,
            _ => lens.displayName,
          };
          options.add((
            label: localizedLabel,
            zoom: 1.0,
            switchCameraId: lens.cameraId,
          ));
        }
      } else {
        if (minZoom < 0.95) {
          options.add((label: '${minZoom.toStringAsFixed(1)}x', zoom: minZoom, switchCameraId: null));
        }
        options.add((label: '1x', zoom: 1.0, switchCameraId: null));
        if (maxZoom >= 2.0 && maxZoom < 3.0) {
          options.add((label: '2x', zoom: 2.0, switchCameraId: null));
        } else if (maxZoom >= 3.0) {
          options.add((label: '3x', zoom: 3.0, switchCameraId: null));
        }
        if (maxZoom >= 5.0) {
          options.add((label: '5x', zoom: 5.0, switchCameraId: null));
        }
      }
    } else {
      options.add((label: '1x', zoom: 1.0, switchCameraId: null));
      if (maxZoom >= 2.0) {
        options.add((label: '2x', zoom: 2.0, switchCameraId: null));
      }
    }

    if (options.length <= 1) return const SizedBox.shrink();

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: options.map((option) {
        final isSelected = option.switchCameraId != null
            ? option.switchCameraId == selectedCameraId
            : (currentZoom - option.zoom).abs() < 0.2;

        return GestureDetector(
          onTap: () async {
            HapticFeedback.selectionClick();
            if (option.switchCameraId != null && option.switchCameraId != selectedCameraId) {
              await onSwitchLens(option.switchCameraId!);
            } else {
              await onSetZoom(option.zoom);
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: isSelected ? Colors.amber : Colors.black45,
            ),
            child: buildRotatedWidget(
              iconTurns: iconTurns,
              child: Text(
                option.label,
                style: TextStyle(
                  color: isSelected ? Colors.black : Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        );
      }).toList(),
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