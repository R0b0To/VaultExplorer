import 'dart:ui' show FontFeature;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_session_controller.dart';
import 'package:vaultexplorer/features/browser/viewer/models/viewer_adjustments.dart';

enum _AdjustmentControl { brightness, contrast, saturation, hue, gamma }

/// Compact picture-adjustment panel for the file at [path].
///
/// Meant to be shown with a transparent barrier so the picture stays visible
/// while dragging. It reads and writes the viewer session directly, so the
/// picture behind it updates live.
class AdjustmentsSheet extends ConsumerStatefulWidget {
  const AdjustmentsSheet({
    super.key,
    required this.sessionKey,
    required this.path,
    required this.showApplyToAll,
    required this.onInteraction,
    this.isSidebar = false,
  });

  final String sessionKey;
  final String path;

  /// Only meaningful when there is more than one file to apply to.
  final bool showApplyToAll;

  /// Called on every change so the viewer can keep its chrome timer sane.
  final VoidCallback onInteraction;

  /// Uses the full available height when shown as a landscape side panel.
  final bool isSidebar;

  /// Within this fraction of a slider's range, the thumb snaps to neutral so
  /// "no adjustment" is easy to hit exactly.
  static const double _snapFraction = 0.02;

  static double _snap(double v, double neutral, double min, double max) =>
      (v - neutral).abs() < (max - min) * _snapFraction ? neutral : v;

  static String _signed(int v) => v > 0 ? '+$v' : '$v';

  @override
  ConsumerState<AdjustmentsSheet> createState() => _AdjustmentsSheetState();
}

class _AdjustmentsSheetState extends ConsumerState<AdjustmentsSheet> {
  _AdjustmentControl _selectedControl = _AdjustmentControl.brightness;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final provider = mediaViewerSessionProvider(widget.sessionKey);
    final session = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final adj = session.adjustmentsFor(widget.path);

    void set(ViewerAdjustments v) {
      widget.onInteraction();
      controller.setAdjustments(widget.path, v);
    }

