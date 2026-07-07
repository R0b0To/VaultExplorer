import 'package:flutter/material.dart';
import '../theme.dart';

/// Uppercased, letter-spaced section header used above grouped settings
/// cards. Single source of truth — do not re-inline this elsewhere.
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

// ─────────────────────────────────────────────────────────────────────────────
// NEW: shared M3 building blocks
// ─────────────────────────────────────────────────────────────────────────────

/// Grouped settings/tile card — the pattern that used to be hand-copied as
/// `_Card` (app_settings_screen.dart) and `_AboutGroup` (about_screen.dart).
/// One rounded tonal Card containing rows separated by hairline dividers
/// (or, for [SettingsToggleRow]-style content, plain spacing — pass
/// [dividers]: false to omit them).
class AppCard extends StatelessWidget {
  final List<Widget> children;
  final bool dividers;
  final EdgeInsetsGeometry padding;

  const AppCard({
    super.key,
    required this.children,
    this.dividers = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  });

  /// A card whose children are full-bleed rows (e.g. tappable list tiles)
  /// separated by inset dividers, matching about_screen's `_AboutGroup`.
  const AppCard.rows({super.key, required this.children})
      : dividers = true,
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
                    const Divider(height: 1, indent: 68, endIndent: 16),
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

/// A tappable option row for bottom sheets that present a small set of
/// choices (e.g. "Mount file" / "Mount USB" / "Create new") — replaces the
/// ad hoc PopupMenuButton + Icon + Text rows previously hand-built per
/// screen. Designed to sit inside a [showModalBottomSheet].
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