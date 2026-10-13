import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/data/models/audio_equalizer_settings.dart';

/// The media player's equalizer: on/off, presets, ten band sliders, a preamp
/// and the clipping guard.
///
/// Purely presentational. It keeps its own working copy of the settings so the
/// sliders track the finger, and reports out through two callbacks:
///  - [onChanged] on *every* change (each slider tick) -- the viewer pushes it
///    straight to the native audio pipeline, which is cheap;
///  - [onCommit] when a change is final (slider released, chip/switch tapped)
///    -- the viewer persists it, which is not cheap (encrypted write), so it
///    must not happen per tick.
///
/// Moving a band, picking a preset (other than Flat) or changing the preamp
/// while the equalizer is off switches it on, since that is clearly what the
/// person wants to hear.
class AudioEqualizerSheet extends StatefulWidget {
  const AudioEqualizerSheet({
    super.key,
    required this.initial,
    required this.onChanged,
    required this.onCommit,
    this.onInteraction,
  });

  final AudioEqualizerSettings initial;

  /// Every change, including each tick of a slider drag.
  final ValueChanged<AudioEqualizerSettings> onChanged;

  /// A change the person has finished making.
  final ValueChanged<AudioEqualizerSettings> onCommit;

  /// Called alongside every change so the viewer can keep its chrome timer sane.
  final VoidCallback? onInteraction;

  /// "+3", "-6.5", "0": a signed dB value without the unit.
  @visibleForTesting
  static String formatDb(double value) {
    final rounded = (value * 10).round() / 10;
    if (rounded == 0) return '0';
    final text = rounded == rounded.roundToDouble()
        ? rounded.toStringAsFixed(0)
        : rounded.toStringAsFixed(1);
    return rounded > 0 ? '+$text' : text;
  }

  /// "31", "125", "1k", "16k": the short frequency label under a band.
  @visibleForTesting
  static String bandLabel(double hz) {
    if (hz >= 1000) {
      final k = hz / 1000;
      return '${k == k.roundToDouble() ? k.toStringAsFixed(0) : k.toStringAsFixed(1)}k';
    }
    return hz.toStringAsFixed(0);
  }

  @override
  State<AudioEqualizerSheet> createState() => _AudioEqualizerSheetState();
}

class _AudioEqualizerSheetState extends State<AudioEqualizerSheet> {
  late AudioEqualizerSettings _settings = widget.initial;

  /// Applies [next] and reports it. [commit] false is for the middle of a
  /// drag; [autoEnable] false is for the controls that must not flip the
  /// master switch themselves (the switch, reset, the clipping toggle).
  void _apply(
    AudioEqualizerSettings next, {
    bool commit = true,
    bool autoEnable = true,
  }) {
    var settings = next;
    if (autoEnable && !settings.enabled && !settings.isFlat) {
      settings = settings.copyWith(enabled: true);
    }
    setState(() => _settings = settings);
    widget.onChanged(settings);
    if (commit) widget.onCommit(settings);
    widget.onInteraction?.call();
  }

  void _commitCurrent() {
    widget.onCommit(_settings);
    widget.onInteraction?.call();
  }

