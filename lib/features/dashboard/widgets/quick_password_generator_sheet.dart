import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/features/tools/services/keyfile_passphrase_generator_service.dart';

/// A small modal sheet that generates a Diceware passphrase or a random
/// character password and returns it (via [Navigator.pop]) to the caller.
///
/// Used by both the local and USB container-creation flows
/// ([CreateContainerSheet] and [UsbCreateContainerSheet]) -- previously each
/// had its own byte-for-byte copy of this class, which is how the "Use This
/// Password" button ended up hardcoded and un-localized in two places at
/// once instead of one. Extracted here so there's a single copy to fix.
class QuickPasswordGeneratorSheet extends StatefulWidget {
  const QuickPasswordGeneratorSheet({super.key});

  @override
  State<QuickPasswordGeneratorSheet> createState() => _QuickPasswordGeneratorSheetState();
}

class _QuickPasswordGeneratorSheetState extends State<QuickPasswordGeneratorSheet> {
  String _preset = 'dice5';
  String _generated = '';

  @override
  void initState() {
    super.initState();
    _regenerate();
  }

  Future<void> _regenerate() async {
    String pwd = '';
    if (_preset == 'dice5') {
      final res = await KeyfilePassphraseGeneratorService.generateDicewarePassphrase(
        wordCount: 5,
        separator: '-',
        casing: PasswordCasing.lowercase,
        includeNumber: true,
      );
      pwd = res.passphrase;
    } else if (_preset == 'dice6') {
      final res = await KeyfilePassphraseGeneratorService.generateDicewarePassphrase(
        wordCount: 6,
        separator: '-',
        casing: PasswordCasing.lowercase,
        includeNumber: true,
      );
      pwd = res.passphrase;
    } else if (_preset == 'char24') {
      final res = KeyfilePassphraseGeneratorService.generateCustomPassword(
        length: 24,
        useUppercase: true,
        useLowercase: true,
        useNumbers: true,
        useSymbols: true,
      );
      pwd = res.password;
    } else {
      final res = KeyfilePassphraseGeneratorService.generateCustomPassword(
        length: 32,
        useUppercase: true,
        useLowercase: true,
        useNumbers: true,
        useSymbols: true,
      );
      pwd = res.password;
    }
    if (mounted) setState(() => _generated = pwd);
  }

  @override
  Widget build(BuildContext context) {
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
                onPressed: _regenerate,
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
              _generated,
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
                _buildPresetChip('dice5', '5 Words (Diceware)'),
                const SizedBox(width: 8),
                _buildPresetChip('dice6', '6 Words (Diceware)'),
                const SizedBox(width: 8),
                _buildPresetChip('char24', '24 Chars (Alphanumeric)'),
                const SizedBox(width: 8),
                _buildPresetChip('char32', '32 Chars (Complex)'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.check_rounded, size: 18),
            label: Text(context.l10n.useThisPasswordButton),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _generated.isEmpty ? null : () => Navigator.of(context).pop(_generated),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetChip(String key, String label) {
    final selected = _preset == key;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: selected,
      showCheckmark: false,
      onSelected: (sel) {
        if (sel) {
          setState(() => _preset = key);
          _regenerate();
        }
      },
    );
  }
}
