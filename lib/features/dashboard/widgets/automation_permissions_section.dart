// The device-permission checklist on a vault's Automation screen.
//
// This used to be a single "Allow camera capture" switch that quietly also
// requested camera + microphone and nagged about "display over other apps",
// and that kept saying "on" after any of those had been revoked. Two
// different things were folded into one control:
//
//  * a per-vault POLICY decision ("may automation capture on this vault?"),
//    which the app stores and the person flips, and
//  * app-wide Android PERMISSIONS, which the app can't toggle, only request,
//    and which can change from system settings at any time.
//
// The switch now stays a pure policy opt-in (see AutomationSettingsScreen),
// and this section shows each permission as its own row with its *live* OS
// state, what it is needed for, how much it matters, and one button that does
// the right thing (system prompt, or the right Settings page).
//
// Stateless on purpose: the screen owns the status and the request logic.
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';

/// How badly automation needs a permission. Drives the tag on each row, the
/// order of the rows, and whether a missing one turns the summary red.
enum AutomationPermissionImportance {
  /// Some automation action fails outright without it.
  required,

  /// Automation works, but can be unreliable (e.g. cold start blocked).
  recommended,

  /// Only matters for one particular way of triggering automation.
  optional,
}

class AutomationPermissionItem {
  final IconData icon;
  final String title;

  /// What the permission is needed for, in plain words.
  final String description;
  final AutomationPermissionImportance importance;
  final bool granted;

  /// True once a system prompt has been refused (or can't be shown): the
  /// button then opens Settings instead of asking again.
  final bool needsSettings;

  /// A request for this row is in flight.
  final bool busy;
  final VoidCallback onAction;

  const AutomationPermissionItem({
    required this.icon,
    required this.title,
    required this.description,
    required this.importance,
    required this.granted,
    required this.onAction,
    this.needsSettings = false,
    this.busy = false,
  });
}

class AutomationPermissionsSection extends StatelessWidget {
  final List<AutomationPermissionItem> items;
  const AutomationPermissionsSection({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Most important first. Built by grouping rather than sorting because
    // List.sort isn't stable and rows must not shuffle between rebuilds.
    final ordered = [
      for (final importance in AutomationPermissionImportance.values)
        ...items.where((i) => i.importance == importance),
    ];
    final missing = items.where((i) => !i.granted);
    final requiredMissing = missing
        .where((i) => i.importance == AutomationPermissionImportance.required)
        .length;
    final recommendedMissing = missing
        .where(
          (i) => i.importance == AutomationPermissionImportance.recommended,
        )
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        SectionHeader(l10n.automationPermissionsSectionHeader),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            l10n.automationPermissionsIntro,
            style: textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 8),
        _ReadinessBanner(
          requiredMissing: requiredMissing,
          recommendedMissing: recommendedMissing,
        ),
        const SizedBox(height: 8),
        SectionCard(
          children: [for (final item in ordered) _PermissionRow(item: item)],
        ),
      ],
    );
  }
}

/// One-glance answer to "is this set up?", so nobody has to read every row.
class _ReadinessBanner extends StatelessWidget {
  final int requiredMissing;
  final int recommendedMissing;
  const _ReadinessBanner({
    required this.requiredMissing,
    required this.recommendedMissing,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final semantic = context.semanticColors;
    final textTheme = Theme.of(context).textTheme;

    final (Color bg, Color fg, IconData icon, String title, String message) =
        requiredMissing > 0
        ? (
            cs.errorContainer,
            cs.onErrorContainer,
            Icons.error_outline_rounded,
            l10n.automationPermSetupNeededTitle,
            l10n.automationPermSetupNeededMessage(requiredMissing),
          )
        : recommendedMissing > 0
        ? (
            semantic.warningContainer,
            semantic.onWarningContainer,
            Icons.warning_amber_rounded,
            l10n.automationPermAlmostReadyTitle,
            l10n.automationPermAlmostReadyMessage(recommendedMissing),
          )
        : (
            semantic.successContainer,
            semantic.onSuccessContainer,
            Icons.check_circle_outline_rounded,
            l10n.automationPermReadyTitle,
            l10n.automationPermReadyMessage,
          );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: fg, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: textTheme.titleSmall?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: textTheme.bodySmall?.copyWith(color: fg, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  final AutomationPermissionItem item;
  const _PermissionRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final semantic = context.semanticColors;
    final textTheme = Theme.of(context).textTheme;

    final Color tint = item.granted
        ? semantic.success
        : switch (item.importance) {
            AutomationPermissionImportance.required => cs.error,
            AutomationPermissionImportance.recommended => semantic.warning,
            AutomationPermissionImportance.optional => cs.onSurfaceVariant,
          };

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tint.withValues(alpha: 0.14),
            ),
            child: Icon(
              item.granted ? Icons.check_rounded : item.icon,
              color: tint,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      item.title,
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    _StatusTag(item: item),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  item.description,
                  style: textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                if (!item.granted) ...[
                  const SizedBox(height: 10),
                  _ActionButton(
                    label: item.needsSettings
                        ? l10n.openSettings
                        : l10n.automationPermGrantButton,
                    emphasized:
                        item.importance ==
                        AutomationPermissionImportance.required,
                    busy: item.busy,
                    onPressed: item.onAction,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final bool emphasized;
  final bool busy;
  final VoidCallback onPressed;
  const _ActionButton({
    required this.label,
    required this.emphasized,
    required this.busy,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final child = busy
        ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Text(label);
    final onTap = busy ? null : onPressed;
    // The one thing that must be fixed gets the loud button; the rest stay
    // quiet so a long list doesn't read as an emergency.
    return emphasized
        ? FilledButton(onPressed: onTap, child: child)
        : FilledButton.tonal(onPressed: onTap, child: child);
  }
}

class _StatusTag extends StatelessWidget {
  final AutomationPermissionItem item;
  const _StatusTag({required this.item});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final semantic = context.semanticColors;

    final (Color bg, Color fg, String label) = item.granted
        ? (
            semantic.successContainer,
            semantic.onSuccessContainer,
            l10n.automationPermGranted,
          )
        : switch (item.importance) {
            AutomationPermissionImportance.required => (
              cs.errorContainer,
              cs.onErrorContainer,
              l10n.automationPermTagRequired,
            ),
            AutomationPermissionImportance.recommended => (
              semantic.warningContainer,
              semantic.onWarningContainer,
              l10n.automationPermTagRecommended,
            ),
            AutomationPermissionImportance.optional => (
              cs.surfaceContainerHighest,
              cs.onSurfaceVariant,
              l10n.automationPermTagOptional,
            ),
          };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: fg,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
