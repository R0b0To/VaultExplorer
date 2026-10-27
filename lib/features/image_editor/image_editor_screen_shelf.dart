part of 'image_editor_screen.dart';

// ── PHOTO STUDIO SPECIFICATIONS & TYPES ─────────────────────────────────────

enum _TuneParam { brightness, contrast, saturation, ambiance, warmth, shadows }

extension _TuneParamX on _TuneParam {
  String getLocalizedLabel(AppLocalizations l10n) => switch (this) {
    _TuneParam.brightness => l10n.adjustmentBrightness,
    _TuneParam.contrast => l10n.adjustmentContrast,
    _TuneParam.saturation => l10n.adjustmentSaturation,
    _TuneParam.ambiance => l10n.imageEditorTuneAmbiance,
    _TuneParam.warmth => l10n.imageEditorTuneWarmth,
    _TuneParam.shadows => l10n.imageEditorTuneShadows,
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

  String getLocalizedLabel(AppLocalizations l10n) => switch (id) {
    'original' => l10n.imageEditorLookCurrent,
    'portrait' => l10n.imageEditorLookPortrait,
    'vivid' => l10n.adjustmentPresetVivid,
    'bw' => l10n.adjustmentPresetBlackAndWhite,
    'warm' => l10n.adjustmentPresetWarm,
    'cool' => l10n.adjustmentPresetCool,
    'dramatic' => l10n.imageEditorLookDramatic,
    'vintage' => l10n.imageEditorLookVintage,
    _ => label,
  };
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
  _LookPreset(id: 'warm', label: 'Warm', adjustments: ViewerAdjustments.warm),
  _LookPreset(id: 'cool', label: 'Cool', adjustments: ViewerAdjustments.cool),
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

  String _toolTitle(BuildContext context, EditorTool tool) {
    final l10n = context.l10n;
    return switch (tool) {
      EditorTool.crop => l10n.cropToolLabel,
      EditorTool.tuneImage => l10n.imageEditorTuneImageToolLabel,
      EditorTool.looks => l10n.imageEditorLooksToolLabel,
      EditorTool.draw => l10n.drawToolLabel,
      EditorTool.text => l10n.textToolLabel,
      EditorTool.redact => l10n.redactToolLabel,
      EditorTool.none => fileName,
    };
  }

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
                      icon: const Icon(
                        Icons.arrow_back_rounded,
                        color: Colors.white,
                      ),
                      tooltip: context.l10n.goBack,
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
                      tooltip: context.l10n.undoTooltip,
                      onPressed: canUndo ? onUndo : null,
                    ),
                    if (allowSequentialCapture && onContinueCapture != null)
                      IconButton(
                        icon: const Icon(
                          Icons.add_a_photo_outlined,
                          color: Colors.white,
                        ),
                        tooltip: context.l10n.add,
                        onPressed: onContinueCapture,
                      ),
                    PopupMenuButton<String>(
                      icon: const Icon(
                        Icons.more_vert_rounded,
                        color: Colors.white,
                      ),
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
                            children: [
                              const Icon(
                                Icons.save_alt_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                context.l10n.imageEditorExportSave,
                                style: const TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                        if (hasEdits)
                          PopupMenuItem(
                            value: 'reset',
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.restart_alt_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  context.l10n.imageEditorRevertOriginal,
                                  style: const TextStyle(color: Colors.white),
                                ),
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
                        _toolTitle(context, activeTool),
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
                          isComparing
                              ? Icons.visibility
                              : Icons.visibility_outlined,
                          color: isComparing
                              ? const Color(0xFF38BDF8)
                              : Colors.white,
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

// ── TOOLS ROW ───────────────────────────────────────────────────────────────

class _EditorToolsRow extends StatelessWidget {
  final EditorTool activeTool;
  final void Function(EditorTool) onSelectTool;

  const _EditorToolsRow({required this.activeTool, required this.onSelectTool});

  Widget _buildToolItem({
    required IconData icon,
    required String label,
    required EditorTool tool,
    required bool isLandscape,
  }) {
    final selected = activeTool == tool;
    return SizedBox(
      width: isLandscape ? 70 : null,
      child: InkWell(
        onTap: () => onSelectTool(tool),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isLandscape ? 3 : 10,
            vertical: 8,
          ),
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
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? const Color(0xFF38BDF8) : Colors.white70,
                  fontSize: isLandscape ? 10 : 11,
                  fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final tools = [
      _buildToolItem(
        icon: Icons.filter_vintage_rounded,
        label: l10n.imageEditorLooksToolLabel,
        tool: EditorTool.looks,
        isLandscape: isLandscape,
      ),
      _buildToolItem(
        icon: Icons.tune_rounded,
        label: l10n.imageEditorTuneImageToolLabel,
        tool: EditorTool.tuneImage,
        isLandscape: isLandscape,
      ),
      _buildToolItem(
        icon: Icons.crop_rounded,
        label: l10n.cropToolLabel,
        tool: EditorTool.crop,
        isLandscape: isLandscape,
      ),
      _buildToolItem(
        icon: Icons.brush_rounded,
        label: l10n.drawToolLabel,
        tool: EditorTool.draw,
        isLandscape: isLandscape,
      ),
      _buildToolItem(
        icon: Icons.text_fields_rounded,
        label: l10n.textToolLabel,
        tool: EditorTool.text,
        isLandscape: isLandscape,
      ),
      _buildToolItem(
        icon: Icons.visibility_off_outlined,
        label: l10n.redactToolLabel,
        tool: EditorTool.redact,
        isLandscape: isLandscape,
      ),
    ];
    return Container(
      color: const Color(0xFF161616),
      padding: EdgeInsets.symmetric(
        vertical: 6,
        horizontal: isLandscape ? 4 : 0,
      ),
      child: isLandscape
          ? Wrap(
              alignment: WrapAlignment.center,
              runAlignment: WrapAlignment.center,
              children: tools,
            )
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: tools,
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
    final l10n = context.l10n;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    if (isLandscape) {
      return Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          color: Color(0xFF161616),
          border: Border(top: BorderSide(color: Color(0xFF262626), width: 0.8)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (centerActions.isNotEmpty)
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 4,
                runSpacing: 2,
                children: [
                  for (final action in centerActions)
                    SizedBox(
                      width: 88,
                      height: 50,
                      child: Center(child: action),
                    ),
                ],
              ),
            SizedBox(
              height: 50,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                    tooltip: l10n.cancel,
                    onPressed: onCancel,
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                    tooltip: l10n.done,
                    onPressed: onApply,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      height: 54,
      decoration: const BoxDecoration(
        color: Color(0xFF161616),
        border: Border(top: BorderSide(color: Color(0xFF262626), width: 0.8)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(
              Icons.close_rounded,
              color: Colors.white,
              size: 24,
            ),
            tooltip: l10n.cancel,
            onPressed: onCancel,
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: centerActions,
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.check_rounded,
              color: Colors.white,
              size: 24,
            ),
            tooltip: l10n.done,
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
    final compact = MediaQuery.of(context).orientation == Orientation.landscape;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 10,
          vertical: compact ? 0 : 2,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: compact ? 26 : 30,
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
            SizedBox(height: compact ? 1 : 2),
            Text(
              label,
              maxLines: compact ? 1 : null,
              overflow: compact ? TextOverflow.ellipsis : null,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontSize: compact ? 9 : 10,
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
    final newVal = (_dragStartValue! + deltaValue).clamp(
      widget.min,
      widget.max,
    );
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
          onHorizontalDragStart: (details) =>
              _handleDragStart(details.localPosition),
          onHorizontalDragUpdate: (details) =>
              _handleDragUpdate(details.localPosition, w),
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
      oldDelegate.value != value ||
      oldDelegate.min != min ||
      oldDelegate.max != max;
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
    final l10n = context.l10n;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final currentAspect = cropBoxSize == null
        ? 1.0
        : cropBoxSize!.width / cropBoxSize!.height;

    final formattedAngle = angle.abs() < 0.005
        ? '0.00°'
        : '${angle > 0 ? '+' : ''}${angle.toStringAsFixed(2)}°';

    final aspects = [
      (
        label: l10n.cropAspectFreeLabel,
        icon: Icons.crop_free_rounded,
        ratio: null,
      ),
      (
        label: l10n.cropAspectOriginalLabel,
        icon: Icons.crop_original_rounded,
        ratio: currentAspect,
      ),
      (
        label: l10n.cropAspectSquareLabel,
        icon: Icons.crop_square_rounded,
        ratio: 1.0,
      ),
      (
        label: l10n.imageEditorCropAspectDin,
        icon: Icons.description_outlined,
        ratio: 1.0 / 1.414,
      ),
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
                      Text(
                        l10n.imageEditorAngle,
                        style: const TextStyle(
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
          if (isLandscape)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final item in aspects)
                    _AspectCard(
                      icon: item.icon,
                      label: item.label,
                      selected: item.ratio == null
                          ? cropAspectRatio == null
                          : (cropAspectRatio != null &&
                                (cropAspectRatio! - item.ratio!).abs() < 0.01),
                      onTap: () => onSetCropAspect(item.ratio),
                    ),
                ],
              ),
            )
          else
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 4,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: Colors.white70,
                                width: 1.2,
                              ),
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
                            param.getLocalizedLabel(context.l10n),
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
                            color: p == selectedParam
                                ? Colors.black
                                : Colors.white70,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            p.getLocalizedLabel(context.l10n),
                            style: TextStyle(
                              color: p == selectedParam
                                  ? Colors.black
                                  : Colors.white,
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
                              color: p == selectedParam
                                  ? Colors.black
                                  : Colors.white70,
                              fontSize: 13,
                              fontWeight: p == selectedParam
                                  ? FontWeight.w700
                                  : FontWeight.normal,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
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

  Widget _presetTile(
    BuildContext context,
    _LookPreset preset, {
    required bool compact,
  }) {
    final isSelected = preset.id == selectedPresetId;
    final previewSize = compact ? 48.0 : 54.0;
    return SizedBox(
      width: compact ? 92 : null,
      child: GestureDetector(
        onTap: () => onSelectPreset(preset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: previewSize,
              height: previewSize,
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
                  size: compact ? 20 : 22,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              preset.getLocalizedLabel(context.l10n),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontSize: compact ? 10 : 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    if (isLandscape) {
      return Container(
        color: const Color(0xFF161616),
        padding: const EdgeInsets.all(8),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 6,
          runSpacing: 8,
          children: [
            for (final preset in _kLookPresets)
              _presetTile(context, preset, compact: true),
          ],
        ),
      );
    }

    return Container(
      color: const Color(0xFF161616),
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: SizedBox(
        height: 90,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          itemCount: _kLookPresets.length,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (context, index) =>
              _presetTile(context, _kLookPresets[index], compact: false),
        ),
      ),
    );
  }
}

// ── TEXT SHELF (STYLE / COLOR / OPACITY TABS) ───────────────────────────────

Future<void> _showImageEditorColorPicker(
  BuildContext context, {
  required Color color,
  required ValueChanged<Color> onChanged,
  ValueChanged<bool>? onInteraction,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF202020),
    isScrollControlled: true,
    builder: (sheetContext) {
      final maxHeight = MediaQuery.of(sheetContext).size.height * 0.9;
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ImageEditorColorPicker(
                  color: color,
                  onChanged: onChanged,
                  onInteraction: onInteraction,
                  maxWheelDiameter: 260,
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    child: Text(sheetContext.l10n.done),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  onInteraction?.call(false);
}

Widget _imageEditorCustomColorOption(
  BuildContext context, {
  required Color color,
  required bool compact,
  ValueChanged<bool>? onInteraction,
  required ValueChanged<Color> onChanged,
}) {
  final size = compact ? 32.0 : 36.0;
  return SizedBox(
    width: compact ? 40 : null,
    child: Center(
      child: Tooltip(
        message: context.l10n.imageEditorActionColor,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => _showImageEditorColorPicker(
            context,
            color: color,
            onChanged: onChanged,
            onInteraction: onInteraction,
          ),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white70, width: 1.5),
            ),
            child: Icon(
              Icons.colorize_rounded,
              size: compact ? 16 : 18,
              color: color.computeLuminance() > 0.5
                  ? Colors.black
                  : Colors.white,
            ),
          ),
        ),
      ),
    ),
  );
}

class _ImageEditorColorPicker extends StatefulWidget {
  final Color color;
  final ValueChanged<Color> onChanged;
  final ValueChanged<bool>? onInteraction;
  final double maxWheelDiameter;

  const _ImageEditorColorPicker({
    required this.color,
    required this.onChanged,
    required this.maxWheelDiameter,
    this.onInteraction,
  });

  @override
  State<_ImageEditorColorPicker> createState() =>
      _ImageEditorColorPickerState();
}

class _ImageEditorColorPickerState extends State<_ImageEditorColorPicker> {
  late HSVColor _hsv;
  late int _lastEmitted;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.color);
    _lastEmitted = widget.color.toARGB32();
  }

  @override
  void didUpdateWidget(_ImageEditorColorPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.color.toARGB32() != _lastEmitted) {
      _hsv = HSVColor.fromColor(widget.color);
      _lastEmitted = widget.color.toARGB32();
    }
  }

  void _emit(HSVColor value) {
    final color = value.toColor();
    setState(() {
      _hsv = value;
      _lastEmitted = color.toARGB32();
    });
    widget.onChanged(color);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final availableWidth = constraints.maxWidth.isFinite
          ? constraints.maxWidth
          : MediaQuery.of(context).size.width;
      final diameter = math.min(
        widget.maxWheelDiameter,
        math.max(120.0, availableWidth - 24),
      );
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: SizedBox.square(
              dimension: diameter,
              child: SkinHsvWheel(
                value: _hsv,
                onChanged: _emit,
                onInteraction: widget.onInteraction,
              ),
            ),
          ),
          Row(
            children: [
              const Icon(
                Icons.opacity_rounded,
                size: 20,
                color: Colors.white70,
              ),
              Expanded(
                child: Slider(
                  value: _hsv.alpha,
                  onChangeStart: (_) => widget.onInteraction?.call(true),
                  onChanged: (value) => _emit(_hsv.withAlpha(value)),
                  onChangeEnd: (_) => widget.onInteraction?.call(false),
                ),
              ),
              SizedBox(
                width: 40,
                child: Text(
                  '${(_hsv.alpha * 100).round()}%',
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    },
  );
}

enum _TextShelfTab { color, opacity, style }

class _TextShelf extends StatelessWidget {
  final _TextShelfTab tab;
  final TextMarkAnnotation textAnnotation;
  final ValueChanged<String> onSelectStyle;
  final ValueChanged<Color> onSelectColor;
  final ValueChanged<double> onOpacityChanged;
  final ValueChanged<bool>? onColorInteraction;

  const _TextShelf({
    required this.tab,
    required this.textAnnotation,
    required this.onSelectStyle,
    required this.onSelectColor,
    required this.onOpacityChanged,
    this.onColorInteraction,
  });

  Widget _styleOption(TextStylePreset preset, {required bool compact}) {
    final selected = textAnnotation.styleId == preset.id;
    return SizedBox(
      width: compact ? 82 : null,
      child: GestureDetector(
        onTap: () => onSelectStyle(preset.id),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: compact ? 2 : 5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: compact ? 48 : 54,
                height: compact ? 48 : 54,
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.12)
                      : Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: selected ? Colors.white : Colors.white24,
                    width: selected ? 1.8 : 1.0,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  preset.previewText,
                  style: getTextStyleForPreset(
                    styleId: preset.id,
                    fontSize: compact ? 13 : 15,
                    color: selected ? Colors.white : Colors.white70,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                preset.label,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white60,
                  fontSize: compact ? 10 : 11,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _colorOption(Color color, {required bool compact}) {
    final selected = textAnnotation.color == color;
    final size = compact ? 32.0 : 36.0;
    return SizedBox(
      width: compact ? 36 : null,
      child: GestureDetector(
        onTap: () => onSelectColor(color),
        child: Container(
          width: size,
          height: size,
          margin: EdgeInsets.symmetric(horizontal: compact ? 2 : 6),
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? Colors.white : Colors.white24,
              width: selected ? 2.5 : 1.2,
            ),
          ),
          child: selected
              ? Icon(
                  Icons.check_rounded,
                  size: 18,
                  color: color.computeLuminance() > 0.5
                      ? Colors.black
                      : Colors.white,
                )
              : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    switch (tab) {
      case _TextShelfTab.style:
        return Container(
          color: const Color(0xFF161616),
          padding: EdgeInsets.all(isLandscape ? 8 : 0),
          child: isLandscape
              ? Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 4,
                  runSpacing: 8,
                  children: [
                    for (final preset in kTextPresets)
                      _styleOption(preset, compact: true),
                  ],
                )
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      for (final preset in kTextPresets) ...[
                        _styleOption(preset, compact: false),
                      ],
                    ],
                  ),
                ),
        );

      case _TextShelfTab.color:
        return Container(
          color: const Color(0xFF161616),
          padding: EdgeInsets.all(isLandscape ? 8 : 0),
          child: isLandscape
              ? _ImageEditorColorPicker(
                  color: textAnnotation.color,
                  onChanged: onSelectColor,
                  onInteraction: onColorInteraction,
                  maxWheelDiameter: 190,
                )
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      _imageEditorCustomColorOption(
                        context,
                        color: textAnnotation.color,
                        compact: false,
                        onInteraction: onColorInteraction,
                        onChanged: onSelectColor,
                      ),
                      for (final color in editorColorPalette)
                        _colorOption(color, compact: false),
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
                              border: Border.all(
                                color: Colors.white70,
                                width: 1.2,
                              ),
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
                            context.l10n.imageEditorActionOpacity,
                            style: const TextStyle(
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
  final ValueChanged<bool>? onColorInteraction;

  const _DrawShelf({
    required this.tab,
    required this.selectedColor,
    required this.opacity,
    required this.strokeDiameter,
    required this.onSelectColor,
    required this.onOpacityChanged,
    required this.onStrokeDiameterChanged,
    this.onColorInteraction,
  });

  Widget _colorOption(Color color, {required bool compact}) {
    final selected = selectedColor == color;
    final size = compact ? 32.0 : 36.0;
    return SizedBox(
      width: compact ? 36 : null,
      child: GestureDetector(
        onTap: () => onSelectColor(color),
        child: Container(
          width: size,
          height: size,
          margin: EdgeInsets.symmetric(horizontal: compact ? 2 : 6),
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? Colors.white : Colors.white24,
              width: selected ? 2.5 : 1.2,
            ),
          ),
          child: selected
              ? Icon(
                  Icons.check_rounded,
                  size: 18,
                  color: color.computeLuminance() > 0.5
                      ? Colors.black
                      : Colors.white,
                )
              : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    switch (tab) {
      case _DrawShelfTab.color:
        return Container(
          color: const Color(0xFF161616),
          padding: EdgeInsets.all(isLandscape ? 8 : 0),
          child: isLandscape
              ? _ImageEditorColorPicker(
                  color: selectedColor,
                  onChanged: onSelectColor,
                  onInteraction: onColorInteraction,
                  maxWheelDiameter: 190,
                )
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      _imageEditorCustomColorOption(
                        context,
                        color: selectedColor,
                        compact: false,
                        onInteraction: onColorInteraction,
                        onChanged: onSelectColor,
                      ),
                      for (final color in editorColorPalette)
                        _colorOption(color, compact: false),
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
                              border: Border.all(
                                color: Colors.white70,
                                width: 1.2,
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Icon(
                              Icons.line_weight_rounded,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            context.l10n.imageEditorActionSize,
                            style: const TextStyle(
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
                    if ((strokeDiameter - DrawOverlay.kDefaultBrushDiameter)
                            .abs() >
                        1.0)
                      Positioned(
                        right: 16,
                        child: GestureDetector(
                          onTap: () => onStrokeDiameterChanged(
                            DrawOverlay.kDefaultBrushDiameter,
                          ),
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
                              border: Border.all(
                                color: Colors.white70,
                                width: 1.2,
                              ),
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
                            context.l10n.imageEditorActionOpacity,
                            style: const TextStyle(
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

// ── REDACT SHELF (COLOR PALETTE) ───────────────────────────────────────────

class _RedactShelf extends StatelessWidget {
  final Color selectedColor;
  final ValueChanged<Color> onSelectColor;
  final ValueChanged<bool>? onColorInteraction;

  const _RedactShelf({
    required this.selectedColor,
    required this.onSelectColor,
    this.onColorInteraction,
  });

  static const List<Color> _swatchColors = [
    Colors.black,
    Colors.white,
    Color(0xFFEF4444), // Red
    Color(0xFFF97316), // Orange
    Color(0xFFFBBF24), // Yellow
    Color(0xFF22C55E), // Green
    Color(0xFF06B6D4), // Cyan
    Color(0xFF3B82F6), // Blue
    Color(0xFFA855F7), // Purple
    Color(0xFFEC4899), // Pink
  ];

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    return Container(
      color: const Color(0xFF161616),
      padding: EdgeInsets.symmetric(
        horizontal: isLandscape ? 8 : 16,
        vertical: 8,
      ),
      child: isLandscape
          ? _ImageEditorColorPicker(
              color: selectedColor,
              onChanged: onSelectColor,
              onInteraction: onColorInteraction,
              maxWheelDiameter: 190,
            )
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _imageEditorCustomColorOption(
                    context,
                    color: selectedColor,
                    compact: false,
                    onInteraction: onColorInteraction,
                    onChanged: onSelectColor,
                  ),
                  for (final color in _swatchColors) _swatch(color),
                ],
              ),
            ),
    );
  }

  Widget _swatch(Color color) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: GestureDetector(
      onTap: () => onSelectColor(color),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: color.toARGB32() == selectedColor.toARGB32()
                ? const Color(0xFF38BDF8)
                : Colors.white24,
            width: color.toARGB32() == selectedColor.toARGB32() ? 2.5 : 1.0,
          ),
        ),
      ),
    ),
  );
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
                children: [shelf, bottomBar],
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
    required this.isTuneImage,
    required this.onTunePointerDown,
    required this.onTunePointerMove,
    required this.onTunePointerUp,
    required this.onTunePointerCancel,
  });

  final Widget body;
  final bool hasError;
  final Widget shelf;
  final Widget bottomBar;
  final bool isTuneImage;
  final ValueChanged<PointerDownEvent> onTunePointerDown;
  final ValueChanged<PointerMoveEvent> onTunePointerMove;
  final ValueChanged<PointerUpEvent> onTunePointerUp;
  final ValueChanged<PointerCancelEvent> onTunePointerCancel;

  @override
  Widget build(BuildContext context) {
    final panelWidth = (MediaQuery.of(context).size.width * 0.32).clamp(
      220.0,
      360.0,
    );
    return Row(
      children: [
        Expanded(child: body),
        if (!hasError)
          Container(
            width: panelWidth,
            decoration: const BoxDecoration(
              color: Color(0xFF161616),
              border: Border(
                left: BorderSide(color: Color(0xFF262626), width: 0.8),
              ),
            ),
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: isTuneImage
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              shelf,
                              Expanded(
                                child: Listener(
                                  behavior: HitTestBehavior.translucent,
                                  onPointerDown: onTunePointerDown,
                                  onPointerMove: onTunePointerMove,
                                  onPointerUp: onTunePointerUp,
                                  onPointerCancel: onTunePointerCancel,
                                  child: const ColoredBox(
                                    color: Color(0xFF161616),
                                    child: SizedBox.expand(),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : SingleChildScrollView(child: shelf),
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
