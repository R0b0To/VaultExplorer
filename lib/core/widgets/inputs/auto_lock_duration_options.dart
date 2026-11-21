import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/utils/platform_features.dart';
import 'package:vaultexplorer/core/widgets/inputs/duration_picker_dialog.dart';
import 'package:vaultexplorer/core/widgets/inputs/option_picker_tile.dart';

/// Sentinel [SelectOption] value meaning "open the custom duration dialog"
/// rather than an actual duration. Never persisted to settings — callers
/// intercept it in their `onChanged` handler (see [pickCustomAutoLockDuration]).
const int kCustomAutoLockDuration = -1;

/// Sentinel [SelectOption] value meaning "no override — follow the app-wide
/// auto-lock / lock-on-screen-lock behavior". Only offered where a
/// [defaultOption] is passed to [autoLockDurationOptions] (the per-container
/// picker); the global settings picker has no such concept, since it *is*
/// the app-wide setting. Distinct from the zero option (e.g. "Never"):
/// picking "Never" here is what exempts a single container from the app-wide
/// lock-all sweep, whereas this sentinel leaves that container subject to it.
const int kInheritAutoLockDuration = -2;

/// Sentinel [SelectOption] value meaning "lock with no delay at all". Only
/// offered where an [immediateOption] is passed to [autoLockDurationOptions]
/// (the per-container picker) -- the two global pickers have no separate
/// entry for this because they already spend the real zero value on it
/// (their [zeroOption] *is* "Immediately"). The per-container picker can't
/// reuse zero the same way because it's already spoken for by "Never", so
/// "Immediately" needs its own sentinel to stay distinct from both "Never"
/// (value 0) and "App Default" ([kInheritAutoLockDuration]).
const int kImmediateAutoLockDuration = -3;

/// Sentinel [SelectOption] value meaning "no inactivity timer at all — the
/// only thing that locks this is a genuine screen-off/device-lock event".
/// Offered where a [screenLockOnlyOption] is passed to
/// [autoLockDurationOptions] (both the global Vault Auto-Lock picker and the
/// per-container picker). Distinct from [kImmediateAutoLockDuration]:
/// "Immediately" also locks on plain app backgrounding (switching to another
/// app while the screen stays on), whereas this sentinel ignores that and
/// reacts only to the screen physically turning off. See
/// AppSettings.autoLockScreenLockOnly / ContainerRecord.autoCloseScreenLockOnly
/// and SessionLockController's handling of both.
const int kScreenLockOnlyAutoLockDuration = -4;

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

/// Builds the shared list of auto-lock duration options: an optional leading
/// [defaultOption] (value [kInheritAutoLockDuration]) for pickers that need
/// an explicit "no override" choice, an optional [immediateOption] (value
/// [kImmediateAutoLockDuration]) for pickers that need "Immediately" as its
/// own entry distinct from [zeroOption] (whose label differs by call site —
/// "Immediately" for the two global pickers, "Never" for the per-container
/// picker, which is also the only one that passes [immediateOption]), an
/// optional [screenLockOnlyOption] (value [kScreenLockOnlyAutoLockDuration])
/// for pickers that offer "locks only on screen lock" as its own entry, the
/// standard minute/hour presets, the currently configured duration if it
/// isn't one of those presets (so it still shows up correctly selected), and
/// a trailing "Custom…" entry (value [kCustomAutoLockDuration]) that opens a
/// picker dialog rather than being a real duration.
List<SelectOption<int>> autoLockDurationOptions(
  BuildContext context, {
  required SelectOption<int> zeroOption,
  required int currentMinutes,
  SelectOption<int>? defaultOption,
  SelectOption<int>? immediateOption,
  SelectOption<int>? screenLockOnlyOption,
}) {
  final options = <SelectOption<int>>[
    if (defaultOption != null) defaultOption,
    if (immediateOption != null) immediateOption,
    // "Only when the screen turns off" needs a screen-off event, which desktop
    // sessions don't have. A value already saved (e.g. imported from an
    // Android backup) keeps its entry so the picker still has a match.
    if (screenLockOnlyOption != null &&
        (PlatformFeatures.lockOnScreenOff ||
            currentMinutes == kScreenLockOnlyAutoLockDuration))
      screenLockOnlyOption,
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