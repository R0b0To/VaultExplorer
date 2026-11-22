import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/widgets/menus/back_dismissible_menu_anchor.dart';

Widget _noWidget(BuildContext context) => const SizedBox.shrink();

/// One entry of an [AdaptiveActionStrip].
///
/// An entry always has an inline form ([builder], normally an [IconButton] or
/// a menu anchor button). When it also has a [menuBuilder] it may collapse
/// into the strip's overflow menu if the strip runs out of room; without one
/// it is pinned and always stays inline.
@immutable
class AdaptiveActionItem {
  const AdaptiveActionItem({
    required this.id,
    required this.builder,
    this.menuBuilder,
    this.priority = 0,
  }) : isSeparator = false;

  /// A thin vertical divider between groups. It is drawn only while there is
  /// a visible action on both sides of it, so a group that has collapsed
  /// entirely never leaves a dangling divider behind.
  const AdaptiveActionItem.separator({required this.id})
    : builder = _noWidget,
      menuBuilder = null,
      priority = 0,
      isSeparator = true;

  /// Stable identity. Keeps an open menu or hover state attached to its
  /// button while the item moves between the strip and the overflow menu.
  final Object id;

  /// The inline widget.
  final WidgetBuilder builder;

  /// The same action as an overflow-menu entry (a [MenuItemButton], or a
  /// [SubmenuButton] for actions that open their own menu). Null pins the
  /// item inline. May return null for an action that has nothing to show.
  final Widget? Function(BuildContext context)? menuBuilder;

  /// Which items collapse first: lower priority goes into the overflow menu
  /// before higher priority. Among equal priorities the later item collapses
  /// first, so the user's configured order is respected.
  final int priority;

  final bool isSeparator;

  bool get isCollapsible => !isSeparator && menuBuilder != null;
}

/// The result of fitting a list of items into a width.
@immutable
class AdaptiveActionLayout {
  const AdaptiveActionLayout({required this.inline, required this.overflow});

  /// Indexes (into the item list) drawn in the strip, in order. Separators
  /// that would dangle have already been removed.
  final List<int> inline;

  /// Indexes of the items collapsed into the overflow menu, in order. When
  /// this is not empty the strip also draws the overflow button.
  final List<int> overflow;
}

/// Decides which [items] stay inline and which collapse into the overflow
/// menu for a strip [available] logical pixels wide.
///
/// Every action button is [itemExtent] wide and every separator
/// [separatorExtent]; the overflow button costs one [itemExtent]. Because the
/// button costs what one collapsed action frees, collapsing a lone action only
/// happens when it also frees a separator -- otherwise it would be a worse
/// deal than showing it.
@visibleForTesting
AdaptiveActionLayout planAdaptiveActionLayout({
  required List<AdaptiveActionItem> items,
  required double available,
  required double itemExtent,
  required double separatorExtent,
}) {
  final all = List<int>.generate(items.length, (i) => i);

  // What the strip draws once [hidden] is collapsed: separators are kept only
  // between two visible actions, never leading, trailing or doubled.
  List<int> inlineWithout(Set<int> hidden) {
    final inline = <int>[];
    for (final i in all) {
      if (hidden.contains(i)) continue;
      if (items[i].isSeparator &&
          (inline.isEmpty || items[inline.last].isSeparator)) {
        continue;
      }
      inline.add(i);
    }
    while (inline.isNotEmpty && items[inline.last].isSeparator) {
      inline.removeLast();
    }
    return inline;
  }

  double widthOf(List<int> indexes) {
    var width = 0.0;
    for (final i in indexes) {
      width += items[i].isSeparator ? separatorExtent : itemExtent;
    }
    return width;
  }

  final hidden = <int>{};
  if (widthOf(inlineWithout(hidden)) > available) {
    // Make room for the overflow button, then collapse the least important
    // items until what is left fits.
    final budget = available - itemExtent;
    final candidates = all.where((i) => items[i].isCollapsible).toList()
      ..sort((a, b) {
        final byPriority = items[a].priority.compareTo(items[b].priority);
        return byPriority != 0 ? byPriority : b.compareTo(a);
      });
    for (final index in candidates) {
      if (widthOf(inlineWithout(hidden)) <= budget) break;
      hidden.add(index);
    }
  }

  return AdaptiveActionLayout(
    inline: inlineWithout(hidden),
    overflow: [
      for (final i in all)
        if (hidden.contains(i)) i,
    ],
  );
}

