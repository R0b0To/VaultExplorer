import 'package:flutter/material.dart';
import '../models/crypto_algorithms.dart';
import '../services/vaultexplorer_api.dart' show KeyfileRef;
import '../theme.dart';


class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: cs.primary,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
      ),
    );
  }
}

/// Icon + title/subtitle + trailing Switch row.
class SettingsToggleRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const SettingsToggleRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.md),
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icon, size: AppIconSize.standard, color: cs.onSurfaceVariant),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

/// Error-container banner with icon + message.
class InlineErrorBanner extends StatelessWidget {
  final String message;
  const InlineErrorBanner(this.message, {super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: AppIconSize.standard,
            color: cs.onErrorContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: textTheme.bodySmall?.copyWith(color: cs.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

/// Generic tinted inline banner (success / warning / info / error) — the
/// general-purpose sibling of [InlineErrorBanner], built on
/// [AppSemanticColors] so status colors never get hand-rolled again.
enum AppBannerTone { info, success, warning, error }

class InlineBanner extends StatelessWidget {
  final String message;
  final AppBannerTone tone;
  final IconData? icon;
  final Widget? trailing;

  const InlineBanner(
    this.message, {
    super.key,
    this.tone = AppBannerTone.info,
    this.icon,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final semantic = context.semanticColors;
    final textTheme = context.typography;

    final (Color bg, Color fg, IconData defaultIcon) = switch (tone) {
      AppBannerTone.info => (cs.secondaryContainer, cs.onSecondaryContainer, Icons.info_outline_rounded),
      AppBannerTone.success => (semantic.successContainer, semantic.onSuccessContainer, Icons.check_circle_outline_rounded),
      AppBannerTone.warning => (semantic.warningContainer, semantic.onWarningContainer, Icons.warning_amber_rounded),
      AppBannerTone.error => (cs.errorContainer, cs.onErrorContainer, Icons.error_outline_rounded),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadius.md)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? defaultIcon, size: AppIconSize.standard, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: textTheme.bodySmall?.copyWith(color: fg, height: 1.4)),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}

/// Standard keyboard-safe, gesture-nav-safe bottom sheet wrapper.
class AppBottomSheet extends StatelessWidget {
  final Widget child;
  const AppBottomSheet({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: AppSpacing.sheetPadding,
          child: child,
        ),
      ),
    );
  }
}

/// Obscure/reveal toggle icon for password fields.
class PasswordVisibilityToggle extends StatelessWidget {
  final bool obscured;
  final VoidCallback onToggle;
  const PasswordVisibilityToggle({
    super.key,
    required this.obscured,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        size: AppIconSize.small,
      ),
      onPressed: onToggle,
    );
  }
}


class AppCard extends StatelessWidget {
  final List<Widget> children;
  final bool dividers;
  final EdgeInsetsGeometry padding;

  final double dividerIndent;

  const AppCard({
    super.key,
    required this.children,
    this.dividers = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    this.dividerIndent = 68,
  });

  /// A card whose children are full-bleed rows (e.g. tappable list tiles)
  /// separated by inset dividers, matching about_screen's `_AboutGroup`.
  const AppCard.rows({
    super.key,
    required this.children,
    this.dividerIndent = 68,
  })  : dividers = true,
        padding = EdgeInsets.zero;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Card(
      color: cs.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      child: dividers
          ? Column(
              children: [
                for (int i = 0; i < children.length; i++) ...[
                  children[i],
                  if (i < children.length - 1)
                    Divider(height: 1, indent: dividerIndent, endIndent: 16),
                ],
              ],
            )
          : Padding(
              padding: padding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
    );
  }
}

/// Full-screen (or full-section) empty/error state: icon, headline, body,
/// and an optional primary action. Generalizes the pattern previously
/// duplicated across `EmptyState`, `_EmptyPlaceholder`, `_SearchEmptyState`.
class AppEmptyState extends StatefulWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData? actionIcon;

  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.actionIcon,
  });

  @override
  State<AppEmptyState> createState() => _AppEmptyStateState();
}

