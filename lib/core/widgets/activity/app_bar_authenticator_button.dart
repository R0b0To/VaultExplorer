import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/features/authenticator/authenticator_registry_controller.dart';
import 'package:vaultexplorer/features/authenticator/authenticator_screen.dart';
import 'package:vaultexplorer/features/settings/app_settings_controller.dart';

/// App bar action that appears only once at least one currently unlocked
/// vault has a TOTP-capable item (a standalone Authenticator entry, or a
/// `password` item with its optional 2FA field filled in), opening the
/// aggregated [AuthenticatorScreen].
///
/// Mirrors [AppBarTransferButton]'s show-only-when-relevant placement in
/// the dashboard's AppBar, but with no debounce/linger timers -- TOTP item
/// presence doesn't flicker the way transient file-operation status does,
/// so there's nothing here that needs smoothing over.
class AppBarAuthenticatorButton extends ConsumerWidget {
  const AppBarAuthenticatorButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(appSettingsControllerProvider.select((s) => s.settings.enableAuthenticator));
    if (!enabled) return const SizedBox.shrink();

    final hasEntries = ref.watch(authenticatorRegistryProvider.select((s) => s.hasAnyEntry));
    if (!hasEntries) return const SizedBox.shrink();

    return Tooltip(
      message: context.l10n.authenticatorAppBarTooltip,
      child: IconButton(
        icon: const Icon(Icons.verified_user_rounded),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AuthenticatorScreen()),
        ),
      ),
    );
  }
}
