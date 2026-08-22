part of 'vault_explorer_api.dart';

/// automation opt-in level for a single vault. Mirrors
/// AutomationSettings.AutomationTier (Kotlin) by name -- see
/// AutomationSettingsHandlers.kt for the wire contract.
enum AutomationTier {
  none('NONE'),
  lifecycle('LIFECYCLE'),
  full('FULL');

  final String wire;
  const AutomationTier(this.wire);

  static AutomationTier fromWire(String? wire) => values.firstWhere(
    (t) => t.wire == wire,
    orElse: () => AutomationTier.none,
  );

  String label(AppLocalizations l10n) => switch (this) {
    AutomationTier.none => l10n.automationTierOffLabel,
    AutomationTier.lifecycle => l10n.automationTierLifecycleLabel,
    AutomationTier.full => l10n.automationTierFullLabel,
  };

  String subtitle(AppLocalizations l10n) => switch (this) {
    AutomationTier.none => l10n.automationTierOffSubtitle,
    AutomationTier.lifecycle => l10n.automationTierLifecycleSubtitle,
    AutomationTier.full => l10n.automationTierFullSubtitle,
  };

  IconData get icon => switch (this) {
    AutomationTier.none => Icons.block_rounded,
    AutomationTier.lifecycle => Icons.lock_open_rounded,
    AutomationTier.full => Icons.sync_alt_rounded,
  };
}

typedef AutomationVaultConfig = ({
  AutomationTier tier,
  String? format,
  bool hasStoredPassword,
});

mixin _AutomationOps {
  /// Current automation API token, generating one on first call.
  /// One token per install, shared by every vault -- not per-vault (see
  /// AutomationSettings.kt).
  Future<String?> getAutomationToken() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        ChannelMethods.getAutomationToken,
      );
      return result?['token'] as String?;
    } catch (e) {
      _logSwallowed('getAutomationToken', e);
      return null;
    }
  }

  /// Rotates the token. Any automation profile still using the old value
  /// will silently stop working -- VaultAutomationReceiver.kt gives no
  /// reply at all on a bad token -- until it's updated with the new one.
  Future<String?> regenerateAutomationToken() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        ChannelMethods.regenerateAutomationToken,
      );
      return result?['token'] as String?;
    } catch (e) {
      _logSwallowed('regenerateAutomationToken', e);
      return null;
    }
  }

  Future<AutomationVaultConfig> getAutomationVaultConfig(
    String vaultUri,
  ) async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        ChannelMethods.getAutomationVaultConfig,
        {'vaultUri': vaultUri},
      );
      return (
        tier: AutomationTier.fromWire(result?['tier'] as String?),
        format: result?['format'] as String?,
        hasStoredPassword: result?['hasStoredPassword'] as bool? ?? false,
      );
    } catch (e) {
      _logSwallowed('getAutomationVaultConfig', e);
      return (
        tier: AutomationTier.none,
        format: null,
        hasStoredPassword: false,
      );
    }
  }

  /// [format] should be the vault's [ContainerFormat.wire] value
  /// ('cryptomator' / 'gocryptfs' / 'cryfs') for a directory vault, or
  /// null for a standard block-device container -- see
  /// AutomationSettingsHandlers.kt's wireFormatToDirectoryFormat. Passing
  /// the wrong format for a directory vault won't error here, but its
  /// later UNLOCK_VAULT automation calls will fail -- see
  /// VaultAutomationReceiver.handleUnlock.
  Future<bool> setAutomationTier(
    String vaultUri,
    AutomationTier tier, {
    String? format,
  }) async {
    try {
      final success = await _channel.invokeMethod<bool>(
        ChannelMethods.setAutomationTier,
        {'vaultUri': vaultUri, 'tier': tier.wire, 'format': format},
      );
      return success ?? false;
    } catch (e) {
      _logSwallowed('setAutomationTier', e);
      return false;
    }
  }

  /// Pass null or an empty string to clear the stored password. There is
  /// deliberately no getter for this -- see AutomationSettingsHandlers.kt.
  Future<bool> setAutomationPassword(String vaultUri, String? password) async {
    try {
      final success = await _channel.invokeMethod<bool>(
        ChannelMethods.setAutomationPassword,
        {'vaultUri': vaultUri, 'password': password},
      );
      return success ?? false;
    } catch (e) {
      _logSwallowed('setAutomationPassword', e);
      return false;
    }
  }
}
