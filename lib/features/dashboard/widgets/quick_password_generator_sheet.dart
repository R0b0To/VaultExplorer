import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/features/dashboard/widgets/quick_password_generator_controller.dart';

/// A small modal sheet that generates a Diceware passphrase or a random
/// character password and returns it (via [Navigator.pop]) to the caller.
///
/// Used by both the local and USB container-creation flows
/// ([CreateContainerSheet] and [UsbCreateContainerSheet]) -- previously each
/// had its own byte-for-byte copy of this class, which is how the "Use This
/// Password" button ended up hardcoded and un-localized in two places at
/// once instead of one. Extracted here so there's a single copy to fix.
class QuickPasswordGeneratorSheet extends ConsumerWidget {
  const QuickPasswordGeneratorSheet({super.key});

  Widget _buildPresetChip(BuildContext context, WidgetRef ref, String selectedPreset, String key, String label) {
    final selected = selectedPreset == key;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: selected,
      showCheckmark: false,
      onSelected: (sel) {
        if (sel) ref.read(quickPasswordGeneratorProvider.notifier).selectPreset(key);
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(quickPasswordGeneratorProvider);
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.password_rounded, size: 22, color: cs.primary),
              const SizedBox(width: 10),
              Text(
                context.l10n.quickPasswordGeneratorSheetTitle,
                style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                tooltip: context.l10n.generateNewTooltip,
                onPressed: () => ref.read(quickPasswordGeneratorProvider.notifier).regenerate(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
            ),
            child: SelectableText(
              state.generated,
              style: textTheme.titleMedium?.copyWith(
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
                color: cs.primary,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildPresetChip(context, ref, state.preset, 'dice5', '5 Words (Diceware)'),
                const SizedBox(width: 8),
                _buildPresetChip(context, ref, state.preset, 'dice6', '6 Words (Diceware)'),
                const SizedBox(width: 8),
                _buildPresetChip(context, ref, state.preset, 'char24', '24 Chars (Alphanumeric)'),
                const SizedBox(width: 8),
                _buildPresetChip(context, ref, state.preset, 'char32', '32 Chars (Complex)'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.check_rounded, size: 18),
            label: Text(context.l10n.useThisPasswordButton),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: state.generated.isEmpty ? null : () => Navigator.of(context).pop(state.generated),
          ),
        ],
      ),
    );
  }
}