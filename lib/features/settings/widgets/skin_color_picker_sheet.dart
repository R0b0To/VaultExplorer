import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/widgets/sheets/app_bottom_sheet.dart';

/// The result of [showSkinColorPicker].
///
/// Wrapping the color lets "the person chose Default" ([color] null) be told
/// apart from "the person dismissed the sheet" (the future completes with
/// null instead).
class SkinColorPick {
  final Color? color;
  const SkinColorPick(this.color);
}

/// Swatches offered by the picker. Deliberately includes white, black and a
/// few greys so names can be made high-contrast on any theme.
const List<Color> kSkinPalette = [
  Color(0xFFEF5350),
  Color(0xFFFF7043),
  Color(0xFFFFA726),
  Color(0xFFFFB300),
  Color(0xFFFFEE58),
  Color(0xFF9CCC65),
  Color(0xFF66BB6A),
  Color(0xFF26A69A),
  Color(0xFF26C6DA),
  Color(0xFF42A5F5),
  Color(0xFF5C6BC0),
  Color(0xFF7E57C2),
  Color(0xFFAB47BC),
  Color(0xFFEC407A),
  Color(0xFF8D6E63),
  Color(0xFF78909C),
  Color(0xFFBDBDBD),
  Color(0xFF616161),
  Color(0xFFFFFFFF),
  Color(0xFF000000),
];

/// `RRGGBB` for [color], without alpha or a leading `#`.
String skinColorToHex(Color color) => (color.toARGB32() & 0xFFFFFF)
    .toRadixString(16)
    .padLeft(6, '0')
    .toUpperCase();

/// Parses six hex digits (RGB) or eight (ARGB); null for other values.
Color? skinColorFromHex(String hex) {
  final value = hex.replaceFirst('#', '').trim();
  if (value.length != 6 && value.length != 8) return null;
  final parsed = int.tryParse(value, radix: 16);
  if (parsed == null) return null;
  return value.length == 6 ? Color(0xFF000000 | parsed) : Color(parsed);
}

/// Opens the picker. Completes with null if dismissed.
///
/// [allowDefault] adds a context.l10n.fileSkinColorDefault button that completes with
/// `SkinColorPick(null)`, for options where "follow the theme" is a valid
/// choice (names, details) as opposed to ones that always need a color.
Future<SkinColorPick?> showSkinColorPicker(
  BuildContext context, {
  required String title,
  Color? initial,
  bool allowDefault = true,
}) {
  return showModalBottomSheet<SkinColorPick>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _SkinColorPickerSheet(
      title: title,
      initial: initial,
      allowDefault: allowDefault,
    ),
  );
}

class _SkinColorPickerSheet extends StatefulWidget {
  final String title;
  final Color? initial;
  final bool allowDefault;

  const _SkinColorPickerSheet({
    required this.title,
    required this.initial,
    required this.allowDefault,
  });

  @override
  State<_SkinColorPickerSheet> createState() => _SkinColorPickerSheetState();
}

class _SkinColorPickerSheetState extends State<_SkinColorPickerSheet> {
  late final TextEditingController _hexController;
  late HSVColor _selected;
  Color? _typedColor;
  bool _showExactEntry = false;

  Color get _color => _selected.toColor();

