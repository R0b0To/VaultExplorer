part of 'image_editor_screen.dart';

// ── PHOTO STUDIO SPECIFICATIONS & TYPES ─────────────────────────────────────

enum _TuneParam {
  brightness,
  contrast,
  saturation,
  ambiance,
  warmth,
  shadows,
}

extension _TuneParamX on _TuneParam {
  String get label => switch (this) {
    _TuneParam.brightness => 'Brightness',
    _TuneParam.contrast => 'Contrast',
    _TuneParam.saturation => 'Saturation',
    _TuneParam.ambiance => 'Ambiance',
    _TuneParam.warmth => 'Warmth',
    _TuneParam.shadows => 'Shadows',
  };

  IconData get icon => switch (this) {
    _TuneParam.brightness => Icons.brightness_6_rounded,
    _TuneParam.contrast => Icons.contrast_rounded,
    _TuneParam.saturation => Icons.color_lens_outlined,
    _TuneParam.ambiance => Icons.auto_awesome_rounded,
    _TuneParam.warmth => Icons.thermostat_rounded,
    _TuneParam.shadows => Icons.wb_twilight_rounded,
  };
}

class _LookPreset {
  final String id;
  final String label;
  final ViewerAdjustments adjustments;

  const _LookPreset({
    required this.id,
    required this.label,
    required this.adjustments,
  });
}

const List<_LookPreset> _kLookPresets = [
  _LookPreset(
    id: 'original',
    label: 'Current',
    adjustments: ViewerAdjustments.identity,
  ),
  _LookPreset(
    id: 'portrait',
    label: 'Portrait',
    adjustments: ViewerAdjustments(
      contrast: 1.05,
      saturation: 1.08,
      gamma: 1.05,
    ),
  ),
  _LookPreset(
    id: 'vivid',
    label: 'Vivid',
    adjustments: ViewerAdjustments.vivid,
  ),
  _LookPreset(
    id: 'bw',
    label: 'B&W',
    adjustments: ViewerAdjustments.blackAndWhite,
  ),
  _LookPreset(
    id: 'warm',
    label: 'Warm',
    adjustments: ViewerAdjustments.warm,
  ),
  _LookPreset(
    id: 'cool',
    label: 'Cool',
    adjustments: ViewerAdjustments.cool,
  ),
  _LookPreset(
    id: 'dramatic',
    label: 'Dramatic',
    adjustments: ViewerAdjustments(contrast: 1.25, saturation: 0.85),
  ),
  _LookPreset(
    id: 'vintage',
    label: 'Vintage',
    adjustments: ViewerAdjustments(
      contrast: 0.95,
      saturation: 0.85,
      hue: 0.1,
      gamma: 1.1,
    ),
  ),
];

// ── TOP BAR (WITH SAFE AREA FOR STATUS BAR) ─────────────────────────────────

class _EditorTopBar extends StatelessWidget implements PreferredSizeWidget {
  final String fileName;
  final EditorTool activeTool;
  final bool canUndo;
  final bool hasEdits;
  final bool isComparing;
  final bool allowSequentialCapture;
  final VoidCallback onBack;
  final VoidCallback onUndo;
  final VoidCallback onCompareStart;
  final VoidCallback onCompareEnd;
  final VoidCallback onResetToOriginal;
  final VoidCallback onExport;
  final VoidCallback? onContinueCapture;

  const _EditorTopBar({
    required this.fileName,
    required this.activeTool,
    required this.canUndo,
    required this.hasEdits,
    required this.isComparing,
    required this.allowSequentialCapture,
    required this.onBack,
    required this.onUndo,
    required this.onCompareStart,
    required this.onCompareEnd,
    required this.onResetToOriginal,
    required this.onExport,
    this.onContinueCapture,
  });

  @override
  Size get preferredSize => const Size.fromHeight(52);

  String _toolTitle(EditorTool tool) => switch (tool) {
    EditorTool.crop => 'Crop',
    EditorTool.tuneImage => 'Tune Image',
    EditorTool.looks => 'Looks',
    EditorTool.draw => 'Draw',
    EditorTool.text => 'Text',
    EditorTool.redact => 'Redact',
    EditorTool.none => fileName,
  };

