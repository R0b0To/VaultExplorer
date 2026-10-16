// Review step of the document scanner: fit the four corners to the page, pick a
// filter, rotate, and produce the finished page.
//
// Pops with a [ScanPage], or null if the user backs out. All work happens in
// memory through [DocumentScanApi].

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';

import '../camera_capture_lock_controller.dart';
import 'document_scan_api.dart';
import 'scan_geometry.dart';

enum _Stage { corners, result }

class DocumentScanEditorScreen extends ConsumerStatefulWidget {
  const DocumentScanEditorScreen({
    super.key,
    required this.original,
    required this.detection,
    required this.api,
    required this.volId,
  });

  /// The full-resolution capture; used for the final render.
  final Uint8List original;

  /// Detection result; its preview is what the corners are edited on and what
  /// the live filter preview is rendered from.
  final ScanDetection detection;

  final DocumentScanApi api;

  /// Container the page is destined for: the editor hides itself when it locks,
  /// like the camera screen does.
  final int volId;

  @override
  ConsumerState<DocumentScanEditorScreen> createState() => _DocumentScanEditorScreenState();
}

class _DocumentScanEditorScreenState extends ConsumerState<DocumentScanEditorScreen> {
  static const double _handleHit = 52;

  _Stage _stage = _Stage.corners;
  late ScanQuad _quad;
  ScanFilter _filter = ScanFilter.color;
  int _rotation = 0;
  Uint8List? _resultPreview;
  bool _busy = false;
  bool _saving = false;
  int _previewSeq = 0;
  int? _dragging;

  @override
  void initState() {
    super.initState();
    _quad = widget.detection.quad ?? ScanQuad.inset();
    if (widget.detection.quad == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _toast(context.l10n.scanNoDocumentFound);
      });
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // ───────────────────────────── actions ─────────────────────────────

  void _autoDetect() {
    final detected = widget.detection.quad;
    if (detected == null) {
      _toast(context.l10n.scanNoDocumentFound);
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => _quad = detected);
  }

  void _dragCorner(int index, Offset delta, Size box) {
    final target = _quad.corners[index] + Offset(delta.dx / box.width, delta.dy / box.height);
    final moved = _quad.withCorner(index, target);
    // Never let the outline fold over itself or collapse.
    if (!moved.isValid) return;
    setState(() => _quad = moved);
  }

  void _goToResult() {
    setState(() => _stage = _Stage.result);
    unawaited(_refreshPreview());
  }

  void _rotate() {
    HapticFeedback.selectionClick();
    setState(() => _rotation = (_rotation + 90) % 360);
    unawaited(_refreshPreview());
  }

  Future<void> _refreshPreview() async {
    final seq = ++_previewSeq;
    setState(() => _busy = true);
    try {
      final page = await widget.api.process(
        jpeg: widget.detection.preview,
        quad: _quad,
        filter: _filter,
        rotationDegrees: _rotation,
        maxLongSide: 1100,
        quality: 80,
      );
      if (!mounted || seq != _previewSeq) return;
      setState(() {
        _resultPreview = page.bytes;
        _busy = false;
      });
    } catch (_) {
      if (!mounted || seq != _previewSeq) return;
      setState(() => _busy = false);
      _toast(context.l10n.scanProcessingFailed);
    }
  }

  Future<void> _finish() async {
    setState(() => _saving = true);
    try {
      final page = await widget.api.process(
        jpeg: widget.original,
        quad: _quad,
        filter: _filter,
        rotationDegrees: _rotation,
      );
      if (!mounted) return;
      Navigator.of(context).pop(page);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast(context.l10n.scanProcessingFailed);
    }
  }

  // ───────────────────────────── build ─────────────────────────────

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(cameraCaptureLockProvider(widget.volId), (previous, locked) {
      if (locked && mounted) Navigator.of(context).pop();
    });
    if (ref.watch(cameraCaptureLockProvider(widget.volId))) {
      return const Scaffold(backgroundColor: Colors.black, body: SizedBox.expand());
    }

