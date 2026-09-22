import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'vault_camera_controller.dart';

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
                  PopupMenuButton<double>(
                    initialValue: selectedAspectRatio,
                    color: Colors.black87,
                    onSelected: onAspectRatioChanged,
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 4 / 3, child: Text('4:3', style: TextStyle(color: Colors.white))),
                      PopupMenuItem(value: 16 / 9, child: Text('16:9', style: TextStyle(color: Colors.white))),
                      PopupMenuItem(value: 1.0, child: Text('1:1', style: TextStyle(color: Colors.white))),
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
                    PopupMenuButton<String>(
                      initialValue: videoQuality,
                      color: Colors.black87,
                      onSelected: onVideoQualityChanged,
                      itemBuilder: (context) => [
                        PopupMenuItem(value: 'sd', child: Text(l10n.cameraQualitySd, style: const TextStyle(color: Colors.white))),
                        PopupMenuItem(value: 'hd', child: Text(l10n.cameraQualityHd, style: const TextStyle(color: Colors.white))),
                        PopupMenuItem(value: 'fhd', child: Text(l10n.cameraQualityFhd, style: const TextStyle(color: Colors.white))),
                        PopupMenuItem(value: 'uhd', child: Text(l10n.cameraQualityUhd, style: const TextStyle(color: Colors.white))),
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
                    PopupMenuButton<String>(
                      initialValue: photoResolution,
                      color: Colors.black87,
                      onSelected: onPhotoResolutionChanged,
                      itemBuilder: (context) => [
                        PopupMenuItem(value: 'max', child: Text(l10n.cameraPhotoResMax, style: const TextStyle(color: Colors.white))),
                        PopupMenuItem(value: 'high', child: Text(l10n.cameraPhotoResHigh, style: const TextStyle(color: Colors.white))),
                        PopupMenuItem(value: 'med', child: Text(l10n.cameraPhotoResMedium, style: const TextStyle(color: Colors.white))),
                        PopupMenuItem(value: 'low', child: Text(l10n.cameraPhotoResLow, style: const TextStyle(color: Colors.white))),
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