  @override
  Widget build(BuildContext context) {
    final isToolActive = activeTool != EditorTool.none;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Color(0xFF161616),
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Container(
        color: Colors.black,
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: 52,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  if (!isToolActive) ...[
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                      tooltip: 'Back',
                      onPressed: onBack,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.undo_rounded,
                        color: canUndo ? Colors.white : Colors.white24,
                      ),
                      tooltip: 'Undo',
                      onPressed: canUndo ? onUndo : null,
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.layers_outlined,
                        color: hasEdits ? Colors.white : Colors.white38,
                      ),
                      tooltip: 'Reset Edits',
                      onPressed: hasEdits ? onResetToOriginal : null,
                    ),
                    if (allowSequentialCapture && onContinueCapture != null)
                      IconButton(
                        icon: const Icon(
                          Icons.add_a_photo_outlined,
                          color: Colors.white,
                        ),
                        tooltip: 'Add Another',
                        onPressed: onContinueCapture,
                      ),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
                      color: const Color(0xFF262626),
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      onSelected: (value) {
                        switch (value) {
                          case 'reset':
                            onResetToOriginal();
                            break;
                          case 'export':
                            onExport();
                            break;
                        }
                      },
                      itemBuilder: (ctx) => [
                        PopupMenuItem(
                          value: 'export',
                          child: Row(
                            children: const [
                              Icon(Icons.save_alt_rounded, color: Colors.white, size: 20),
                              SizedBox(width: 12),
                              Text('Export / Save', style: TextStyle(color: Colors.white)),
                            ],
                          ),
                        ),
                        if (hasEdits)
                          PopupMenuItem(
                            value: 'reset',
                            child: Row(
                              children: const [
                                Icon(Icons.restart_alt_rounded, color: Colors.white, size: 20),
                                SizedBox(width: 12),
                                Text('Revert to Original', style: TextStyle(color: Colors.white)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ] else ...[
                    // Active Tool Mode: Cyan square indicator + Tool Title
                    const SizedBox(width: 12),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: const Color(0xFF38BDF8),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _toolTitle(activeTool),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    // Hold-to-compare Eye icon
                    Listener(
                      onPointerDown: (_) => onCompareStart(),
                      onPointerUp: (_) => onCompareEnd(),
                      onPointerCancel: (_) => onCompareEnd(),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        child: Icon(
                          isComparing ? Icons.visibility : Icons.visibility_outlined,
                          color: isComparing ? const Color(0xFF38BDF8) : Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.undo_rounded,
                        color: canUndo ? Colors.white : Colors.white24,
                      ),
                      tooltip: 'Undo',
                      onPressed: canUndo ? onUndo : null,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── BOTTOM NAVIGATION (LOOKS | TOOLS | EXPORT) ──────────────────────────────

class _EditorBottomBar extends StatelessWidget {
  final bool isToolsActive;
  final bool isLooksActive;
  final VoidCallback onSelectLooks;
  final VoidCallback onSelectTools;
  final VoidCallback onExport;

  const _EditorBottomBar({
    required this.isToolsActive,
    required this.isLooksActive,
    required this.onSelectLooks,
    required this.onSelectTools,
    required this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      decoration: const BoxDecoration(
        color: Color(0xFF161616),
        border: Border(
          top: BorderSide(color: Color(0xFF262626), width: 0.8),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onSelectLooks,
              child: Center(
                child: Text(
                  'Looks',
                  style: TextStyle(
                    color: isLooksActive ? const Color(0xFF38BDF8) : Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: onSelectTools,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.keyboard_arrow_up_rounded,
                      color: Colors.white,
                      size: 14,
                    ),
                    Text(
                      'Tools',
                      style: TextStyle(
                        color: isToolsActive ? const Color(0xFF38BDF8) : Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: onExport,
              child: const Center(
                child: Text(
                  'Export',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── TOOLS DRAWER ROW ────────────────────────────────────────────────────────

class _EditorToolsRow extends StatelessWidget {
  final EditorTool activeTool;
  final void Function(EditorTool) onSelectTool;

  const _EditorToolsRow({
    required this.activeTool,
    required this.onSelectTool,
  });

  Widget _buildToolItem({
    required IconData icon,
    required String label,
    required EditorTool tool,
  }) {
    final selected = activeTool == tool;
    return InkWell(
      onTap: () => onSelectTool(tool),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected
                    ? const Color(0xFF38BDF8).withValues(alpha: 0.18)
                    : const Color(0xFF222222),
                border: Border.all(
                  color: selected
                      ? const Color(0xFF38BDF8)
                      : Colors.white.withValues(alpha: 0.18),
                  width: 1.2,
                ),
              ),
              child: Icon(
                icon,
                color: selected ? const Color(0xFF38BDF8) : Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: selected ? const Color(0xFF38BDF8) : Colors.white70,
                fontSize: 11,
                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF161616),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildToolItem(
              icon: Icons.tune_rounded,
              label: 'Tune Image',
              tool: EditorTool.tuneImage,
            ),
            _buildToolItem(
              icon: Icons.crop_rounded,
              label: 'Crop',
              tool: EditorTool.crop,
            ),
            _buildToolItem(
              icon: Icons.brush_rounded,
              label: 'Draw',
              tool: EditorTool.draw,
            ),
            _buildToolItem(
              icon: Icons.text_fields_rounded,
              label: 'Text',
              tool: EditorTool.text,
            ),
            _buildToolItem(
              icon: Icons.visibility_off_outlined,
              label: 'Redact',
              tool: EditorTool.redact,
            ),
          ],
        ),
      ),
    );
  }
}

// ── TOOL ACTION BAR (CANCEL "X" / CENTER ACTIONS / APPLY "✓") ────────────────

class _EditorToolActionBar extends StatelessWidget {
  final VoidCallback onCancel;
  final VoidCallback onApply;
  final List<Widget> centerActions;

  const _EditorToolActionBar({
    required this.onCancel,
    required this.onApply,
    this.centerActions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      decoration: const BoxDecoration(
        color: Color(0xFF161616),
        border: Border(
          top: BorderSide(color: Color(0xFF262626), width: 0.8),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white, size: 24),
            tooltip: 'Cancel',
            onPressed: onCancel,
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: centerActions,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.check_rounded, color: Colors.white, size: 24),
            tooltip: 'Apply',
            onPressed: onApply,
          ),
        ],
      ),
    );
  }
}

class _EditorToolActionItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool isSelected;

  const _EditorToolActionItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 30,
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFFDCDCDC)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Center(
                child: Icon(
                  icon,
                  color: isSelected ? const Color(0xFF1E1E1E) : Colors.white,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── STATIC LEVEL RULER (MATCHING ACTUAL STUDIO GAUGE SPECIFICATION) ─────────

/// A static ruler with fixed vertical tick marks across the screen,
/// where a solid amber fill bar expands from center (0) to the active value,
/// with an amber downward triangle pointer at the tip.
class _EditorLevelRuler extends StatefulWidget {
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  const _EditorLevelRuler({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  State<_EditorLevelRuler> createState() => _EditorLevelRulerState();
}

class _EditorLevelRulerState extends State<_EditorLevelRuler> {
  double? _dragStartX;
  double? _dragStartValue;

  void _handleDragStart(Offset localPos) {
    _dragStartX = localPos.dx;
    _dragStartValue = widget.value;
  }

  void _handleDragUpdate(Offset localPos, double width) {
    if (_dragStartX == null || _dragStartValue == null) {
      _handleAbsoluteTouch(localPos, width);
      return;
    }
    const pad = 16.0;
    final usableW = width - (pad * 2);
    if (usableW <= 0) return;

    final dx = localPos.dx - _dragStartX!;
    final range = widget.max - widget.min;
    final deltaValue = (dx / usableW) * range;
    final newVal = (_dragStartValue! + deltaValue).clamp(widget.min, widget.max);
    widget.onChanged(newVal);
  }

  void _handleAbsoluteTouch(Offset localPos, double width) {
    const pad = 16.0;
    final usableW = width - (pad * 2);
    if (usableW <= 0) return;
    final clampedX = localPos.dx.clamp(pad, width - pad);
    final centerX = width / 2.0;
    final ratio = (clampedX - centerX) / (usableW / 2.0); // -1.0 .. +1.0
    final double newVal;
    if (widget.min < 0 && widget.max > 0) {
      newVal = ratio >= 0 ? (ratio * widget.max) : (ratio * widget.min.abs());
    } else {
      newVal = widget.min + ((ratio + 1.0) / 2.0) * (widget.max - widget.min);
    }
    widget.onChanged(newVal.clamp(widget.min, widget.max));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (details) => _handleDragStart(details.localPosition),
          onHorizontalDragUpdate: (details) => _handleDragUpdate(details.localPosition, w),
          onHorizontalDragEnd: (_) {
            _dragStartX = null;
            _dragStartValue = null;
          },
          onHorizontalDragCancel: () {
            _dragStartX = null;
            _dragStartValue = null;
          },
          onTapUp: (details) => _handleAbsoluteTouch(details.localPosition, w),
          child: SizedBox(
            height: 32,
            width: double.infinity,
            child: CustomPaint(
              painter: _EditorLevelRulerPainter(
                value: widget.value,
                min: widget.min,
                max: widget.max,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EditorLevelRulerPainter extends CustomPainter {
  final double value;
  final double min;
  final double max;

  _EditorLevelRulerPainter({
    required this.value,
    required this.min,
    required this.max,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    const pad = 16.0;
    final usableW = size.width - (pad * 2);
    final centerX = size.width / 2.0;
    final centerY = size.height / 2.0;

    // 1. Calculate active value position X
    final double rawValX;
    if (min < 0 && max > 0) {
      final ratio = value >= 0 ? (value / max) : (value / min.abs());
      rawValX = centerX + ratio * (usableW / 2.0);
    } else {
      rawValX = pad + ((value - min) / (max - min)) * usableW;
    }
    final valX = rawValX.clamp(pad, size.width - pad);

    // 2. Draw static background ticks across full ruler width
    const tickSpacing = 6.0;
    final numTicks = (usableW / tickSpacing).floor();
    final actualSpacing = usableW / numTicks;

    final tickPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;

    final centerTickPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.75)
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i <= numTicks; i++) {
      final tx = pad + i * actualSpacing;
      final isCenter = (tx - centerX).abs() < (actualSpacing / 2.0);
      final tickH = isCenter ? 14.0 : 10.0;
      canvas.drawLine(
        Offset(tx, centerY - tickH / 2.0),
        Offset(tx, centerY + tickH / 2.0),
        isCenter ? centerTickPaint : tickPaint,
      );
    }

    // 3. Draw solid amber fill bar from center to current value position
    const amberColor = Color(0xFFF59E0B);
    final fillPaint = Paint()
      ..color = amberColor
      ..style = PaintingStyle.fill;

    if (min >= 0 || value.abs() > 0.4) {
      final double startX;
      final double endX;
      if (min >= 0) {
        startX = pad;
        endX = valX;
      } else {
        startX = math.min(centerX, valX);
        endX = math.max(centerX, valX);
      }
      const barH = 10.0;
      final rrect = RRect.fromRectAndRadius(
        Rect.fromLTRB(startX, centerY - barH / 2.0, endX, centerY + barH / 2.0),
        const Radius.circular(2.0),
      );
      canvas.drawRRect(rrect, fillPaint);
    }

    // 4. Draw downward triangle pointer at valX right above the bar
    final arrowTop = centerY - 12.0;
    final arrowBottom = centerY - 5.0;
    final arrowPath = Path()
      ..moveTo(valX - 4.5, arrowTop)
      ..lineTo(valX + 4.5, arrowTop)
      ..lineTo(valX, arrowBottom)
      ..close();
    canvas.drawPath(arrowPath, fillPaint);
  }

  @override
  bool shouldRepaint(covariant _EditorLevelRulerPainter oldDelegate) =>
      oldDelegate.value != value || oldDelegate.min != min || oldDelegate.max != max;
}

// ── CROP SHELF (ANGLE RULER + ASPECT CARDS) ──────────────────────────────────

class _CropShelf extends StatelessWidget {
  final double? cropAspectRatio;
  final Size? cropBoxSize;
  final ValueChanged<double?> onSetCropAspect;
  final double angle;
  final ValueChanged<double> onAngleChanged;

  const _CropShelf({
    required this.cropAspectRatio,
    required this.cropBoxSize,
    required this.onSetCropAspect,
    required this.angle,
    required this.onAngleChanged,
  });

  @override
  Widget build(BuildContext context) {
    final currentAspect = cropBoxSize == null
        ? 1.0
        : cropBoxSize!.width / cropBoxSize!.height;

    final formattedAngle = angle.abs() < 0.005
        ? '0.00°'
        : '${angle > 0 ? '+' : ''}${angle.toStringAsFixed(2)}°';

    final aspects = [
      (label: 'Free', icon: Icons.crop_free_rounded, ratio: null),
      (label: 'Original', icon: Icons.crop_original_rounded, ratio: currentAspect),
      (label: 'Square', icon: Icons.crop_square_rounded, ratio: 1.0),
      (label: 'DIN', icon: Icons.description_outlined, ratio: 1.0 / 1.414),
      (label: '3:2', icon: Icons.crop_3_2_rounded, ratio: 3.0 / 2.0),
      (label: '4:3', icon: Icons.crop_7_5_rounded, ratio: 4.0 / 3.0),
      (label: '16:9', icon: Icons.crop_16_9_rounded, ratio: 16.0 / 9.0),
    ];

    return Container(
      color: const Color(0xFF161616),
      padding: const EdgeInsets.only(top: 6, bottom: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Parameter Readout row: Angle on left, value centered
          SizedBox(
            height: 32,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                  left: 16,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white70, width: 1.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Icon(
                          Icons.unfold_more_rounded,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Angle',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Center(
                  child: Text(
                    formattedAngle,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Level ruler
          _EditorLevelRuler(
            value: angle,
            min: -45.0,
            max: 45.0,
            onChanged: onAngleChanged,
          ),
          const SizedBox(height: 6),
          // Aspect cards
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                for (final item in aspects) ...[
                  _AspectCard(
                    icon: item.icon,
                    label: item.label,
                    selected: item.ratio == null
                        ? cropAspectRatio == null
                        : (cropAspectRatio != null &&
                            (cropAspectRatio! - item.ratio!).abs() < 0.01),
                    onTap: () => onSetCropAspect(item.ratio),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AspectCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _AspectCard({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          color: selected
              ? Colors.white.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? Colors.white : Colors.white24,
            width: selected ? 1.8 : 1.0,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 22,
              color: selected ? Colors.white : Colors.white70,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : Colors.white70,
                fontSize: 10,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── TUNE IMAGE SHELF & FLOATING PARAMETER OVERLAY ───────────────────────────

class _TuneImageShelf extends StatelessWidget {
  final _TuneParam param;
  final int value;
  final ValueChanged<int> onValueChanged;
  final VoidCallback onToggleParamMenu;

  const _TuneImageShelf({
    required this.param,
    required this.value,
    required this.onValueChanged,
    required this.onToggleParamMenu,
  });

  String get _signedValue => value > 0 ? '+$value' : '$value';

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF161616),
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header: Parameter label on left, value centered over ruler needle
          SizedBox(
            height: 38,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                  left: 16,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onToggleParamMenu,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.white70, width: 1.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Icon(
                              Icons.unfold_more_rounded,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            param.label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Center(
                  child: Text(
                    _signedValue,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Static gauge ruler with solid amber fill bar
          _EditorLevelRuler(
            value: value.toDouble(),
            min: -100.0,
            max: 100.0,
            onChanged: (v) => onValueChanged(v.round()),
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

/// Floating parameter selector overlay with amber active item bar
class _TuneParamOverlay extends StatelessWidget {
  final _TuneParam selectedParam;
  final Map<_TuneParam, int> values;
  final ValueChanged<_TuneParam> onSelectParam;
  final VoidCallback? onDismiss;
  final bool isInteractive;

  const _TuneParamOverlay({
    required this.selectedParam,
    required this.values,
    required this.onSelectParam,
    this.onDismiss,
    this.isInteractive = true,
  });

  String _formatValue(int val) => val > 0 ? '+$val' : '$val';

  @override
  Widget build(BuildContext context) {
    final cardContent = SizedBox(
      width: 230,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
            decoration: BoxDecoration(
              color: const Color(0xCC1A1A1A),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
                width: 0.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final p in _TuneParam.values) ...[
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onSelectParam(p),
                    child: Container(
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: p == selectedParam
                            ? const Color(0xFFF59E0B) // Amber highlight
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            p.icon,
                            size: 16,
                            color: p == selectedParam ? Colors.black : Colors.white70,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            p.label,
                            style: TextStyle(
                              color: p == selectedParam ? Colors.black : Colors.white,
                              fontSize: 14,
                              fontWeight: p == selectedParam
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            _formatValue(values[p] ?? 0),
                            style: TextStyle(
                              color: p == selectedParam ? Colors.black : Colors.white70,
                              fontSize: 13,
                              fontWeight: p == selectedParam
                                  ? FontWeight.w700
                                  : FontWeight.normal,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
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

    final overlayBody = Container(
      color: Colors.transparent,
      child: Center(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {}, // prevent tap inside card from dismissing
          child: cardContent,
        ),
      ),
    );

    if (!isInteractive) {
      return IgnorePointer(child: overlayBody);
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onDismiss,
      child: overlayBody,
    );
  }
}

// ── LOOKS PRESET CAROUSEL ───────────────────────────────────────────────────

class _LooksShelf extends StatelessWidget {
  final String selectedPresetId;
  final ValueChanged<_LookPreset> onSelectPreset;

  const _LooksShelf({
    required this.selectedPresetId,
    required this.onSelectPreset,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF161616),
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              'MY LOOKS',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
              ),
            ),
          ),
          SizedBox(
            height: 90,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              itemCount: _kLookPresets.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, idx) {
                final preset = _kLookPresets[idx];
                final isSelected = preset.id == selectedPresetId;
                return GestureDetector(
                  onTap: () => onSelectPreset(preset),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          color: const Color(0xFF262626),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected ? Colors.white : Colors.white24,
                            width: isSelected ? 2.0 : 1.0,
                          ),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: switch (preset.id) {
                              'portrait' => const [Color(0xFF8B5E3C), Color(0xFF4A3525)],
                              'vivid' => const [Color(0xFFE65100), Color(0xFF1565C0)],
                              'bw' => const [Color(0xFF9E9E9E), Color(0xFF212121)],
                              'warm' => const [Color(0xFFF57C00), Color(0xFFFFB74D)],
                              'cool' => const [Color(0xFF0288D1), Color(0xFF81D4FA)],
                              'dramatic' => const [Color(0xFF263238), Color(0xFF37474F)],
                              'vintage' => const [Color(0xFF795548), Color(0xFFA1887F)],
                              _ => const [Color(0xFF424242), Color(0xFF212121)],
                            },
                          ),
                        ),
                        child: Center(
                          child: Icon(
                            switch (preset.id) {
                              'bw' => Icons.monochrome_photos_rounded,
                              'portrait' => Icons.portrait_rounded,
                              'vivid' => Icons.auto_awesome_rounded,
                              'warm' => Icons.wb_sunny_rounded,
                              'cool' => Icons.ac_unit_rounded,
                              'dramatic' => Icons.filter_hdr_rounded,
                              'vintage' => Icons.camera_roll_rounded,
                              _ => Icons.photo_rounded,
                            },
                            color: Colors.white.withValues(alpha: 0.8),
                            size: 22,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        preset.label,
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.white70,
                          fontSize: 11,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── TEXT SHELF (STYLE / COLOR / OPACITY TABS) ───────────────────────────────

enum _TextShelfTab { color, opacity, style }

class _TextShelf extends StatelessWidget {
  final _TextShelfTab tab;
  final TextMarkAnnotation textAnnotation;
  final ValueChanged<String> onSelectStyle;
  final ValueChanged<Color> onSelectColor;
  final ValueChanged<double> onOpacityChanged;

  const _TextShelf({
    required this.tab,
    required this.textAnnotation,
    required this.onSelectStyle,
    required this.onSelectColor,
    required this.onOpacityChanged,
  });

  @override
  Widget build(BuildContext context) {
    switch (tab) {
      case _TextShelfTab.style:
        return Container(
          color: const Color(0xFF161616),
          padding: const EdgeInsets.only(top: 10, bottom: 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                for (final preset in kTextPresets) ...[
                  GestureDetector(
                    onTap: () => onSelectStyle(preset.id),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(
                              color: textAnnotation.styleId == preset.id
                                  ? Colors.white.withValues(alpha: 0.12)
                                  : Colors.white.withValues(alpha: 0.04),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: textAnnotation.styleId == preset.id
                                    ? Colors.white
                                    : Colors.white24,
                                width: textAnnotation.styleId == preset.id ? 1.8 : 1.0,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              preset.previewText,
                              style: getTextStyleForPreset(
                                styleId: preset.id,
                                fontSize: 15,
                                color: textAnnotation.styleId == preset.id
                                    ? Colors.white
                                    : Colors.white70,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            preset.label,
                            style: TextStyle(
                              color: textAnnotation.styleId == preset.id
                                  ? Colors.white
                                  : Colors.white60,
                              fontSize: 11,
                              fontWeight: textAnnotation.styleId == preset.id
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );

      case _TextShelfTab.color:
        return Container(
          color: const Color(0xFF161616),
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                for (final c in editorColorPalette) ...[
                  GestureDetector(
                    onTap: () => onSelectColor(c),
                    child: Container(
                      width: 36,
                      height: 36,
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: textAnnotation.color == c
                              ? Colors.white
                              : Colors.white24,
                          width: textAnnotation.color == c ? 2.5 : 1.2,
                        ),
                      ),
                      child: textAnnotation.color == c
                          ? Icon(
                              Icons.check_rounded,
                              size: 18,
                              color: c.computeLuminance() > 0.5
                                  ? Colors.black
                                  : Colors.white,
                            )
                          : null,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );

      case _TextShelfTab.opacity:
        return Container(
          color: const Color(0xFF161616),
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 34,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned(
                      left: 16,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.white70, width: 1.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Icon(
                              Icons.unfold_more_rounded,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Opacity',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Center(
                      child: Text(
                        '${(textAnnotation.opacity * 100).round()}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _EditorLevelRuler(
                value: textAnnotation.opacity * 100.0,
                min: 0.0,
                max: 100.0,
                onChanged: (v) => onOpacityChanged(v / 100.0),
              ),
            ],
          ),
        );
    }
  }
}

enum _DrawShelfTab { color, size, opacity }

class _DrawShelf extends StatelessWidget {
  final _DrawShelfTab tab;
  final Color selectedColor;
  final double opacity;
  final double strokeDiameter;
  final ValueChanged<Color> onSelectColor;
  final ValueChanged<double> onOpacityChanged;
  final ValueChanged<double> onStrokeDiameterChanged;

  const _DrawShelf({
    required this.tab,
    required this.selectedColor,
    required this.opacity,
    required this.strokeDiameter,
    required this.onSelectColor,
    required this.onOpacityChanged,
    required this.onStrokeDiameterChanged,
  });

  @override
  Widget build(BuildContext context) {
    switch (tab) {
      case _DrawShelfTab.color:
        return Container(
          color: const Color(0xFF161616),
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                for (final c in editorColorPalette) ...[
                  GestureDetector(
                    onTap: () => onSelectColor(c),
                    child: Container(
                      width: 36,
                      height: 36,
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selectedColor == c ? Colors.white : Colors.white24,
                          width: selectedColor == c ? 2.5 : 1.2,
                        ),
                      ),
                      child: selectedColor == c
                          ? Icon(
                              Icons.check_rounded,
                              size: 18,
                              color: c.computeLuminance() > 0.5
                                  ? Colors.black
                                  : Colors.white,
                            )
                          : null,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );

      case _DrawShelfTab.size:
        return Container(
          color: const Color(0xFF161616),
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 34,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned(
                      left: 16,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.white70, width: 1.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Icon(
                              Icons.line_weight_rounded,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Size',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Center(
                      child: Text(
                        '${strokeDiameter.round()} px',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    if ((strokeDiameter - DrawOverlay.kDefaultBrushDiameter).abs() > 1.0)
                      Positioned(
                        right: 16,
                        child: GestureDetector(
                          onTap: () => onStrokeDiameterChanged(DrawOverlay.kDefaultBrushDiameter),
                          child: const Icon(
                            Icons.refresh_rounded,
                            size: 18,
                            color: Colors.white70,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              _EditorLevelRuler(
                value: strokeDiameter,
                min: 4.0,
                max: 200.0,
                onChanged: onStrokeDiameterChanged,
              ),
            ],
          ),
        );

      case _DrawShelfTab.opacity:
        return Container(
          color: const Color(0xFF161616),
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 34,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned(
                      left: 16,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.white70, width: 1.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Icon(
                              Icons.unfold_more_rounded,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Opacity',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Center(
                      child: Text(
                        '${(opacity * 100).round()}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _EditorLevelRuler(
                value: opacity * 100.0,
                min: 0.0,
                max: 100.0,
                onChanged: (v) => onOpacityChanged(v / 100.0),
              ),
            ],
          ),
        );
    }
  }
}

// ── ANNOTATION CONTROLS (DRAW / TEXT / REDACT) ──────────────────────────────

class _AnnotationShelf extends StatelessWidget {
  final EditorTool activeTool;
  final Color currentColor;
  final ValueChanged<Color> onSetColor;
  final VoidCallback onShowStrokeWidthPicker;
  final VoidCallback onShowFontSizePicker;
  final VoidCallback onClearAll;
  final bool hasAnnotations;

  const _AnnotationShelf({
    required this.activeTool,
    required this.currentColor,
    required this.onSetColor,
    required this.onShowStrokeWidthPicker,
    required this.onShowFontSizePicker,
    required this.onClearAll,
    required this.hasAnnotations,
  });

  static const List<Color> _swatchColors = [
    Colors.white,
    Colors.black,
    Color(0xFFE53935), // Red
    Color(0xFFFDD835), // Yellow
    Color(0xFF43A047), // Green
    Color(0xFF1E88E5), // Blue
    Color(0xFF8E24AA), // Purple
    Color(0xFFFFB74D), // Orange
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF161616),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Color swatches row
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final color in _swatchColors)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: GestureDetector(
                      onTap: () => onSetColor(color),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: color == currentColor ? Colors.white : Colors.white24,
                            width: color == currentColor ? 2.5 : 1.0,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (activeTool == EditorTool.text)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Text(
                'Tap on the photo to place text',
                style: TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }
}

// ── PORTRAIT & LANDSCAPE OVERALL LAYOUT COMPOSITION ─────────────────────────

class _PortraitLayout extends StatelessWidget {
  const _PortraitLayout({
    required this.body,
    required this.hasError,
    required this.shelf,
    required this.bottomBar,
  });

  final Widget body;
  final bool hasError;
  final Widget shelf;
  final Widget bottomBar;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(child: body),
        if (!hasError)
          ColoredBox(
            color: const Color(0xFF161616),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  shelf,
                  bottomBar,
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _LandscapeLayout extends StatelessWidget {
  const _LandscapeLayout({
    required this.body,
    required this.hasError,
    required this.shelf,
    required this.bottomBar,
  });

  final Widget body;
  final bool hasError;
  final Widget shelf;
  final Widget bottomBar;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: body),
        if (!hasError)
          Container(
            width: 240,
            decoration: const BoxDecoration(
              color: Color(0xFF161616),
              border: Border(
                left: BorderSide(color: Color(0xFF262626), width: 0.8),
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(child: shelf),
                  ),
                  bottomBar,
                ],
              ),
            ),
          ),
      ],
    );
  }
}
