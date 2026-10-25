import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/data/models/custom_app_skin.dart';
import 'package:vaultexplorer/features/skin_editor/skin_element_inspector.dart';
import 'package:vaultexplorer/features/skin_editor/skin_inline_color_editor.dart';
import 'package:vaultexplorer/features/skin_editor/skin_target.dart';

/// The panel that opens over the app while the picker is on.
///
/// It is deliberately small and does not dim or block the app: you pick an
/// element, drag the wheel, and watch the real screen change behind it. All
/// state lives in the owner; this widget only draws it and reports taps.
class SkinPickerPanel extends StatelessWidget {
  /// What the last tap found, or null before anything was tapped.
  final SkinPickResult? pick;

  /// Which of [pick]'s layers is selected, if the target came from a layer.
  final int? layerIndex;

  /// The color being edited, or null before anything was selected.
  final SkinTarget? target;

  final CustomAppSkin skin;

  /// The app's own theme, used to show what each color currently looks like.
  final ThemeData base;

  /// Whether the dark palette is the one being edited.
  final bool dark;

  final int undoDepth;
  final bool showAll;
  final bool collapsed;
  final double maxHeight;

  /// Whether the panel sits at the top of the screen rather than the bottom.
  final bool dockTop;

  /// True while a color is being dragged: the panel turns almost transparent so
  /// the whole page can be seen.
  final bool fade;

  /// Set when the selected color belongs to a part of the app (the file
  /// manager, the text editor) that is not drawn from this skin, so changing it
  /// shows nothing yet. Explains that and offers [onFollowAppSkin].
  final String? independentNotice;

  final ValueChanged<int> onSelectLayer;
  final ValueChanged<SkinTarget> onSelectTarget;
  final ValueChanged<Color> onColor;
  final VoidCallback onReset;
  final VoidCallback onToggleAll;
  final VoidCallback onToggleCollapsed;
  final VoidCallback onUndo;
  final ValueChanged<bool> onSetDark;
  final VoidCallback onMoreOptions;
  final VoidCallback onToggleDock;
  final ValueChanged<bool> onDock;
  final ValueChanged<bool> onInteraction;
  final VoidCallback onFollowAppSkin;

