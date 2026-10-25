import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/features/settings/widgets/skin_color_picker_sheet.dart';

/// A color editor that lives inside the floating panel instead of a modal
/// sheet, so the app stays visible and every change shows up as it is made.
///
/// Every change is reported immediately through [onChanged]; there is no
/// "apply" step. The editor keeps its own hue/saturation state while it is
/// being dragged (a color wheel cannot be rebuilt from an RGB value without
/// losing the hue at black and white), and only re-reads [color] when it was
/// changed from outside (undo, reset, another color selected).
class SkinInlineColorEditor extends StatefulWidget {
  final Color color;
  final ValueChanged<Color> onChanged;

  const SkinInlineColorEditor({
    super.key,
    required this.color,
    required this.onChanged,
  });

  @override
  State<SkinInlineColorEditor> createState() => _SkinInlineColorEditorState();
}

class _SkinInlineColorEditorState extends State<SkinInlineColorEditor> {
  late HSVColor _hsv;
  late int _lastEmitted;
  late final TextEditingController _hex;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.color);
    _lastEmitted = widget.color.toARGB32();
    _hex = TextEditingController(text: _hexText(widget.color));
  }

  @override
  void didUpdateWidget(SkinInlineColorEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Our own change comes straight back as the new color; anything else was
    // done elsewhere (undo, reset) and has to be shown.
    if (widget.color.toARGB32() != _lastEmitted) {
      _hsv = HSVColor.fromColor(widget.color);
      _lastEmitted = widget.color.toARGB32();
      _hex.text = _hexText(widget.color);
    }
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  String _hexText(Color color) {
    final argb = color.toARGB32();
    return ((argb >> 24) & 0xFF) == 0xFF
        ? skinColorToHex(color)
        : argb.toRadixString(16).padLeft(8, '0').toUpperCase();
  }

  void _emit(HSVColor hsv, {bool updateHex = true}) {
    final color = hsv.toColor();
    setState(() {
      _hsv = hsv;
      _lastEmitted = color.toARGB32();
      if (updateHex) _hex.text = _hexText(color);
    });
    widget.onChanged(color);
  }

  void _emitColor(Color color) => _emit(HSVColor.fromColor(color));

  void _onHexChanged(String value) {
    final color = skinColorFromHex(value);
    if (color == null) return;
    _emit(HSVColor.fromColor(color), updateHex: false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final current = _hsv.toColor();

    Widget alphaRow() => Row(
      children: [
        Icon(Icons.opacity_rounded, size: 20, color: cs.onSurfaceVariant),
        Expanded(
          child: Slider(
            value: _hsv.alpha,
            onChanged: (value) => _emit(_hsv.withAlpha(value)),
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            '${(_hsv.alpha * 100).round()}%',
            textAlign: TextAlign.end,
            style: textTheme.labelMedium,
          ),
        ),
      ],
    );

    Widget hexField() => Row(
      children: [
        Expanded(
          child: TextField(
            controller: _hex,
            maxLength: 8,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F]')),
            ],
            decoration: InputDecoration(
              labelText: context.l10n.skinRGBARGB,
              prefixText: '#',
              counterText: '',
              isDense: true,
            ),
            onChanged: _onHexChanged,
          ),
        ),
        const SizedBox(width: 10),
        SkinColorSample(color: current),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // Side by side when there is room; stacked on a narrow panel.
        final wide = constraints.maxWidth >= 330;
        final wheelSize = wide ? 150.0 : 160.0;
        final wheel = SizedBox.square(
          dimension: wheelSize,
          child: SkinHsvWheel(value: _hsv, onChanged: _emit),
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  wheel,
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [alphaRow(), const SizedBox(height: 6), hexField()],
                    ),
                  ),
                ],
              )
            else ...[
              Center(child: wheel),
              alphaRow(),
              hexField(),
            ],
            const SizedBox(height: 10),
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: kSkinPalette.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final color = kSkinPalette[index];
                  return Center(
                    child: SkinColorSwatch(
                      color: color,
                      selected: current.toARGB32() == color.toARGB32(),
                      onTap: () => _emitColor(color),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
