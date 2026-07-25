import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class GlassPill extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  
  const GlassPill({super.key, required this.child, this.padding = const EdgeInsets.all(8)});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          padding: padding,
          color: Colors.white.withOpacity(0.15),
          child: child,
        ),
      ),
    );
  }
}

class TopSettingsPill extends StatelessWidget {
  final FlashMode flashMode;
  final VoidCallback onCycleFlash;
  final int timerDelay;
  final VoidCallback onCycleTimer;
  final ResolutionPreset resolution;
  final ValueChanged<ResolutionPreset> onChangeResolution;
  final bool isVideoMode;
  final VoidCallback onClose;
  final bool isVertical;

  const TopSettingsPill({
    super.key, required this.flashMode, required this.onCycleFlash,
    required this.timerDelay, required this.onCycleTimer,
    required this.resolution, required this.onChangeResolution,
    required this.isVideoMode, required this.onClose, this.isVertical = false,
  });

  @override
  Widget build(BuildContext context) {
    final children = [
      _buildIconBtn(Icons.close_rounded, Colors.white, onClose),
      const SizedBox(width: 16, height: 16),
      _buildResolutionMenu(context),
      if (!isVideoMode) ...[
        const SizedBox(width: 8, height: 8),
        _buildIconBtn(
          timerDelay == 3 ? Icons.timer_3_rounded : timerDelay == 10 ? Icons.timer_10_rounded : Icons.timer_off_rounded,
          timerDelay > 0 ? Colors.amber : Colors.white,
          onCycleTimer,
        ),
        const SizedBox(width: 8, height: 8),
        _buildIconBtn(
          flashMode == FlashMode.auto ? Icons.flash_auto_rounded : (flashMode == FlashMode.always || flashMode == FlashMode.torch) ? Icons.flash_on_rounded : Icons.flash_off_rounded,
          flashMode == FlashMode.off ? Colors.white : Colors.amber,
          onCycleFlash,
        ),
      ]
    ];

    return GlassPill(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: isVertical ? Column(mainAxisSize: MainAxisSize.min, children: children) : Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }

  Widget _buildIconBtn(IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Icon(icon, color: color, size: 24),
    );
  }

  Widget _buildResolutionMenu(BuildContext context) {
    return PopupMenuButton<ResolutionPreset>(
      initialValue: resolution,
      color: Colors.black87,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onSelected: onChangeResolution,
      itemBuilder: (context) => ResolutionPreset.values.reversed.map((res) {
        return PopupMenuItem(value: res, child: Text(res.name.toUpperCase(), style: const TextStyle(color: Colors.white)));
      }).toList(),
      child: Text(resolution.name.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
    );
  }
}

class ModernShutterButton extends StatelessWidget {
  final bool isVideoMode;
  final bool isRecording;
  final VoidCallback onTap;

  const ModernShutterButton({super.key, required this.isVideoMode, required this.isRecording, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 80, height: 80,
        padding: EdgeInsets.all(isVideoMode && isRecording ? 20 : 4),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white54, width: 4),
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          decoration: BoxDecoration(
            color: isVideoMode ? Colors.redAccent : Colors.white,
            borderRadius: BorderRadius.circular(isVideoMode && isRecording ? 12 : 40),
          ),
        ),
      ),
    );
  }
}

class CameraModeSelector extends StatelessWidget {
  final bool isVideoMode;
  final ValueChanged<bool> onModeChanged;
  final bool isVertical;

  const CameraModeSelector({super.key, required this.isVideoMode, required this.onModeChanged, required this.isVertical});

  @override
  Widget build(BuildContext context) {
    final photoBtn = _buildTab('PHOTO', !isVideoMode, () => onModeChanged(false));
    final videoBtn = _buildTab('VIDEO', isVideoMode, () => onModeChanged(true));

    return GlassPill(
      padding: const EdgeInsets.all(4),
      child: isVertical ? Column(mainAxisSize: MainAxisSize.min, children: [photoBtn, videoBtn]) : Row(mainAxisSize: MainAxisSize.min, children: [photoBtn, videoBtn]),
    );
  }

  Widget _buildTab(String text, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
        ),
        child: RotatedBox(
          quarterTurns: isVertical ? 1 : 0,
          child: Text(text, style: TextStyle(color: isSelected ? Colors.white : Colors.white54, fontWeight: FontWeight.bold, fontSize: 13)),
        ),
      ),
    );
  }
}

class BusyOverlay extends StatelessWidget {
  final String label;
  const BusyOverlay({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: Container(
        color: Colors.black.withOpacity(0.4),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: 20),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}