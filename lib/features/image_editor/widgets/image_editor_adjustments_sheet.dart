import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/features/browser/viewer/models/viewer_adjustments.dart';

enum _EditorAdjustmentControl { brightness, contrast, saturation, hue }

const _editorWarmAdjustment = ViewerAdjustments(
  contrast: 1.05,
  saturation: 1.08,
  hue: 9,
);

/// Color and filter controls for the image editor. Changes preview immediately
/// through [onChanged]; Done returns the selected adjustment for baking into
/// the working image, while Cancel leaves the image untouched.
class ImageEditorAdjustmentsSheet extends StatefulWidget {
  const ImageEditorAdjustmentsSheet({
    super.key,
    required this.initialValue,
    required this.onChanged,
  });

  final ViewerAdjustments initialValue;
  final ValueChanged<ViewerAdjustments> onChanged;

  @override
  State<ImageEditorAdjustmentsSheet> createState() =>
      _ImageEditorAdjustmentsSheetState();
}

class _ImageEditorAdjustmentsSheetState
    extends State<ImageEditorAdjustmentsSheet> {
  late ViewerAdjustments _adjustments = widget.initialValue;
  _EditorAdjustmentControl _selectedControl =
      _EditorAdjustmentControl.saturation;

  static double _snap(double value, double neutral, double min, double max) =>
      (value - neutral).abs() < (max - min) * 0.02 ? neutral : value;

  static String _signed(int value) => value > 0 ? '+$value' : '$value';

  void _set(ViewerAdjustments value) {
    setState(() => _adjustments = value);
    widget.onChanged(value);
  }

  Widget _presetChip({
    required String label,
    required ViewerAdjustments value,
  }) {
    final selected = _adjustments == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) {
        HapticFeedback.selectionClick();
        _set(selected ? ViewerAdjustments.identity : value);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final adj = _adjustments;
    final slider = switch (_selectedControl) {
      _EditorAdjustmentControl.brightness => (
        label: l10n.adjustmentBrightness,
        value: adj.brightness,
        valueText: _signed((adj.brightness * 100).round()),
        min: ViewerAdjustments.minBrightness,
        max: ViewerAdjustments.maxBrightness,
        neutral: ViewerAdjustments.neutralBrightness,
        onChanged: (double v) => _set(
          adj.copyWith(
            brightness: _snap(
              v,
              ViewerAdjustments.neutralBrightness,
              ViewerAdjustments.minBrightness,
              ViewerAdjustments.maxBrightness,
            ),
          ),
        ),
      ),
      _EditorAdjustmentControl.contrast => (
        label: l10n.adjustmentContrast,
        value: adj.contrast,
        valueText: '${(adj.contrast * 100).round()}%',
        min: ViewerAdjustments.minContrast,
        max: ViewerAdjustments.maxContrast,
        neutral: ViewerAdjustments.neutralContrast,
        onChanged: (double v) => _set(
          adj.copyWith(
            contrast: _snap(
              v,
              ViewerAdjustments.neutralContrast,
              ViewerAdjustments.minContrast,
              ViewerAdjustments.maxContrast,
            ),
          ),
        ),
      ),
      _EditorAdjustmentControl.saturation => (
        label: l10n.adjustmentSaturation,
        value: adj.saturation,
        valueText: '${(adj.saturation * 100).round()}%',
        min: ViewerAdjustments.minSaturation,
        max: ViewerAdjustments.maxSaturation,
        neutral: ViewerAdjustments.neutralSaturation,
        onChanged: (double v) => _set(
          adj.copyWith(
            saturation: _snap(
              v,
              ViewerAdjustments.neutralSaturation,
              ViewerAdjustments.minSaturation,
              ViewerAdjustments.maxSaturation,
            ),
          ),
        ),
      ),
      _EditorAdjustmentControl.hue => (
        label: l10n.adjustmentHue,
        value: adj.hue,
        valueText: '${adj.hue.round()}°',
        min: ViewerAdjustments.minHue,
        max: ViewerAdjustments.maxHue,
        neutral: ViewerAdjustments.neutralHue,
        onChanged: (double v) => _set(
          adj.copyWith(
            hue: _snap(
              v,
              ViewerAdjustments.neutralHue,
              ViewerAdjustments.minHue,
              ViewerAdjustments.maxHue,
            ),
          ),
        ),
      ),
    };

    final maxHeight = MediaQuery.sizeOf(context).height * 0.82;
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Material(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.adjustmentsSheetTitle,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: l10n.resetToDefaultsTooltip,
                      onPressed: adj.isIdentity
                          ? null
                          : () => _set(ViewerAdjustments.identity),
                      icon: const Icon(Icons.restart_alt_rounded),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    _presetChip(
                      label: l10n.adjustmentPresetVivid,
                      value: ViewerAdjustments.vivid,
                    ),
                    _presetChip(
                      label: l10n.adjustmentPresetBlackAndWhite,
                      value: ViewerAdjustments.blackAndWhite,
                    ),
                    _presetChip(
                      label: l10n.adjustmentPresetWarm,
                      value: _editorWarmAdjustment,
                    ),
                    _presetChip(
                      label: l10n.adjustmentPresetCool,
                      value: ViewerAdjustments.cool,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final control in _EditorAdjustmentControl.values)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(switch (control) {
                              _EditorAdjustmentControl.brightness =>
                                l10n.adjustmentBrightness,
                              _EditorAdjustmentControl.contrast =>
                                l10n.adjustmentContrast,
                              _EditorAdjustmentControl.saturation =>
                                l10n.adjustmentSaturation,
                              _EditorAdjustmentControl.hue =>
                                l10n.adjustmentHue,
                            }),
                            selected: _selectedControl == control,
                            showCheckmark: false,
                            onSelected: (_) =>
                                setState(() => _selectedControl = control),
                          ),
                        ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        slider.label,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    Text(slider.valueText, style: TextStyle(color: cs.primary)),
                    IconButton(
                      tooltip: l10n.reset,
                      onPressed: slider.value == slider.neutral
                          ? null
                          : () => slider.onChanged(slider.neutral),
                      icon: const Icon(Icons.undo_rounded, size: 20),
                    ),
                  ],
                ),
                Slider(
                  value: slider.value.clamp(slider.min, slider.max).toDouble(),
                  min: slider.min,
                  max: slider.max,
                  onChanged: slider.onChanged,
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(l10n.cancel),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(adj),
                      child: Text(l10n.done),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
