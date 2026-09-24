import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/widgets/inputs/auto_lock_duration_options.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';

/// What will actually happen to an unlocked container, purely for user
/// feedback (the dashboard card and drawer row). Mirrors the real lock
/// logic -- [VaultDashboardController.scheduleAutoClose] for a per-container
/// override, [SessionLockController]'s vault-lock timer/handleScreenOff for
/// containers that fall back to the app-wide sweep -- so this never claims a
/// behavior the app doesn't actually implement. Never used to drive an
/// actual lock decision.
sealed class AutoLockStatus {
  const AutoLockStatus();
}

/// Locks after [minutes] of inactivity -- either the container's own
/// [ContainerRecord.autoCloseMins], or (when unset) the app-wide
/// [AppSettings.autoLockMins] it falls back to.
class AutoLockAfter extends AutoLockStatus {
  const AutoLockAfter(this.minutes);
  final int minutes;
}

/// No per-container override, and the app-wide default has no inactivity
/// delay of its own -- locks as soon as the screen turns off.
class AutoLockOnScreenOff extends AutoLockStatus {
  const AutoLockOnScreenOff();
}

/// Either explicitly set to "Never" on this container, or falling back to
/// an app-wide default that has vault auto-lock switched off entirely.
class AutoLockNever extends AutoLockStatus {
  const AutoLockNever();
}

/// Computes what will actually lock [record]'s container, falling back to
/// the app-wide [settings] when the container has no override of its own.
/// See [ContainerRecord.isExemptFromGlobalLock] and
/// [VaultDashboardScreen._lockAllMountedContainers] for the real sweep this
/// mirrors, and [SessionLockController.handleScreenOff] for the app-wide
/// screen-off/inactivity behavior a non-overridden container follows.
AutoLockStatus computeAutoLockStatus(ContainerRecord? record, AppSettings settings) {
  if (record?.autoCloseNever == true) return const AutoLockNever();
  final perContainerMins = record?.autoCloseMins ?? 0;
  if (perContainerMins > 0) return AutoLockAfter(perContainerMins);
  if (!settings.lockContainersOnScreenLock) return const AutoLockNever();
  if (settings.autoLockMins > 0) return AutoLockAfter(settings.autoLockMins);
  return const AutoLockOnScreenOff();
}

class _AutoLockVisual {
  const _AutoLockVisual({required this.icon, required this.label, required this.tooltip});
  final IconData icon;
  final String label;
  final String tooltip;
}

_AutoLockVisual? _visualFor(BuildContext context, AutoLockStatus status) {
  final l10n = context.l10n;
  return switch (status) {
    AutoLockAfter(:final minutes) => _AutoLockVisual(
        icon: Icons.timer_outlined,
        label: l10n.autoLockIndicatorLocksAfter(formatAutoLockDuration(context, minutes)),
        tooltip: l10n.autoLockIndicatorLocksAfterTooltip(formatAutoLockDuration(context, minutes)),
      ),
    AutoLockOnScreenOff() => _AutoLockVisual(
        icon: Icons.screen_lock_portrait_outlined,
        label: l10n.autoLockIndicatorLocksOnScreenOff,
        tooltip: l10n.autoLockIndicatorLocksOnScreenOff,
      ),
    AutoLockNever() => null,
  };
}

/// Subtle icon badge placed next to the vault title. Shows an icon (e.g. timer
/// or screen lock) with an explanatory tooltip on tap/hover stating that the
/// inactivity timer resets on interaction. Hidden when auto-lock is disabled.
class AutoLockIconBadge extends StatelessWidget {
  const AutoLockIconBadge({super.key, required this.record, required this.settings});
  final ContainerRecord? record;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final visual = _visualFor(context, computeAutoLockStatus(record, settings));
    if (visual == null) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Tooltip(
        message: visual.tooltip,
        child: Icon(
          visual.icon,
          size: 15,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Renders "{statusLabel} ⏱️" in the drawer row with a tooltip on the icon.
class DrawerAutoLockStatusText extends StatelessWidget {
  const DrawerAutoLockStatusText({
    super.key,
    required this.statusLabel,
    required this.statusColor,
    required this.record,
    required this.settings,
    required this.style,
  });
  final String statusLabel;
  final Color statusColor;
  final ContainerRecord? record;
  final AppSettings settings;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final visual = _visualFor(context, computeAutoLockStatus(record, settings));
    final cs = Theme.of(context).colorScheme;
    final baseStyle = (style ?? const TextStyle()).copyWith(color: statusColor);

    if (visual == null) {
      return Text(
        statusLabel,
        style: baseStyle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(statusLabel, style: baseStyle),
        const SizedBox(width: 5),
        Tooltip(
          message: visual.tooltip,
          child: Icon(
            visual.icon,
            size: 13,
            color: cs.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
