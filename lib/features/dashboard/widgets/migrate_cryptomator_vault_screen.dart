import 'package:flutter/services.dart' show AutofillContextAction;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/features/dashboard/widgets/migrate_cryptomator_vault_controller.dart';

/// Confirmation + password screen for the one-way Cryptomator format 7 -> 8 upgrade. Pops with `true` after a
/// successful upgrade so the caller can re-probe the vault and drop its "Upgrade vault format" row.
///
/// The vault must be locked; the caller disables its entry point for a mounted vault and the native side
/// refuses regardless (error code VAULT_UNLOCKED, shown here as a message).
class MigrateCryptomatorVaultScreen extends ConsumerStatefulWidget {
  final String uri;

  const MigrateCryptomatorVaultScreen({super.key, required this.uri});

  @override
  ConsumerState<MigrateCryptomatorVaultScreen> createState() =>
      _MigrateCryptomatorVaultScreenState();
}

class _MigrateCryptomatorVaultScreenState
    extends ConsumerState<MigrateCryptomatorVaultScreen> {
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    ref
        .read(migrateCryptomatorVaultProvider(widget.uri).notifier)
        .submit(password: _passwordCtrl.text, l10n: context.l10n);
  }

  @override
  Widget build(BuildContext context) {
    final provider = migrateCryptomatorVaultProvider(widget.uri);
    final state = ref.watch(provider);
    ref.listen<MigrateCryptomatorVaultState>(provider, (previous, next) {
      if (next.successTick > (previous?.successTick ?? 0)) {
        showAppSnackBar(
          context,
          message: context.l10n.cryptomatorUpgradedMessage,
          tone: AppBannerTone.success,
        );
        Navigator.pop(context, true);
      }
    });

    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.l10n.cryptomatorUpgradeTitle,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cs.errorContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded, color: cs.error),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        context.l10n.cryptomatorUpgradeWarning,
                        style: textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              AutofillGroup(
                onDisposeAction: AutofillContextAction.cancel,
                child: TextField(
                  controller: _passwordCtrl,
                  obscureText: _obscure,
                  enabled: !state.isProcessing,
                  autofillHints: const <String>[AutofillHints.password],
                  onChanged: (value) => ref
                      .read(provider.notifier)
                      .setPasswordFilled(value.isNotEmpty),
                  decoration: InputDecoration(
                    labelText: context.l10n.passwordLabel,
                    filled: true,
                    fillColor: cs.surfaceContainerHighest,
                    prefixIcon: Icon(
                      Icons.lock_outline_rounded,
                      size: 20,
                      color: cs.primary,
                    ),
                    suffixIcon: PasswordVisibilityToggle(
                      obscured: _obscure,
                      onToggle: () => setState(() => _obscure = !_obscure),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: state.confirmed,
                onChanged: state.isProcessing
                    ? null
                    : (value) => ref
                          .read(provider.notifier)
                          .setConfirmed(value ?? false),
                title: Text(
                  context.l10n.cryptomatorUpgradeConfirm,
                  style: textTheme.bodyMedium,
                ),
              ),
              const SizedBox(height: 8),
              if (state.errorMsg != null) ...[
                InlineErrorBanner(state.errorMsg!),
                const SizedBox(height: 16),
              ],
              FilledButton(
                onPressed: state.canSubmit ? _submit : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  shape: const StadiumBorder(),
                ),
                child: state.isProcessing
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation(cs.onPrimary),
                        ),
                      )
                    : Text(
                        context.l10n.cryptomatorUpgradeAction,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
