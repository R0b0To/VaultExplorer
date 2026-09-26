import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/features/camera/camera_ui_components.dart';
import 'package:vaultexplorer/features/camera/vault_camera_controller.dart';

class QrScannerScreen extends ConsumerStatefulWidget {
  const QrScannerScreen({super.key});

  @override
  ConsumerState<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends ConsumerState<QrScannerScreen> {
  late final VaultCameraController _camera;
  StreamSubscription<String>? _qrSub;
  bool _isTorchOn = false;
  bool _hasResult = false;
  int _displayRotation = 0;

  @override
  void initState() {
    super.initState();
    _camera = VaultCameraController(ref.read(vaultEngineEventsProvider));
    _initScanner();
  }

  Future<void> _initScanner() async {
    try {
      final hasPerms = await VaultCameraController.hasPermissions();
      if (!hasPerms) {
        final ok = await _camera.requestPermissions();
        if (!ok || !mounted) {
          Navigator.pop(context);
          return;
        }
      }

      await _camera.open(
        facing: 'back',
        quality: 'hd',
        scanMode: true,
      );

      _displayRotation = await VaultCameraController.getDisplayRotation();

      _qrSub = _camera.qrCodes.listen((qrText) {
        if (_hasResult || !mounted) return;
        _hasResult = true;
        HapticFeedback.mediumImpact();
        Navigator.pop(context, qrText);
      });

      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _toggleTorch() async {
    _isTorchOn = !_isTorchOn;
    await _camera.setFlash(_isTorchOn ? 'torch' : 'off');
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _qrSub?.cancel();
    _camera.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final l10n = context.l10n;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_camera.isInitialized && _camera.textureId != null)
            LayoutBuilder(
              builder: (context, constraints) => CameraPreviewView(
                textureId: _camera.textureId!,
                previewWidth: _camera.previewWidth,
                previewHeight: _camera.previewHeight,
                sensorOrientation: _camera.sensorOrientation,
                displayRotation: _displayRotation,
                frameAspectRatio: constraints.maxWidth / constraints.maxHeight,
              ),
            )
          else
            const Center(child: CircularProgressIndicator(color: Colors.white)),

          // Viewfinder mask with center cutout
          _ViewfinderOverlay(
            hint: l10n.qrScannerHint,
            accentColor: cs.primary,
          ),

          // Top action bar
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton.filledTonal(
                  icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                  style: IconButton.styleFrom(backgroundColor: Colors.black54),
                  onPressed: () => Navigator.pop(context),
                ),
                Text(
                  l10n.qrScannerTitle,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                IconButton.filledTonal(
                  icon: Icon(
                    _isTorchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                    color: _isTorchOn ? Colors.amber : Colors.white,
                  ),
                  style: IconButton.styleFrom(backgroundColor: Colors.black54),
                  onPressed: _toggleTorch,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ViewfinderOverlay extends StatelessWidget {
  final String hint;
  final Color accentColor;

  const _ViewfinderOverlay({required this.hint, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final boxSize = constraints.maxWidth * 0.68;
        final left = (constraints.maxWidth - boxSize) / 2;
        final top = (constraints.maxHeight - boxSize) / 2;
        final cutoutRect = Rect.fromLTWH(left, top, boxSize, boxSize);

        return Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(
              painter: _ScannerOverlayPainter(
                cutoutRect: cutoutRect,
                borderRadius: 16,
                overlayColor: Colors.black.withValues(alpha: 0.6),
              ),
            ),
            Center(
              child: Container(
                width: boxSize,
                height: boxSize,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: accentColor, width: 2.5),
                ),
              ),
            ),
            Positioned(
              bottom: constraints.maxHeight * 0.2,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    hint,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ScannerOverlayPainter extends CustomPainter {
  final Rect cutoutRect;
  final double borderRadius;
  final Color overlayColor;

  _ScannerOverlayPainter({
    required this.cutoutRect,
    required this.borderRadius,
    required this.overlayColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(cutoutRect, Radius.circular(borderRadius)));

    canvas.drawPath(path, Paint()..color = overlayColor);
  }

  @override
  bool shouldRepaint(covariant _ScannerOverlayPainter oldDelegate) {
    return oldDelegate.cutoutRect != cutoutRect ||
        oldDelegate.borderRadius != borderRadius ||
        oldDelegate.overlayColor != overlayColor;
  }
}