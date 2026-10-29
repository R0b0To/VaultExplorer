import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/models/tab_swipe_gestures.dart';
import 'package:vaultexplorer/features/settings/app_settings_controller.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

/// The file manager's tab swipe gestures, each one set on its own:
///
///  * whether swiping sideways moves between tabs;
///  * what a right swipe does on the first tab (or anywhere, with tab
///    swiping off): open the side menu, loop to the last tab, or nothing;
///  * what a left swipe does on the last tab (or anywhere, with tab swiping
///    off): open a new tab, loop to the first tab, or nothing.
///
/// A small preview above the two pickers shows what ends up at either end of
/// the tabs, so a combination can be read at a glance.
class TabSwipeGesturesSection extends ConsumerWidget {
  const TabSwipeGesturesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final enabled = ref.watch(
      appSettingsControllerProvider.select((s) => s.settings.useBrowserTabs),
    );
    final gestures = ref.watch(
      appSettingsControllerProvider.select((s) => s.settings.tabSwipeGestures),
    );
    final swiping = gestures.swipeBetweenTabs;

    void update(TabSwipeGestures Function(TabSwipeGestures current) change) {
      ref
          .read(appSettingsControllerProvider.notifier)
          .updateSettings(
            (settings) => settings.copyWith(
              tabSwipeGestures: change(settings.tabSwipeGestures),
            ),
          );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(l10n.tabEdgeSwipeLabel),
        SectionCard(
          children: [
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              value: swiping,
              onChanged: enabled
                  ? (value) => update((g) => g.copyWith(swipeBetweenTabs: value))
                  : null,
              title: Text(
                l10n.tabSwipeBetweenTabsTitle,
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                swiping
                    ? l10n.tabSwipeBetweenTabsOnDesc
                    : l10n.tabSwipeBetweenTabsOffDesc,
                style: textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              secondary: Icon(
                Icons.swap_horiz_rounded,
                color: enabled ? cs.primary : cs.onSurfaceVariant,
              ),
            ),
            _TabSwipePreview(gestures: gestures, enabled: enabled),
            // Right swipe first: it is what ends up at the left end of the
            // tabs, so the two pickers read in the same order as the preview.
            OptionPickerTile<TabRightSwipeAction>(
              label: swiping
                  ? l10n.tabSwipeRightOnFirstTab
                  : l10n.tabSwipeRightAnywhere,
              value: gestures.rightSwipe,
              enabled: enabled,
              prefixIcon: Icons.arrow_forward_rounded,
              options: [
                for (final action in gestures.rightSwipeChoices)
                  SelectOption(
                    value: action,
                    label: _rightLabel(l10n, action),
                    subtitle: _rightDescription(l10n, action),
                  ),
              ],
              onChanged: (action) => update((g) => g.copyWith(rightSwipe: action)),
            ),
            OptionPickerTile<TabLeftSwipeAction>(
              label: swiping
                  ? l10n.tabSwipeLeftOnLastTab
                  : l10n.tabSwipeLeftAnywhere,
              value: gestures.leftSwipe,
              enabled: enabled,
              prefixIcon: Icons.arrow_back_rounded,
              options: [
                for (final action in gestures.leftSwipeChoices)
                  SelectOption(
                    value: action,
                    label: _leftLabel(l10n, action),
                    subtitle: _leftDescription(l10n, action),
                  ),
              ],
              onChanged: (action) => update((g) => g.copyWith(leftSwipe: action)),
            ),
          ],
        ),
      ],
    );
  }

  static String _rightLabel(AppLocalizations l10n, TabRightSwipeAction action) =>
      switch (action) {
        TabRightSwipeAction.openDrawer => l10n.tabSwipeActionOpenDrawer,
        TabRightSwipeAction.loopToLast => l10n.tabSwipeActionLoopLast,
        TabRightSwipeAction.nothing => l10n.tabSwipeActionNothing,
      };

  static String? _rightDescription(
    AppLocalizations l10n,
    TabRightSwipeAction action,
  ) => switch (action) {
    TabRightSwipeAction.openDrawer => null,
    TabRightSwipeAction.loopToLast => l10n.tabSwipeRightLoopDesc,
    TabRightSwipeAction.nothing => l10n.tabSwipeRightNothingDesc,
  };

  static String _leftLabel(AppLocalizations l10n, TabLeftSwipeAction action) =>
      switch (action) {
        TabLeftSwipeAction.newTab => l10n.tabSwipeActionNewTab,
        TabLeftSwipeAction.loopToFirst => l10n.tabSwipeActionLoopFirst,
        TabLeftSwipeAction.nothing => l10n.tabSwipeActionNothing,
      };

  static String? _leftDescription(
    AppLocalizations l10n,
    TabLeftSwipeAction action,
  ) => switch (action) {
    TabLeftSwipeAction.newTab => null,
    TabLeftSwipeAction.loopToFirst ||
    TabLeftSwipeAction.nothing => l10n.tabSwipeNewTabsFromStripDesc,
  };
}

/// Three tabs with what a right swipe (left end) and a left swipe (right end)
/// lead to. Always laid out left to right, even in a right-to-left language,
/// because it pictures what happens on the screen, not the reading order.
class _TabSwipePreview extends StatelessWidget {
  const _TabSwipePreview({required this.gestures, required this.enabled});

  final TabSwipeGestures gestures;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final swiping = gestures.swipeBetweenTabs;

    final (IconData, String) leftEnd = switch (gestures.rightSwipe) {
      TabRightSwipeAction.openDrawer => (Icons.menu_rounded, l10n.skinAreaDrawer),
      TabRightSwipeAction.loopToLast => (
        Icons.loop_rounded,
        l10n.tabSwipePreviewLastTab,
      ),
      TabRightSwipeAction.nothing => (Icons.block_rounded, l10n.offLabel),
    };
    final (IconData, String) rightEnd = switch (gestures.leftSwipe) {
      TabLeftSwipeAction.newTab => (Icons.add_rounded, l10n.browserTabNew),
      TabLeftSwipeAction.loopToFirst => (
        Icons.loop_rounded,
        l10n.tabSwipePreviewFirstTab,
      ),
      TabLeftSwipeAction.nothing => (Icons.block_rounded, l10n.offLabel),
    };

    Widget connector() => swiping
        ? Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Icon(
              Icons.swap_horiz_rounded,
              size: 16,
              color: cs.onSurfaceVariant,
            ),
          )
        : const SizedBox(width: 8);

    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              _PreviewEnd(
                icon: leftEnd.$1,
                label: leftEnd.$2,
                active: gestures.rightSwipe != TabRightSwipeAction.nothing,
              ),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const _PreviewTab(label: '1'),
                    connector(),
                    const _PreviewTab(label: '2', selected: true),
                    connector(),
                    const _PreviewTab(label: '3'),
                  ],
                ),
              ),
              _PreviewEnd(
                icon: rightEnd.$1,
                label: rightEnd.$2,
                active: gestures.leftSwipe != TabLeftSwipeAction.nothing,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreviewTab extends StatelessWidget {
  const _PreviewTab({required this.label, this.selected = false});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? cs.primary : cs.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected ? cs.primary : cs.outlineVariant,
        ),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: selected ? cs.onPrimary : cs.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _PreviewEnd extends StatelessWidget {
  const _PreviewEnd({
    required this.icon,
    required this.label,
    required this.active,
  });

  final IconData icon;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 76,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? cs.primaryContainer : cs.surface,
            ),
            child: Icon(
              icon,
              size: 20,
              color: active ? cs.onPrimaryContainer : cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
