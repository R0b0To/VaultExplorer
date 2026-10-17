import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/widgets/layout/section_card.dart';
import 'package:vaultexplorer/features/settings/search/settings_search_models.dart';

/// The pill-shaped "Search settings" field shown above the settings hubs.
class SettingsSearchField extends StatelessWidget {
  const SettingsSearchField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final borderRadius = BorderRadius.circular(28);
    const noBorder = BorderSide.none;

    return TextField(
      controller: controller,
      focusNode: focusNode,
      textInputAction: TextInputAction.search,
      onChanged: onChanged,
      onSubmitted: (_) => onSubmitted(),
      decoration: InputDecoration(
        hintText: context.l10n.settingsSearchHint,
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) {
            if (value.text.isEmpty) return const SizedBox.shrink();
            return IconButton(
              icon: const Icon(Icons.close_rounded),
              tooltip: context.l10n.settingsSearchClear,
              onPressed: () {
                controller.clear();
                onChanged('');
                focusNode.requestFocus();
              },
            );
          },
        ),
        filled: true,
        fillColor: cs.surfaceContainerHigh,
        contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        border: OutlineInputBorder(borderRadius: borderRadius, borderSide: noBorder),
        enabledBorder:
            OutlineInputBorder(borderRadius: borderRadius, borderSide: noBorder),
        focusedBorder: OutlineInputBorder(
          borderRadius: borderRadius,
          borderSide: BorderSide(color: cs.primary, width: 1.5),
        ),
      ),
    );
  }
}

/// The ranked results list that replaces the hub list while a query is typed.
class SettingsSearchResults extends StatelessWidget {
  const SettingsSearchResults({
    super.key,
    required this.results,
    required this.onOpen,
  });

  final List<ResolvedSettingsEntry> results;
  final ValueChanged<ResolvedSettingsEntry> onOpen;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        child: Column(
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 48,
              color: cs.onSurfaceVariant.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 12),
            Text(
              context.l10n.settingsSearchNoResults,
              textAlign: TextAlign.center,
              style: textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              context.l10n.settingsSearchNoResultsHint,
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    final separator =
        Directionality.of(context) == TextDirection.rtl ? ' ‹ ' : ' › ';

    return SectionCard(
      children: [
        for (final result in results)
          _ResultTile(
            result: result,
            separator: separator,
            onTap: () => onOpen(result),
          ),
      ],
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({
    required this.result,
    required this.separator,
    required this.onTap,
  });

  final ResolvedSettingsEntry result;
  final String separator;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final (icon, color) = _hubVisual(result.destination.hub, cs);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 22),
      ),
      title: Text(
        result.title,
        style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          result.breadcrumb.join(separator),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      ),
      onTap: onTap,
    );
  }
}

/// The icon and tint of each hub, matching its tile on the settings screen.
(IconData, Color) _hubVisual(SettingsHub hub, ColorScheme cs) => switch (hub) {
      SettingsHub.security => (Icons.shield_rounded, cs.primary),
      SettingsHub.storage =>
        (Icons.settings_input_composite_rounded, cs.secondary),
      SettingsHub.fileHandling => (Icons.folder_copy_rounded, cs.tertiary),
      SettingsHub.fileManager => (Icons.tune_rounded, Colors.blueAccent),
      SettingsHub.appearance =>
        (Icons.palette_rounded, Colors.deepPurpleAccent),
      SettingsHub.advanced => (Icons.terminal_rounded, Colors.teal),
      SettingsHub.about => (Icons.info_outline_rounded, cs.primary),
    };