    final height = MediaQuery.sizeOf(context).height;
    final maxHeight = widget.isSidebar ? height : height * 0.38;
    final control = _selectedControl;
    final slider = switch (control) {
      _AdjustmentControl.brightness => (
        label: l10n.adjustmentBrightness,
        valueText: AdjustmentsSheet._signed((adj.brightness * 100).round()),
        value: adj.brightness,
        min: ViewerAdjustments.minBrightness,
        max: ViewerAdjustments.maxBrightness,
        neutral: ViewerAdjustments.neutralBrightness,
        onChanged: (double v) => set(
          adj.copyWith(
            brightness: AdjustmentsSheet._snap(
              v,
              ViewerAdjustments.neutralBrightness,
              ViewerAdjustments.minBrightness,
              ViewerAdjustments.maxBrightness,
            ),
          ),
        ),
      ),
      _AdjustmentControl.contrast => (
        label: l10n.adjustmentContrast,
        valueText: '${(adj.contrast * 100).round()}%',
        value: adj.contrast,
        min: ViewerAdjustments.minContrast,
        max: ViewerAdjustments.maxContrast,
        neutral: ViewerAdjustments.neutralContrast,
        onChanged: (double v) => set(
          adj.copyWith(
            contrast: AdjustmentsSheet._snap(
              v,
              ViewerAdjustments.neutralContrast,
              ViewerAdjustments.minContrast,
              ViewerAdjustments.maxContrast,
            ),
          ),
        ),
      ),
      _AdjustmentControl.saturation => (
        label: l10n.adjustmentSaturation,
        valueText: '${(adj.saturation * 100).round()}%',
        value: adj.saturation,
        min: ViewerAdjustments.minSaturation,
        max: ViewerAdjustments.maxSaturation,
        neutral: ViewerAdjustments.neutralSaturation,
        onChanged: (double v) => set(
          adj.copyWith(
            saturation: AdjustmentsSheet._snap(
              v,
              ViewerAdjustments.neutralSaturation,
              ViewerAdjustments.minSaturation,
              ViewerAdjustments.maxSaturation,
            ),
          ),
        ),
      ),
      _AdjustmentControl.hue => (
        label: l10n.adjustmentHue,
        valueText: '${adj.hue.round()}\u00B0',
        value: adj.hue,
        min: ViewerAdjustments.minHue,
        max: ViewerAdjustments.maxHue,
        neutral: ViewerAdjustments.neutralHue,
        onChanged: (double v) => set(
          adj.copyWith(
            hue: AdjustmentsSheet._snap(
              v,
              ViewerAdjustments.neutralHue,
              ViewerAdjustments.minHue,
              ViewerAdjustments.maxHue,
            ),
          ),
        ),
      ),
      _AdjustmentControl.gamma => (
        label: l10n.adjustmentGamma,
        valueText: adj.gamma.toStringAsFixed(2),
        value: adj.gamma,
        min: ViewerAdjustments.minGamma,
        max: ViewerAdjustments.maxGamma,
        neutral: ViewerAdjustments.neutralGamma,
        onChanged: (double v) => set(
          adj.copyWith(
            gamma: AdjustmentsSheet._snap(
              v,
              ViewerAdjustments.neutralGamma,
              ViewerAdjustments.minGamma,
              ViewerAdjustments.maxGamma,
            ),
          ),
        ),
      ),
    };

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(
            left: AppSpacing.md,
            right: AppSpacing.md,
            bottom: AppSpacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.adjustmentsSheetTitle,
                      style: Theme.of(context).textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Flexible(
                    child: _HoldToCompareButton(
                      active: session.compareOriginal,
                      label: l10n.adjustmentsCompareHold,
                      onChanged: controller.setCompareOriginal,
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.resetToDefaultsTooltip,
                    icon: const Icon(Icons.restart_alt_rounded),
                    onPressed: adj.isIdentity
                        ? null
                        : () {
                            HapticFeedback.lightImpact();
                            set(ViewerAdjustments.identity);
                          },
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.xs,
                children: [
                  _PresetChip(
                    label: l10n.adjustmentPresetVivid,
                    selected: adj == ViewerAdjustments.vivid,
                    onTap: (selected) => set(
                      selected
                          ? ViewerAdjustments.identity
                          : ViewerAdjustments.vivid,
                    ),
                  ),
                  _PresetChip(
                    label: l10n.adjustmentPresetBlackAndWhite,
                    selected: adj == ViewerAdjustments.blackAndWhite,
                    onTap: (selected) => set(
                      selected
                          ? ViewerAdjustments.identity
                          : ViewerAdjustments.blackAndWhite,
                    ),
                  ),
                  _PresetChip(
                    label: l10n.adjustmentPresetWarm,
                    selected: adj == ViewerAdjustments.warm,
                    onTap: (selected) => set(
                      selected
                          ? ViewerAdjustments.identity
                          : ViewerAdjustments.warm,
                    ),
                  ),
                  _PresetChip(
                    label: l10n.adjustmentPresetCool,
                    selected: adj == ViewerAdjustments.cool,
                    onTap: (selected) => set(
                      selected
                          ? ViewerAdjustments.identity
                          : ViewerAdjustments.cool,
                    ),
                  ),
                ],
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final option in _AdjustmentControl.values)
                      Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.xs),
                        child: _ControlChip(
                          label: switch (option) {
                            _AdjustmentControl.brightness =>
                              l10n.adjustmentBrightness,
                            _AdjustmentControl.contrast =>
                              l10n.adjustmentContrast,
                            _AdjustmentControl.saturation =>
                              l10n.adjustmentSaturation,
                            _AdjustmentControl.hue => l10n.adjustmentHue,
                            _AdjustmentControl.gamma => l10n.adjustmentGamma,
                          },
                          selected: control == option,
                          onTap: () =>
                              setState(() => _selectedControl = option),
                        ),
                      ),
                  ],
                  mainAxisSize: MainAxisSize.min,
                ),
              ),
              _AdjustmentSlider(
                label: slider.label,
                resetLabel: l10n.reset,
                valueText: slider.valueText,
                value: slider.value,
                min: slider.min,
                max: slider.max,
                neutral: slider.neutral,
                onChanged: slider.onChanged,
              ),
              if (widget.showApplyToAll) ...[
                const Divider(height: AppSpacing.md),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.adjustmentsApplyToAll),
                  value: session.applyAdjustmentsToAll,
                  onChanged: (v) {
                    widget.onInteraction();
                    controller.setApplyAdjustmentsToAll(widget.path, v);
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ControlChip extends StatelessWidget {
  const _ControlChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ChoiceChip(
    label: Text(label),
    selected: selected,
    showCheckmark: false,
    onSelected: (_) => onTap(),
  );
}

class _AdjustmentSlider extends StatelessWidget {
  const _AdjustmentSlider({
    required this.label,
    required this.resetLabel,
    required this.valueText,
    required this.value,
    required this.min,
    required this.max,
    required this.neutral,
    required this.onChanged,
  });

  final String label;
  final String resetLabel;
  final String valueText;
  final double value;
  final double min;
  final double max;
  final double neutral;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final isNeutral = value == neutral;
    void reset() {
      HapticFeedback.selectionClick();
      onChanged(neutral);
    }

    return Column(
      children: [
        Row(
          children: [
            // Double-tapping the label resets just this slider.
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onDoubleTap: isNeutral ? null : reset,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Text(label),
              ),
            ),
            const Spacer(),
            Text(
              valueText,
              style: TextStyle(
                color: isNeutral ? cs.onSurfaceVariant : cs.primary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            SizedBox(
              width: 40,
              height: 32,
              child: isNeutral
                  ? null
                  : IconButton(
                      tooltip: resetLabel,
                      padding: EdgeInsets.zero,
                      iconSize: 18,
                      icon: const Icon(Icons.undo_rounded),
                      onPressed: reset,
                    ),
            ),
          ],
        ),
        SizedBox(
          height: 32,
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;

  /// Receives whether the chip was selected when tapped, so tapping a
  /// selected preset toggles it back off.
  final ValueChanged<bool> onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) {
        HapticFeedback.selectionClick();
        onTap(selected);
      },
    );
  }
}

/// Shows the original picture for as long as it is pressed.
class _HoldToCompareButton extends StatelessWidget {
  const _HoldToCompareButton({
    required this.active,
    required this.label,
    required this.onChanged,
  });

  final bool active;
  final String label;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Semantics(
      button: true,
      label: label,
      child: Listener(
        onPointerDown: (_) {
          HapticFeedback.selectionClick();
          onChanged(true);
        },
        onPointerUp: (_) => onChanged(false),
        onPointerCancel: (_) => onChanged(false),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm + AppSpacing.xs,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: active ? cs.primaryContainer : Colors.transparent,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.compare_rounded,
                size: 20,
                color: active ? cs.onPrimaryContainer : cs.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: active ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
