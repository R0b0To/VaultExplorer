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
  bool hasStoredKeyfiles,
  int? storedPim,
  bool captureEnabled,
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
        hasStoredKeyfiles: result?['hasStoredKeyfiles'] as bool? ?? false,
        storedPim: result?['storedPim'] as int?,
        captureEnabled: result?['captureEnabled'] as bool? ?? false,
      );
    } catch (e) {
      _logSwallowed('getAutomationVaultConfig', e);
      return (
        tier: AutomationTier.none,
        format: null,
        hasStoredPassword: false,
        hasStoredKeyfiles: false,
        storedPim: null,
        captureEnabled: false,
      );
    }
  }

  /// Only takes effect while the vault is at [AutomationTier.full] -- see
  /// AutomationSettings.canCapture (Kotlin) for why TAKE_PHOTO/
  /// START_RECORDING need this *in addition to* full tier rather than
  /// riding along with it. Moving the vault off full tier and back clears
  /// this again server-side, so the UI should re-fetch
  /// [getAutomationVaultConfig] after any [setAutomationTier] call rather
  /// than assuming this stays set.
  Future<bool> setAutomationCaptureEnabled(
    String vaultUri,
    bool enabled,
  ) async {
    try {
      final success = await _channel.invokeMethod<bool>(
        ChannelMethods.setAutomationCaptureEnabled,
        {'vaultUri': vaultUri, 'enabled': enabled},
      );
      return success ?? false;
    } catch (e) {
      _logSwallowed('setAutomationCaptureEnabled', e);
      return false;
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

  Future<List<String>?> getAutomationKeyfiles(String vaultUri) async {
    try {
      final result = await _channel.invokeListMethod<String>(
        ChannelMethods.getAutomationKeyfiles,
        {'vaultUri': vaultUri},
      );
      return result;
    } catch (e) {
      _logSwallowed('getAutomationKeyfiles', e);
      return null;
    }
  }

  Future<bool> setAutomationKeyfiles(
    String vaultUri,
    List<String>? keyfilePaths,
  ) async {
    try {
      final success = await _channel.invokeMethod<bool>(
        ChannelMethods.setAutomationKeyfiles,
        {'vaultUri': vaultUri, 'keyfilePaths': keyfilePaths},
      );
      return success ?? false;
    } catch (e) {
      _logSwallowed('setAutomationKeyfiles', e);
      return false;
    }
  }

  Future<int?> getAutomationPim(String vaultUri) async {
    try {
      final result = await _channel.invokeMethod<int>(
        ChannelMethods.getAutomationPim,
        {'vaultUri': vaultUri},
      );
      return result;
    } catch (e) {
      _logSwallowed('getAutomationPim', e);
      return null;
    }
  }

  Future<bool> setAutomationPim(String vaultUri, int? pim) async {
    try {
      final success = await _channel.invokeMethod<bool>(
        ChannelMethods.setAutomationPim,
        {'vaultUri': vaultUri, 'pim': pim},
      );
      return success ?? false;
    } catch (e) {
      _logSwallowed('setAutomationPim', e);
      return false;
    }
  }

  /// Ground-truth reconciliation: every container session actually active
  /// right now, regardless of what mounted or unmounted it -- a normal
  /// in-app unlock/lock, VaultAutomationReceiver's UNLOCK_VAULT (which can
  /// run with no Activity and so no Flutter engine at all), or
  /// VaultKeepAliveService's "Lock all vaults" notification action (same
  /// headless situation, opposite direction). Mirrors
  /// VaultUnlockHandlers.handleGetActiveContainerSessions on the native
  /// side.
  ///
  /// VaultAutomationUnlockedBridge/VaultForceLockedBridge only cover the
  /// case a Flutter engine happens to already be attached when one of
  /// those fires; call this on dashboard init and on every app resume to
  /// catch whatever those missed (e.g. unlocked or locked headlessly while
  /// the app was closed).
  Future<List<MountedContainer>> getActiveContainerSessions() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        ChannelMethods.getActiveContainerSessions,
      );
      final sessions = (result?['sessions'] as List?) ?? const [];
      return sessions
          .cast<Map<Object?, Object?>>()
          .map(
            (s) => MountedContainer(
              uri: s['uri'] as String,
              displayName: s['displayName'] as String? ?? s['uri'] as String,
              volId: s['volId'] as int,
              rootFiles: (s['files'] as List?)?.cast<String>() ?? const [],
              mountedAt: DateTime.now(),
              totalSpace: 0,
              freeSpace: 0,
              containerFormat: s['containerFormat'] as String? ?? 'veracrypt',
              readOnly: s['readOnly'] as bool? ?? false,
            ),
          )
          .toList();
    } catch (e) {
      _logSwallowed('getActiveContainerSessions', e);
      return const [];
    }
  }
}