  @override
  void initState() {
    super.initState();
    final initial = widget.initial ?? const Color(0xFF6487D9);
    _selected = HSVColor.fromColor(initial);
    _typedColor = initial;
    _hexController = TextEditingController(text: _hexText(initial));
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  String _hexText(Color color) {
    final argb = color.toARGB32();
    return ((argb >> 24) & 0xFF) == 0xFF
        ? skinColorToHex(color)
        : argb.toRadixString(16).padLeft(8, '0').toUpperCase();
  }

  void _pick(Color? color) => Navigator.of(context).pop(SkinColorPick(color));

  void _updateColor(Color color, {bool updateEntry = true}) {
    setState(() {
      _selected = HSVColor.fromColor(color);
      _typedColor = color;
      if (updateEntry) _hexController.text = _hexText(color);
    });
  }

  void _updateHsv(HSVColor color) {
    setState(() {
      _selected = color;
      _typedColor = color.toColor();
      _hexController.text = _hexText(_typedColor!);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return AppBottomSheet(
      child: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final availableWidth = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : MediaQuery.sizeOf(context).width - 40;
            final wheelSize = (availableWidth - 24)
                .clamp(220.0, 310.0)
                .toDouble();
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.title,
                            style: textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        _ColorSample(color: _color),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.l10n.skinDragAroundTheRingTo868d62,
                      style: textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: SizedBox.square(
                        dimension: wheelSize,
                        child: _HsvWheel(
                          value: _selected,
                          onChanged: _updateHsv,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.opacity_rounded, color: cs.onSurfaceVariant),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Slider(
                            value: _selected.alpha,
                            label: '${(_selected.alpha * 100).round()}%',
                            onChanged: (value) =>
                                _updateHsv(_selected.withAlpha(value)),
                          ),
                        ),
                        SizedBox(
                          width: 44,
                          child: Text(
                            '${(_selected.alpha * 100).round()}%',
                            textAlign: TextAlign.end,
                            style: textTheme.labelMedium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.l10n.skinQuickColors,
                      style: textTheme.labelLarge?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 11,
                      runSpacing: 11,
                      children: [
                        for (final color in kSkinPalette)
                          _Swatch(
                            color: color,
                            selected: _color.toARGB32() == color.toARGB32(),
                            onTap: () => _updateColor(color),
                          ),
                      ],
                    ),
                    Theme(
                      data: Theme.of(
                        context,
                      ).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        childrenPadding: EdgeInsets.zero,
                        initiallyExpanded: _showExactEntry,
                        onExpansionChanged: (expanded) =>
                            setState(() => _showExactEntry = expanded),
                        leading: const Icon(Icons.tag_rounded),
                        title: Text(context.l10n.skinEnterAnExactColor),
                        subtitle: Text(context.l10n.skinOptionalRGBOrARGBValue),
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _hexController,
                                  maxLength: 8,
                                  textCapitalization:
                                      TextCapitalization.characters,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                      RegExp('[0-9a-fA-F]'),
                                    ),
                                  ],
                                  decoration: InputDecoration(
                                    labelText: context.l10n.skinRGBARGB,
                                    prefixText: '#',
                                    counterText: '',
                                  ),
                                  onChanged: (value) => setState(() {
                                    _typedColor = skinColorFromHex(value);
                                  }),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: _ColorSample(
                                  color: _typedColor ?? Colors.transparent,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: IconButton.filledTonal(
                                  tooltip: context.l10n.skinUseThisValue,
                                  onPressed: _typedColor == null
                                      ? null
                                      : () => _updateColor(
                                          _typedColor!,
                                          updateEntry: false,
                                        ),
                                  icon: const Icon(Icons.check_rounded),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (widget.allowDefault) ...[
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => _pick(null),
                          icon: const Icon(Icons.restart_alt_rounded),
                          label: Text(context.l10n.fileSkinColorDefault),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: () => _pick(_color),
                      child: Text(context.l10n.done),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _HsvWheel extends StatefulWidget {
  final HSVColor value;
  final ValueChanged<HSVColor> onChanged;

  const _HsvWheel({required this.value, required this.onChanged});

  @override
  State<_HsvWheel> createState() => _HsvWheelState();
}

class _HsvWheelState extends State<_HsvWheel> {
  _WheelDragMode? _dragMode;

  void _start(Offset position, Size size) {
    _dragMode = null;
    final geometry = _WheelGeometry.fromSize(size);
    final distance = (position - geometry.center).distance;
    if (geometry.square.contains(position)) {
      _dragMode = _WheelDragMode.shade;
      _update(position, size);
    } else if (distance >= geometry.innerRadius - 9 &&
        distance <= geometry.radius + 9) {
      _dragMode = _WheelDragMode.hue;
      _update(position, size);
    }
  }

  void _update(Offset position, Size size) {
    final geometry = _WheelGeometry.fromSize(size);
    switch (_dragMode) {
      case _WheelDragMode.hue:
        final delta = position - geometry.center;
        final degrees =
            (math.atan2(delta.dy, delta.dx) * 180 / math.pi + 90) % 360;
        widget.onChanged(widget.value.withHue((degrees + 360) % 360));
        return;
      case _WheelDragMode.shade:
        final saturation =
            ((position.dx - geometry.square.left) / geometry.square.width)
                .clamp(0.0, 1.0);
        final value =
            (1 - (position.dy - geometry.square.top) / geometry.square.height)
                .clamp(0.0, 1.0);
        widget.onChanged(
          widget.value.withSaturation(saturation).withValue(value),
        );
        return;
      case null:
        return;
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => RawGestureDetector(
      gestures: {
        EagerGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
              EagerGestureRecognizer.new,
              (recognizer) {},
            ),
      },
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) =>
            _start(event.localPosition, constraints.biggest),
        onPointerMove: (event) {
          if (_dragMode != null) {
            _update(event.localPosition, constraints.biggest);
          }
        },
        onPointerUp: (_) => _dragMode = null,
        onPointerCancel: (_) => _dragMode = null,
        child: CustomPaint(
          painter: _HsvWheelPainter(widget.value),
          child: const SizedBox.expand(),
        ),
      ),
    ),
  );
}

enum _WheelDragMode { hue, shade }

class _WheelGeometry {
  final Offset center;
  final double radius;
  final double innerRadius;
  final Rect square;

  const _WheelGeometry({
    required this.center,
    required this.radius,
    required this.innerRadius,
    required this.square,
  });

  factory _WheelGeometry.fromSize(Size size) {
    final diameter = math.min(size.width, size.height).toDouble();
    final center = Offset(size.width / 2, size.height / 2);
    final radius = diameter * 0.48;
    final innerRadius = radius * 0.73;
    final squareSide = innerRadius * 1.36;
    return _WheelGeometry(
      center: center,
      radius: radius,
      innerRadius: innerRadius,
      square: Rect.fromCenter(
        center: center,
        width: squareSide,
        height: squareSide,
      ),
    );
  }
}

class _HsvWheelPainter extends CustomPainter {
  final HSVColor value;

  const _HsvWheelPainter(this.value);

  @override
  void paint(Canvas canvas, Size size) {
    final geometry = _WheelGeometry.fromSize(size);
    final outerRect = Rect.fromCircle(
      center: geometry.center,
      radius: geometry.radius,
    );
    final innerRect = Rect.fromCircle(
      center: geometry.center,
      radius: geometry.innerRadius,
    );
    const segmentCount = 360;
    final segmentSweep = 2 * math.pi / segmentCount;
    for (var degree = 0; degree < segmentCount; degree++) {
      final start = -math.pi / 2 + degree * segmentSweep;
      final end = start + segmentSweep;
      final innerEnd = Offset(
        geometry.center.dx + math.cos(end) * geometry.innerRadius,
        geometry.center.dy + math.sin(end) * geometry.innerRadius,
      );
      final slice = Path()
        ..moveTo(
          geometry.center.dx + math.cos(start) * geometry.radius,
          geometry.center.dy + math.sin(start) * geometry.radius,
        )
        ..arcTo(outerRect, start, segmentSweep, false)
        ..lineTo(innerEnd.dx, innerEnd.dy)
        ..arcTo(innerRect, end, -segmentSweep, false)
        ..close();
      canvas.drawPath(
        slice,
        Paint()
          ..color = HSVColor.fromAHSV(1, degree.toDouble(), 1, 1).toColor(),
      );
    }

    final hueColor = HSVColor.fromAHSV(1, value.hue, 1, 1).toColor();
    final square = geometry.square;
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(square, const Radius.circular(5)));
    canvas.drawRect(
      square,
      Paint()
        ..shader = LinearGradient(
          colors: [Colors.white, hueColor],
        ).createShader(square),
    );
    canvas.drawRect(
      square,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black],
        ).createShader(square),
    );
    canvas.restore();

    final hueAngle = (value.hue - 90) * math.pi / 180;
    final hueMarker = Offset(
      geometry.center.dx +
          math.cos(hueAngle) * (geometry.radius + geometry.innerRadius) / 2,
      geometry.center.dy +
          math.sin(hueAngle) * (geometry.radius + geometry.innerRadius) / 2,
    );
    _drawMarker(canvas, hueMarker, 8);

    final shadeMarker = Offset(
      square.left + value.saturation * square.width,
      square.top + (1 - value.value) * square.height,
    );
    _drawMarker(canvas, shadeMarker, 7);
  }

  void _drawMarker(Canvas canvas, Offset point, double radius) {
    canvas.drawCircle(
      point,
      radius + 1,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.65)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.drawCircle(
      point,
      radius,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _HsvWheelPainter oldDelegate) =>
      oldDelegate.value != value;
}

class _ColorSample extends StatelessWidget {
  final Color color;

  const _ColorSample({required this.color});

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.outlineVariant;
    return Tooltip(
      message: '#${skinColorToHex(color)}',
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: outline, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _Swatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkResponse(
      onTap: onTap,
      radius: 25,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? cs.primary : cs.outlineVariant,
            width: selected ? 3 : 1,
          ),
        ),
        child: selected
            ? Icon(
                Icons.check_rounded,
                size: 19,
                color: color.computeLuminance() > 0.5
                    ? Colors.black
                    : Colors.white,
              )
            : null,
      ),
    );
  }
}
