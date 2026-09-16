import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/widgets/inputs/duration_picker_dialog.dart';
import 'package:vaultexplorer/core/widgets/inputs/option_picker_tile.dart';

/// Sentinel [SelectOption] value meaning "open the custom duration dialog"
/// rather than an actual duration. Never persisted to settings — callers
/// intercept it in their `onChanged` handler (see [pickCustomAutoLockDuration]).
const int kCustomAutoLockDuration = -1;

const List<int> _presetAutoLockMinutes = [1, 2, 5, 10, 15, 30, 60];

/// Renders [minutes] as "N minutes", "N hours", or "N hours M minutes" for a
/// mixed duration — works for any positive value, not just the fixed presets.
String formatAutoLockDuration(BuildContext context, int minutes) {
  final hours = minutes ~/ 60;
  final mins = minutes % 60;
  if (hours == 0) return context.l10n.nMinutes(mins);
  if (mins == 0) return context.l10n.nHours(hours);
  return '${context.l10n.nHours(hours)} ${context.l10n.nMinutes(mins)}';
}

/// Builds the shared list of auto-lock duration options: [zeroOption] (whose
/// label differs by call site — "Immediately" vs "Never"), the standard
/// minute/hour presets, the currently configured duration if it isn't one of
/// those presets (so it still shows up correctly selected), and a trailing
/// "Custom…" entry (value [kCustomAutoLockDuration]) that opens a picker
/// dialog rather than being a real duration.
List<SelectOption<int>> autoLockDurationOptions(
  BuildContext context, {
  required SelectOption<int> zeroOption,
  required int currentMinutes,
}) {
  final options = <SelectOption<int>>[
    zeroOption,
    for (final mins in _presetAutoLockMinutes)
      SelectOption(value: mins, label: formatAutoLockDuration(context, mins)),
  ];

  final isPreset = currentMinutes == zeroOption.value || _presetAutoLockMinutes.contains(currentMinutes);
  if (currentMinutes > 0 && !isPreset) {
    options.add(
      SelectOption(value: currentMinutes, label: formatAutoLockDuration(context, currentMinutes)),
    );
  }

  options.add(SelectOption(value: kCustomAutoLockDuration, label: context.l10n.customDurationOption));
  return options;
}

/// Opens the custom duration dialog and invokes [onPicked] with the chosen
/// number of minutes, unless the user cancels. Pass this as the handler for
/// the [kCustomAutoLockDuration] sentinel value.
Future<void> pickCustomAutoLockDuration(
  BuildContext context, {
  required int currentMinutes,
  required ValueChanged<int> onPicked,
}) async {
  final result = await showDurationPickerDialog(
    context,
    title: context.l10n.customDurationDialogTitle,
    initialMinutes: currentMinutes > 0 ? currentMinutes : 5,
  );
  if (result != null) onPicked(result);
}