/// A row of toolbar actions that never overlaps, clips or hides an action
/// when its window is resized.
///
/// It shows as many actions inline as fit and moves the rest into a trailing
/// "more" menu, the standard modern responsive-toolbar pattern (Material's
/// action-overflow, and what desktop apps like Files, Finder and VS Code do).
/// Nothing is ever only reachable by scrolling the strip. Actions come back
/// inline, in their configured order, as soon as the window is wide enough.
///
/// The strip's width comes from its own constraints. Inside an [AppBar]'s
/// `actions` (which are laid out with unbounded width) there are no useful
/// constraints, so the caller passes [availableWidth] explicitly.
class AdaptiveActionStrip extends StatelessWidget {
  const AdaptiveActionStrip({
    super.key,
    required this.items,
    this.itemExtent = 48,
    this.separatorExtent = 9,
    this.availableWidth,
    this.rebuildOn,
    this.overflowIcon = Icons.more_horiz_rounded,
    this.overflowTooltip,
  });

  final List<AdaptiveActionItem> items;

  /// Width reserved for each inline action: 48 for app-bar buttons, 40 for
  /// the compact desktop bar.
  final double itemExtent;

  final double separatorExtent;

  /// Width to fit into. When null the strip uses its own bounded
  /// constraints, and shows everything if they are unbounded.
  final double? availableWidth;

  /// Rebuilds the strip, including the overflow menu entries, when this
  /// changes. For state the entries read live, such as music mode.
  final Listenable? rebuildOn;

  final IconData overflowIcon;

  /// Defaults to the localized "More options".
  final String? overflowTooltip;

  @override
  Widget build(BuildContext context) {
    final listenable = rebuildOn;
    if (listenable == null) return _buildFitted(context);
    return ListenableBuilder(
      listenable: listenable,
      builder: (context, _) => _buildFitted(context),
    );
  }

  Widget _buildFitted(BuildContext context) {
    final fixed = availableWidth;
    if (fixed != null) return _buildRow(context, fixed);
    return LayoutBuilder(
      builder: (context, constraints) => _buildRow(
        context,
        constraints.hasBoundedWidth ? constraints.maxWidth : double.infinity,
      ),
    );
  }

  Widget _buildRow(BuildContext context, double available) {
    final layout = planAdaptiveActionLayout(
      items: items,
      available: available,
      itemExtent: itemExtent,
      separatorExtent: separatorExtent,
    );

    final children = <Widget>[
      for (final index in layout.inline)
        if (items[index].isSeparator)
          KeyedSubtree(
            key: ValueKey<Object>(items[index].id),
            child: SizedBox(
              width: separatorExtent,
              height: 24,
              child: VerticalDivider(width: separatorExtent, thickness: 1),
            ),
          )
        else
          KeyedSubtree(
            key: ValueKey<Object>(items[index].id),
            child: SizedBox(
              width: itemExtent,
              child: Center(child: items[index].builder(context)),
            ),
          ),
    ];

    if (layout.overflow.isNotEmpty) {
      final entries = <Widget>[
        for (final index in layout.overflow)
          if (items[index].menuBuilder!(context) case final Widget entry) entry,
      ];
      if (entries.isNotEmpty) {
        children.add(
          SizedBox(
            width: itemExtent,
            child: Center(
              child: BackDismissibleMenuAnchor(
                menuChildren: entries,
                builder: (context, controller, _) => IconButton(
                  icon: Icon(overflowIcon),
                  tooltip: overflowTooltip ?? context.l10n.moreOptionsTooltip,
                  onPressed: () => controller.isOpen
                      ? controller.close()
                      : controller.open(),
                ),
              ),
            ),
          ),
        );
      }
    }

    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }
}

/// Width an [AppBar] can give its trailing actions: the whole bar minus the
/// leading button, the title's minimum, and whatever else shares the actions
/// slot ([otherActionsWidth]).
///
/// An [AppBar] lays its `actions` out with unbounded width, so a strip inside
/// it cannot measure itself; the caller measures the bar once (see
/// [WidthAwareAppBar]) and uses this to decide the share left for actions.
double appBarActionsBudget({
  required double barWidth,
  required bool hasLeading,
  double minTitleWidth = 160,
  double otherActionsWidth = 0,
}) {
  const leadingExtent = 56.0; // kToolbarHeight-wide leading slot
  const titleSpacing = 16.0;
  final budget =
      barWidth -
      (hasLeading ? leadingExtent : 0) -
      titleSpacing -
      minTitleWidth -
      otherActionsWidth;
  return budget < 0 ? 0 : budget;
}

/// A [PreferredSizeWidget] that tells [builder] how wide the bar is, so the
/// [AppBar] it returns can budget its actions with [appBarActionsBudget].
class WidthAwareAppBar extends StatelessWidget implements PreferredSizeWidget {
  const WidthAwareAppBar({
    super.key,
    required this.builder,
    this.toolbarHeight = kToolbarHeight,
  });

  final Widget Function(BuildContext context, double barWidth) builder;
  final double toolbarHeight;

  @override
  Size get preferredSize => Size.fromHeight(toolbarHeight);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => builder(
        context,
        constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width,
      ),
    );
  }
}