  void _reset() {
    HapticFeedback.lightImpact();
    _apply(
      _settings.copyWith(
        bandGainsDb: EqualizerPreset.flat.bandGainsDb,
        preampDb: 0,
      ),
      autoEnable: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = context.colors;
    final height = MediaQuery.sizeOf(context).height;
    final sliderHeight = (height * 0.26).clamp(110.0, 190.0).toDouble();
    final preset = _settings.matchingPreset;
    final active = _settings.enabled;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: height * 0.92),
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
                  Icon(Icons.equalizer_rounded, color: cs.primary),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      l10n.equalizerTitle,
                      style: Theme.of(context).textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.resetToDefaultsTooltip,
                    icon: const Icon(Icons.restart_alt_rounded),
                    onPressed: _settings.isFlat ? null : _reset,
                  ),
                  Semantics(
                    label: l10n.equalizerTitle,
                    child: Switch(
                      value: _settings.enabled,
                      onChanged: (v) => _apply(
                        _settings.copyWith(enabled: v),
                        autoEnable: false,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    if (preset == null)
                      Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.xs),
                        child: ChoiceChip(
                          label: Text(l10n.equalizerPresetCustom),
                          selected: true,
                          showCheckmark: false,
                          onSelected: (_) {},
                        ),
                      ),
                    for (final p in EqualizerPreset.values)
                      Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.xs),
                        child: ChoiceChip(
                          label: Text(p.getLocalizedLabel(l10n)),
                          selected: preset == p,
                          showCheckmark: false,
                          onSelected: (_) {
                            HapticFeedback.selectionClick();
                            _apply(_settings.withPreset(p));
                          },
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Opacity(
                opacity: active ? 1 : 0.5,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < kEqualizerBandCount; i++)
                      Expanded(
                        child: _BandColumn(
                          gainDb: _settings.bandGainsDb[i],
                          frequencyHz: kEqualizerBandFrequenciesHz[i],
                          sliderHeight: sliderHeight,
                          onChanged: (v) => _apply(
                            _settings.withBandGain(i, v),
                            commit: false,
                          ),
                          onChangeEnd: (_) => _commitCurrent(),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  SizedBox(
                    width: 88,
                    child: Text(
                      l10n.equalizerPreampLabel,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    child: Slider(
                      value: _settings.preampDb,
                      min: -kEqualizerMaxGainDb,
                      max: kEqualizerMaxGainDb,
                      divisions: (kEqualizerMaxGainDb * 4).round(),
                      semanticFormatterCallback: (v) =>
                          '${AudioEqualizerSheet.formatDb(v)} dB',
                      onChanged: (v) =>
                          _apply(_settings.copyWith(preampDb: v), commit: false),
                      onChangeEnd: (_) => _commitCurrent(),
                    ),
                  ),
                  SizedBox(
                    width: 64,
                    child: Text(
                      '${AudioEqualizerSheet.formatDb(_settings.preampDb)} dB',
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        color: _settings.preampDb == 0
                            ? cs.onSurfaceVariant
                            : cs.primary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(height: AppSpacing.md),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.equalizerPreventClippingTitle),
                subtitle: Text(l10n.equalizerPreventClippingSubtitle),
                value: _settings.preventClipping,
                onChanged: (v) => _apply(
                  _settings.copyWith(preventClipping: v),
                  autoEnable: false,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One band: its gain on top, a vertical slider, its centre frequency below.
class _BandColumn extends StatelessWidget {
  const _BandColumn({
    required this.gainDb,
    required this.frequencyHz,
    required this.sliderHeight,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final double gainDb;
  final double frequencyHz;
  final double sliderHeight;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final label = AudioEqualizerSheet.bandLabel(frequencyHz);
    final isFlat = gainDb == 0;
    const tabular = [FontFeature.tabularFigures()];

    return Column(
      children: [
        Text(
          AudioEqualizerSheet.formatDb(gainDb),
          maxLines: 1,
          style: TextStyle(
            fontSize: 11,
            color: isFlat ? cs.onSurfaceVariant : cs.primary,
            fontFeatures: tabular,
          ),
        ),
        SizedBox(
          height: sliderHeight,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 0 dB guide line behind the thumb.
              Container(width: 14, height: 1, color: cs.outline),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 7,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 14,
                  ),
                  // No fill: the thumb position against the 0 dB line is the
                  // information, a bar growing from the bottom would not be.
                  activeTrackColor: cs.outlineVariant,
                  inactiveTrackColor: cs.outlineVariant,
                ),
                child: RotatedBox(
                  quarterTurns: 3,
                  child: Slider(
                    value: gainDb,
                    min: -kEqualizerMaxGainDb,
                    max: kEqualizerMaxGainDb,
                    divisions: (kEqualizerMaxGainDb * 4).round(),
                    semanticFormatterCallback: (v) =>
                        '$label Hz, ${AudioEqualizerSheet.formatDb(v)} dB',
                    onChanged: onChanged,
                    onChangeEnd: onChangeEnd,
                  ),
                ),
              ),
            ],
          ),
        ),
        Text(
          label,
          maxLines: 1,
          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}