  const SkinPickerPanel({
    super.key,
    required this.pick,
    required this.layerIndex,
    required this.target,
    required this.skin,
    required this.base,
    required this.dark,
    required this.undoDepth,
    required this.showAll,
    required this.collapsed,
    required this.maxHeight,
    required this.dockTop,
    required this.fade,
    required this.independentNotice,
    required this.onSelectLayer,
    required this.onSelectTarget,
    required this.onColor,
    required this.onReset,
    required this.onToggleAll,
    required this.onToggleCollapsed,
    required this.onUndo,
    required this.onSetDark,
    required this.onMoreOptions,
    required this.onToggleDock,
    required this.onDock,
    required this.onInteraction,
    required this.onFollowAppSkin,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      // Hit testing is unaffected by opacity, so the drag in progress on the
      // wheel keeps working while the panel is see-through.
      opacity: fade ? 0.08 : 1,
      duration: const Duration(milliseconds: 120),
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 10,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _toolbar(context),
              if (!collapsed)
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    child: _body(context),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toolbar(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    const compact = VisualDensity.compact;
    return GestureDetector(
      // Flick the panel up or down to dock it to that edge, out of the way of
      // whatever is being picked.
      behavior: HitTestBehavior.opaque,
      onVerticalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity < -150) {
          onDock(true);
        } else if (velocity > 150) {
          onDock(false);
        }
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 6, 2, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  visualDensity: compact,
                  tooltip: dark ? l10n.skinDark : l10n.skinLight,
                  onPressed: () => onSetDark(!dark),
                  icon: Icon(
                    dark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                  ),
                ),
                const Spacer(),
                IconButton(
                  visualDensity: compact,
                  tooltip: l10n.undo,
                  onPressed: undoDepth > 0 ? onUndo : null,
                  icon: const Icon(Icons.undo_rounded),
                ),
                IconButton(
                  visualDensity: compact,
                  tooltip: dockTop
                      ? l10n.skinEditDockBottom
                      : l10n.skinEditDockTop,
                  onPressed: onToggleDock,
                  icon: Icon(
                    dockTop
                        ? Icons.vertical_align_bottom_rounded
                        : Icons.vertical_align_top_rounded,
                  ),
                ),
                IconButton(
                  visualDensity: compact,
                  tooltip: l10n.skinEditMoreOptions,
                  onPressed: onMoreOptions,
                  icon: const Icon(Icons.tune_rounded),
                ),
                IconButton(
                  visualDensity: compact,
                  tooltip: collapsed
                      ? l10n.skinEditExpand
                      : l10n.skinEditCollapse,
                  onPressed: onToggleCollapsed,
                  icon: Icon(
                    collapsed
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final pick = this.pick;
    final target = this.target;

    if (pick == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 4),
        child: Row(
          children: [
            Icon(Icons.touch_app_rounded, color: cs.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                l10n.skinEditHint,
                style: textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final layers = pick.layers;
    final layer = layerIndex != null && layerIndex! < layers.length
        ? layers[layerIndex!]
        : null;
    final alternatives = layer == null
        ? const <SkinTarget>[]
        : layer.candidates.take(6).toList();

    // With nothing painted there to match, the list is the only way in; once
    // a color is chosen from it the editor takes over.
    final listMode = showAll || (layers.isEmpty && target == null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (layers.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              l10n.skinEditNoMatch,
              style: textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          )
        else ...[
          Text(
            l10n.skinEditLayersTitle,
            style: textTheme.labelLarge?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < layers.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      selected: i == layerIndex,
                      avatar: _Dot(color: layers[i].color, size: 18),
                      label: Text(
                        '${layers[i].approximate ? '≈ ' : ''}'
                        '${layers[i].candidates.first.title(context)}',
                      ),
                      onSelected: (_) => onSelectLayer(i),
                    ),
                  ),
              ],
            ),
          ),
          if (layer != null && layer.approximate) ...[
            const SizedBox(height: 4),
            Text(
              l10n.skinEditClosest,
              style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
          if (alternatives.length > 1) ...[
            const SizedBox(height: 8),
            Text(
              l10n.skinEditAlsoUsedBy,
              style: textTheme.labelLarge?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final candidate in alternatives)
                  ChoiceChip(
                    selected: candidate == target,
                    label: Text(
                      '${candidate.title(context)} · '
                      '${candidate.group(context)}',
                    ),
                    onSelected: (_) => onSelectTarget(candidate),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 10),
        ],
        if (target != null) ...[
          _header(context, target),
          const SizedBox(height: 10),
          if (independentNotice != null) ...[
            _independentNotice(context, independentNotice!),
            const SizedBox(height: 10),
          ],
        ],
        if (listMode)
          _allColors(context)
        else if (target != null)
          SkinInlineColorEditor(
            key: ValueKey(target.id),
            color: target.current(skin, base, dark: dark),
            onChanged: onColor,
            onInteraction: onInteraction,
          ),
        // Nothing to go back to while the list is all there is.
        if (!(listMode && target == null)) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onToggleAll,
              icon: Icon(
                listMode ? Icons.palette_outlined : Icons.list_rounded,
              ),
              label: Text(
                listMode ? l10n.skinEditBackToEditor : l10n.skinEditAllColors,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _independentNotice(BuildContext context, String message) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.secondaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 20, color: cs.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    message,
                    style: textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onFollowAppSkin,
                icon: const Icon(Icons.palette_outlined),
                label: Text(l10n.skinFollowAppSkin),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, SkinTarget target) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final custom = target.isCustom(skin, dark: dark);
    return Row(
      children: [
        _Dot(color: target.current(skin, base, dark: dark), size: 36),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                target.title(context),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '${target.group(context)} · '
                '${custom ? l10n.skinCustomColor : l10n.skinEditStatusInherited}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (custom && target.canReset)
          TextButton.icon(
            onPressed: onReset,
            icon: const Icon(Icons.restart_alt_rounded),
            label: Text(l10n.skinEditReset),
          ),
      ],
    );
  }

  Widget _allColors(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final area = pick?.area;

    Widget header(String text) => Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: Text(
        text,
        style: textTheme.labelLarge?.copyWith(color: cs.onSurfaceVariant),
      ),
    );

    Widget tile(SkinTarget item) => ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: _Dot(color: item.current(skin, base, dark: dark), size: 28),
      title: Text(item.title(context)),
      subtitle: item.isCustom(skin, dark: dark)
          ? Text(l10n.skinCustomColor)
          : null,
      trailing: item == target ? Icon(Icons.check_rounded, color: cs.primary) : null,
      onTap: () => onSelectTarget(item),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (area != null) ...[
          header(l10n.skinEditPageColors(area.label(l10n))),
          for (final item in skinTargetsForArea(area)) tile(item),
        ],
        header(l10n.skinSharedPaletteTitle),
        for (final item in skinTargetsForArea(null)) tile(item),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  final Color color;
  final double size;

  const _Dot({required this.color, required this.size});

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(
        color: Theme.of(context).colorScheme.outlineVariant,
        width: 1.5,
      ),
    ),
  );
}
