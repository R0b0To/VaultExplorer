import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/api/vault_engine_types.dart' show KeyfileRef;
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';

/// Building blocks of the unlock page as it appears in a native desktop window.
///
/// The phone layout puts rounded inputs inside grouped cards and one full-width
/// pill button at the bottom. In a window that reads as a mobile screen, so the
/// window layout is flat: fields sit directly on the surface with a hairline
/// border, secondary rows carry no card background, and the actions are pinned
/// to a footer, right-aligned, like any desktop dialog.

/// Corner radius of fields, rows and buttons in the window layout. It matches
/// the file manager's panels rather than the phone's pill shapes.
const double kUnlockWindowRadius = AppRadius.sm;

/// Vertical gap between the rows of the form.
const double kUnlockWindowGap = 12;

/// Outline colour of fields and rows when idle.
Color unlockWindowOutline(ColorScheme cs) =>
    cs.onSurface.withValues(alpha: 0.12);

/// Decoration of a text field in the window layout: a 1px hairline border that
/// turns to the accent colour on focus, over a barely tinted fill, with tight
/// padding.
InputDecoration unlockWindowFieldDecoration(
  BuildContext context, {
  required String label,
  required IconData icon,
  Widget? suffix,
}) {
  final cs = Theme.of(context).colorScheme;
  OutlineInputBorder border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(kUnlockWindowRadius),
        borderSide: BorderSide(color: color, width: width),
      );
  return InputDecoration(
    isDense: true,
    filled: true,
    fillColor: cs.onSurface.withValues(alpha: 0.04),
    labelText: label,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    prefixIcon: Icon(icon, size: 20, color: cs.onSurfaceVariant),
    prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 20),
    suffixIcon: suffix,
    suffixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 20),
    border: border(unlockWindowOutline(cs)),
    enabledBorder: border(unlockWindowOutline(cs)),
    focusedBorder: border(cs.primary, 1.5),
    disabledBorder: border(cs.onSurface.withValues(alpha: 0.06)),
    errorBorder: border(cs.error),
    focusedErrorBorder: border(cs.error, 1.5),
  );
}

/// A bordered row on the form surface (the vault badge, the keyfiles row).
class UnlockWindowRow extends StatelessWidget {
  const UnlockWindowRow({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(kUnlockWindowRadius);
    return InkWell(
      borderRadius: radius,
      onTap: onTap,
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(color: unlockWindowOutline(cs)),
        ),
        child: child,
      ),
    );
  }
}

/// "Keyfiles (optional)  [ + Add File ]", with the chosen files listed under
/// it. A subtle row, not a card.
class UnlockWindowKeyfilesRow extends StatelessWidget {
  const UnlockWindowKeyfilesRow({
    super.key,
    required this.keyfiles,
    required this.picking,
    required this.enabled,
    required this.onPick,
    required this.onRemove,
  });

  final List<KeyfileRef> keyfiles;
  final bool picking;
  final bool enabled;
  final VoidCallback onPick;
  final ValueChanged<KeyfileRef> onRemove;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return UnlockWindowRow(
      padding: const EdgeInsets.fromLTRB(12, 4, 6, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                Icons.insert_drive_file_outlined,
                size: 20,
                color: cs.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  context.l10n.keyfilesOptionalLabel,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton.icon(
                onPressed: (enabled && !picking) ? onPick : null,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(kUnlockWindowRadius),
                  ),
                ),
                icon: picking
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_rounded, size: 18),
                label: Text(context.l10n.addFile),
              ),
            ],
          ),
          if (keyfiles.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6, right: 6),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final k in keyfiles)
                    InputChip(
                      visualDensity: VisualDensity.compact,
                      avatar: Icon(
                        Icons.description_outlined,
                        size: 16,
                        color: cs.primary,
                      ),
                      label: Text(
                        k.displayName,
                        style: textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onDeleted: enabled ? () => onRemove(k) : null,
                      deleteIconColor: cs.error,
                      side: BorderSide(color: unlockWindowOutline(cs)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          kUnlockWindowRadius,
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The "Advanced Options" toggle: an icon, a label and a chevron on the plain
/// surface, with no card behind it.
class UnlockWindowAdvancedToggle extends StatelessWidget {
  const UnlockWindowAdvancedToggle({
    super.key,
    required this.expanded,
    required this.enabled,
    required this.onToggle,
  });

  final bool expanded;
  final bool enabled;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = enabled
        ? cs.onSurfaceVariant
        : cs.onSurface.withValues(alpha: 0.38);
    return InkWell(
      borderRadius: BorderRadius.circular(kUnlockWindowRadius),
      onTap: enabled ? onToggle : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.tune_rounded, size: 20, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                context.l10n.advancedOptionsTitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
            AnimatedRotation(
              turns: expanded ? 0.5 : 0,
              duration: const Duration(milliseconds: 150),
              child: Icon(Icons.expand_more_rounded, size: 20, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

/// The pinned footer: a hairline, then the actions right-aligned. [status]
/// (the unlock progress) sits on the left while there is one.
class UnlockWindowFooter extends StatelessWidget {
  const UnlockWindowFooter({
    super.key,
    required this.secondary,
    this.primary,
    this.status,
  });

  /// The Cancel button (or "Cancel Unlock" while unlocking).
  final Widget secondary;

  /// The Unlock button; null where there is nothing to submit (a pattern or a
  /// fingerprint unlocks on its own).
  final Widget? primary;

  final Widget? status;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: unlockWindowOutline(cs))),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: Row(
          children: [
            if (status != null) Expanded(child: status!) else const Spacer(),
            secondary,
            if (primary != null) ...[const SizedBox(width: 8), primary!],
          ],
        ),
      ),
    );
  }
}

/// Button shape shared by the footer actions.
ButtonStyle unlockWindowButtonStyle() => ButtonStyle(
  minimumSize: const WidgetStatePropertyAll(Size(112, 40)),
  shape: WidgetStatePropertyAll(
    RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(kUnlockWindowRadius),
    ),
  ),
);
