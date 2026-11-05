import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/features/authenticator/authenticator_screen.dart';
import 'package:vaultexplorer/features/settings/app_settings_controller.dart';

/// App bar action that opens the aggregated [AuthenticatorScreen] whenever
/// the Authenticator feature is enabled in settings.
///
/// It is shown regardless of whether any unlocked vault currently holds a
/// TOTP-capable item (a standalone Authenticator entry, or a `password`
/// item with its optional 2FA field filled in): the screen's own empty
/// states explain what to unlock or add, which keeps the feature
/// discoverable. The side drawer offers the same destination so it is
/// reachable from every tab, not only the dashboard.
class AppBarAuthenticatorButton extends ConsumerWidget {
  const AppBarAuthenticatorButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(
      appSettingsControllerProvider.select((s) => s.settings.enableAuthenticator),
    );
    if (!enabled) return const SizedBox.shrink();

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