class _AppEmptyStateState extends State<AppEmptyState> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: AppMotion.long1)..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;
    final curved = CurvedAnimation(parent: _controller, curve: AppMotion.standard);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween(begin: 0.94, end: 1.0).animate(curved),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cs.surfaceContainer,
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: Icon(widget.icon, size: 30, color: cs.primary),
                ),
                const SizedBox(height: 24),
                Text(
                  widget.title,
                  style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  widget.message,
                  style: textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
                if (widget.actionLabel != null && widget.onAction != null) ...[
                  const SizedBox(height: 28),
                  FilledButton.icon(
                    onPressed: widget.onAction,
                    icon: Icon(widget.actionIcon ?? Icons.add_rounded, size: 18),
                    label: Text(widget.actionLabel!),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Fades + slightly slides its child in on first build. Use to give a list
/// of cards a gentle staggered entrance instead of popping in all at once —
/// pass the item's index so later items lag slightly behind earlier ones.
class StaggeredEntrance extends StatefulWidget {
  final int index;
  final Widget child;
  const StaggeredEntrance({super.key, required this.index, required this.child});

  @override
  State<StaggeredEntrance> createState() => _StaggeredEntranceState();
}

class _StaggeredEntranceState extends State<StaggeredEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: AppMotion.medium2);
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    final delayMs = 25 * widget.index.clamp(0, 12);
    Future.delayed(Duration(milliseconds: delayMs), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

/// Centralized SnackBar presenter so every screen shows the same shape,
/// duration, and icon language instead of hand-building `SnackBar(...)`
/// inline. Uses [AppSemanticColors] for success/warning tones.
void showAppSnackBar(
  BuildContext context, {
  required String message,
  AppBannerTone tone = AppBannerTone.info,
  IconData? icon,
  SnackBarAction? action,
}) {
  final cs = context.colors;
  final semantic = context.semanticColors;

  final (Color bg, Color fg, IconData defaultIcon) = switch (tone) {
    AppBannerTone.info => (cs.inverseSurface, cs.onInverseSurface, Icons.info_outline_rounded),
    AppBannerTone.success => (semantic.success, semantic.onSuccess, Icons.check_circle_rounded),
    AppBannerTone.warning => (semantic.warning, semantic.onWarning, Icons.warning_amber_rounded),
    AppBannerTone.error => (cs.error, cs.onError, Icons.error_outline_rounded),
  };

  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        backgroundColor: bg,
        content: Row(
          children: [
            Icon(icon ?? defaultIcon, color: fg, size: AppIconSize.standard),
            const SizedBox(width: 12),
            Expanded(
              child: Text(message, style: TextStyle(color: fg)),
            ),
          ],
        ),
        action: action,
      ),
    );
}

Future<bool> showAppConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool isDestructive = false,
}) async {
  final cs = context.colors;
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(cancelLabel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(
            confirmLabel,
            style: isDestructive ? TextStyle(color: cs.error) : null,
          ),
        ),
      ],
    ),
  );
  return result ?? false;
}


class SheetOptionTile extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  const SheetOptionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.iconColor,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;
    final accent = iconColor ?? cs.primary;

    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.md),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(AppRadius.sm + 4),
              ),
              child: Icon(icon, size: AppIconSize.action, color: accent),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

/// The "keyfiles" picker card — previously hand-duplicated (with minor
/// visual drift) across `unlock_sheet.dart`, `usb_unlock_sheet.dart`,
/// `container_config_sheet.dart`'s `_RealPasswordGateDialog`. One
/// implementation now backs all of them.
class KeyfilesPicker extends StatelessWidget {
  final List<KeyfileRef> keyfiles;
  final bool picking;
  final VoidCallback onPick;
  final ValueChanged<KeyfileRef> onRemove;
  final bool enabled;

