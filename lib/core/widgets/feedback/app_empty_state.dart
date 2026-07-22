import 'package:flutter/material.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';

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