    return PopScope(
      canPop: _stage == _Stage.corners && !_saving,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || _saving) return;
        // From the preview, back returns to the corner step instead of leaving.
        setState(() => _stage = _Stage.corners);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            children: [
              _buildTopBar(),
              Expanded(
                child: _stage == _Stage.corners ? _buildCornerEditor() : _buildResultView(),
              ),
              _stage == _Stage.corners ? _buildCornerActions() : _buildResultActions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          IconButton(
            tooltip: l10n.goBack,
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: _saving ? null : () => Navigator.maybePop(context),
          ),
          Expanded(
            child: Text(
              _stage == _Stage.corners ? l10n.scanAdjustCornersTitle : l10n.scanResultTitle,
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  // ── step 1: corners ──

  Widget _buildCornerEditor() {
    final detection = widget.detection;
    return LayoutBuilder(
      builder: (context, constraints) {
        final rect = fitContain(
          constraints.biggest,
          Size(detection.width.toDouble(), detection.height.toDouble()),
        );
        Offset toPx(Offset n) => Offset(rect.left + n.dx * rect.width, rect.top + n.dy * rect.height);
        final points = [for (final c in _quad.corners) toPx(c)];

        return Stack(
          children: [
            Positioned.fromRect(
              rect: rect,
              child: Image.memory(
                detection.preview,
                fit: BoxFit.fill,
                gaplessPlayback: true,
                filterQuality: FilterQuality.medium,
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(child: CustomPaint(painter: _OutlinePainter(points))),
            ),
            for (var i = 0; i < 4; i++)
              Positioned(
                left: points[i].dx - _handleHit / 2,
                top: points[i].dy - _handleHit / 2,
                width: _handleHit,
                height: _handleHit,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (_) => setState(() => _dragging = i),
                  onPanUpdate: (d) => _dragCorner(i, d.delta, rect.size),
                  onPanEnd: (_) => setState(() => _dragging = null),
                  onPanCancel: () => setState(() => _dragging = null),
                  child: Center(child: _HandleDot(active: _dragging == i)),
                ),
              ),
            if (_dragging != null) _buildLoupe(rect, constraints.biggest),
          ],
        );
      },
    );
  }

  /// Magnifier over the corner being dragged, so the finger doesn't hide it.
  Widget _buildLoupe(Rect rect, Size area) {
    const size = 116.0;
    const zoom = 2.6;
    final n = _quad.corners[_dragging!];
    final corner = Offset(rect.left + n.dx * rect.width, rect.top + n.dy * rect.height);
    var top = corner.dy - size - 56;
    if (top < 4) top = corner.dy + 56;
    final left = math.min(math.max(corner.dx - size / 2, 4.0), math.max(4.0, area.width - size - 4));

    return Positioned(
      left: left,
      top: top,
      width: size,
      height: size,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.amber, width: 2),
            boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 8)],
          ),
          child: ClipOval(
            child: Stack(
              children: [
                Positioned(
                  left: size / 2 - n.dx * rect.width * zoom,
                  top: size / 2 - n.dy * rect.height * zoom,
                  width: rect.width * zoom,
                  height: rect.height * zoom,
                  child: Image.memory(widget.detection.preview, fit: BoxFit.fill, gaplessPlayback: true),
                ),
                const Center(child: Icon(Icons.add, color: Colors.amber, size: 22)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCornerActions() {
    final l10n = context.l10n;
    const outline = BorderSide(color: Colors.white38);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                OutlinedButton.icon(
                  onPressed: _autoDetect,
                  icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
                  label: Text(l10n.scanAutoDetectButton),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: outline),
                ),
                OutlinedButton.icon(
                  onPressed: () => setState(() => _quad = ScanQuad.inset(0)),
                  icon: const Icon(Icons.crop_free_rounded, size: 18),
                  label: Text(l10n.scanFullImageButton),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: outline),
                ),
              ],
            ),
          ),
            const SizedBox(width: 8),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
            onPressed: _goToResult,
            child: Text(l10n.continueButton),
          ),
        ],
      ),
    );
  }

  // ── step 2: result ──

  Widget _buildResultView() {
    final preview = _resultPreview;
    return Stack(
      children: [
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: preview == null
                ? const SizedBox.shrink()
                : Center(child: Image.memory(preview, fit: BoxFit.contain, gaplessPlayback: true)),
          ),
        ),
        if (_busy || _saving) const Center(child: CircularProgressIndicator(color: Colors.amber)),
      ],
    );
  }

  String _filterLabel(ScanFilter filter) {
    final l10n = context.l10n;
    switch (filter) {
      case ScanFilter.original:
        return l10n.cropAspectOriginalLabel;
      case ScanFilter.color:
        return l10n.scanFilterColor;
      case ScanFilter.gray:
        return l10n.scanFilterGrayscale;
      case ScanFilter.blackWhite:
        return l10n.adjustmentPresetBlackAndWhite;
    }
  }

  Widget _buildResultActions() {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final f in ScanFilter.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(_filterLabel(f)),
                      selected: _filter == f,
                      showCheckmark: false,
                      selectedColor: Colors.amber,
                      backgroundColor: Colors.white12,
                      side: BorderSide.none,
                      labelStyle: TextStyle(color: _filter == f ? Colors.black : Colors.white),
                      onSelected: _saving
                          ? null
                          : (_) {
                              setState(() => _filter = f);
                              unawaited(_refreshPreview());
                            },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _saving ? null : _rotate,
                icon: const Icon(Icons.rotate_right_rounded, size: 18),
                label: Text(l10n.rotateRightTooltip),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white38),
                ),
              ),
             const Spacer(),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                onPressed: (_saving || _busy) ? null : _finish,
                child: Text(l10n.done),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HandleDot extends StatelessWidget {
  const _HandleDot({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? Colors.amber : Colors.white,
        border: Border.all(color: Colors.amber, width: 3),
        boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 4)],
      ),
    );
  }
}

class _OutlinePainter extends CustomPainter {
  _OutlinePainter(this.points);

  final List<Offset> points;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..addPolygon(points, true);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.fill
        ..color = Colors.amber.withValues(alpha: 0.15),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.amber,
    );
  }

  @override
  bool shouldRepaint(_OutlinePainter oldDelegate) => true;
}