  const KeyfilesPicker({
    super.key,
    required this.keyfiles,
    required this.picking,
    required this.onPick,
    required this.onRemove,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.insert_drive_file_outlined, size: AppIconSize.standard, color: cs.primary),
                  const SizedBox(width: 10),
                  Text(
                    'Keyfiles (optional)',
                    style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600, color: cs.onSurface),
                  ),
                ],
              ),
              TextButton.icon(
                onPressed: (enabled && !picking) ? onPick : null,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: picking
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add file'),
              ),
            ],
          ),
          if (keyfiles.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: keyfiles
                  .map(
                    (k) => InputChip(
                      avatar: Icon(Icons.description_outlined, size: 16, color: cs.onSurfaceVariant),
                      label: Text(k.displayName, style: textTheme.bodySmall, overflow: TextOverflow.ellipsis),
                      onDeleted: enabled ? () => onRemove(k) : null,
                      deleteIconColor: cs.error,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                      backgroundColor: cs.surfaceContainerHigh,
                    ),
                  )
                  .toList(),
            ),
          ] else ...[
            const SizedBox(height: 8),
            Text(
              'No keyfiles attached',
              style: textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The collapsible "Advanced parameters" (PIM / cipher / hash) panel —
/// previously hand-duplicated across the same three call sites as
/// [KeyfilesPicker]. [subtitle] is optional since only
/// `container_config_sheet.dart`'s top-level screen (not its dialogs) shows
/// one.
class AdvancedParamsPanel extends StatelessWidget {
  final TextEditingController? pimController;
  final int cipherId;
  final int hashId;
  final ValueChanged<int> onCipherChanged;
  final ValueChanged<int> onHashChanged;
  final bool enabled;
  final String? subtitle;

  /// Whether "Auto-detect" (id 255) is a valid choice in the cipher/hash
  /// dropdowns. True for unlock flows (native can search); must be false
  /// for creation flows, where a concrete algorithm has to be picked up
  /// front — see create_container_sheet.dart.
  final bool includeAuto;

  /// Extra fields rendered between the PIM field and the cipher dropdown.
  /// Exists so create_container_sheet.dart's file-system selector can live
  /// inside this same panel instead of needing its own separate one.
  final List<Widget> extraFields;

  /// Optional overrides for the cipher/hash dropdown item lists. Defaults
  /// to the full `CipherAlgo`/`HashAlgo` catalog (via [includeAuto]) when
  /// null — pass a filtered list (e.g. `CipherAlgo.luks2Choices`) for
  /// callers that need to restrict the choices to a container-format
  /// specific subset, without affecting any other call site.
  final List<DropdownMenuItem<int>>? cipherItems;
  final List<DropdownMenuItem<int>>? hashItems;

  const AdvancedParamsPanel({
    super.key,
    this.pimController,
    required this.cipherId,
    required this.hashId,
    required this.onCipherChanged,
    required this.onHashChanged,
    this.enabled = true,
    this.subtitle,
    this.includeAuto = true,
    this.extraFields = const [],
    this.cipherItems,
    this.hashItems,
  });

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        title: Text(
          'Advanced parameters',
          style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold, color: cs.onSurface),
        ),
        subtitle: subtitle != null
            ? Text(subtitle!, style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant))
            : null,
        leading: Icon(Icons.tune_rounded, color: cs.primary),
        childrenPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
        collapsedShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
        backgroundColor: cs.surfaceContainerLow,
        collapsedBackgroundColor: cs.surfaceContainerLow,
        children: [
          if (pimController != null) ...[
            TextField(
              controller: pimController,
              enabled: enabled,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'PIM  (leave blank for default)',
                prefixIcon: Icon(Icons.password_outlined, size: AppIconSize.small),
              ),
            ),
            const SizedBox(height: 16),
          ],
          for (final field in extraFields) ...[
            field,
            const SizedBox(height: 16),
          ],
          DropdownButtonFormField<int>(
            initialValue: cipherId,
            decoration: const InputDecoration(
              labelText: 'Encryption Algorithm',
              prefixIcon: Icon(Icons.security_rounded, size: AppIconSize.small),
            ),
            items: cipherItems ?? CipherAlgo.dropdownItems(includeAuto: includeAuto),
            onChanged: enabled
                ? (val) {
                    if (val != null) onCipherChanged(val);
                  }
                : null,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            initialValue: hashId,
            decoration: const InputDecoration(
              labelText: 'Hash Algorithm',
              prefixIcon: Icon(Icons.tag_rounded, size: AppIconSize.small),
            ),
            items: hashItems ?? HashAlgo.dropdownItems(includeAuto: includeAuto),
            onChanged: enabled
                ? (val) {
                    if (val != null) onHashChanged(val);
                  }
                : null,
          ),
        ],
      ),
    );
  }
}