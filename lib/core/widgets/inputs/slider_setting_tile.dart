import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';

/// A settings row with a title, the current value on the right and a slider
/// underneath, for integer settings in [min]..[max] (one step per whole unit,
/// or [divisions] steps when given).
///
/// The slider drags smoothly on local state and only calls [onChanged] when
/// the drag ends, so a persisted setting is written once per adjustment, not
/// once per frame.
class SliderSettingTile extends StatefulWidget {
  final String label;
  final IconData? prefixIcon;
  final int value;
  final int min;
  final int max;
  final int? divisions;
  final String Function(int value) valueLabel;
  final ValueChanged<int> onChanged;

  const SliderSettingTile({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.valueLabel,
    required this.onChanged,
    this.divisions,
    this.prefixIcon,
  });

  @override
  State<SliderSettingTile> createState() => _SliderSettingTileState();
}

class _SliderSettingTileState extends State<SliderSettingTile> {
  late double _value;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _value = widget.value.toDouble();
  }

  @override
  void didUpdateWidget(covariant SliderSettingTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Follow the stored value unless the user is mid-drag.
    if (!_dragging && oldWidget.value != widget.value) {
      _value = widget.value.toDouble();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;
    final shown = _value.round();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (widget.prefixIcon != null) ...[
                Icon(
                  widget.prefixIcon,
                  size: AppIconSize.standard,
                  color: cs.primary,
                ),
                const SizedBox(width: 16),
              ],
              Expanded(
                child: Text(
                  widget.label,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                widget.valueLabel(shown),
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: cs.primary,
                ),
              ),
            ],
          ),
          Slider(
            value: _value.clamp(widget.min.toDouble(), widget.max.toDouble()),
            min: widget.min.toDouble(),
            max: widget.max.toDouble(),
            divisions: widget.divisions ?? (widget.max - widget.min),
            label: widget.valueLabel(shown),
            onChangeStart: (_) => _dragging = true,
            onChanged: (v) => setState(() => _value = v),
            onChangeEnd: (v) {
              _dragging = false;
              widget.onChanged(v.round());
            },
          ),
        ],
      ),
    );
  }
}
