// Dart-side platform bridge for the Emergency Panic, PanicKit, and Quick
// Settings Tile systems (architecture plan Component 5/6) -- see
// PanicSettingsHandlers.kt for the wire contract this wraps, and
// PanicManager.kt / PanicTier.kt (Kotlin) for what each tier actually
// purges once triggered. Everything here is a thin, defensive wrapper:
// every method already has a safe, least-destructive fallback so a
// dropped platform-channel call (engine detached, method missing on an
// old build) never surfaces as a crash in a settings screen -- and never
// silently reports a *more* dangerous configuration than what's really
// stored (see each fallback's own comment).
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/core/api/vault_engine_types.dart';
import 'package:vaultexplorer/data/services/vault_engine/channel_methods.dart';

/// Mirrors PanicTier (Kotlin) by ordinal -- see that enum's own doc
/// comment for what each level's cascade actually purges (each tier
/// re-runs every tier below it). [level] is the exact wire value
/// PanicSettingsHandlers.kt sends and expects back.
enum PanicTier {
  sessionPurge(1),
  credentialPurge(2),
  nuclearWipe(3);

  final int level;
  const PanicTier(this.level);

  static PanicTier fromLevel(int? level) => values.firstWhere(
    (t) => t.level == level,
    orElse: () => PanicTier.sessionPurge,
  );
}

typedef PanicSettingsSnapshot = ({
  PanicTier configuredTier,
  bool quickTileEnabled,
});

typedef PanicKitStatus = ({
  bool responderEnabled,
  bool pairingEnforcementEnabled,
  String? trustedPackage,
  bool hasTrustedCert,
});

typedef PanicTriggerResult = ({
  bool success,
  int containersLocked,
  int keystoreAliasesPurged,
  int filesWiped,
});

class VaultPanicApi {
  final MethodChannel _channel;
  const VaultPanicApi(this._channel);

  /// Falls back to [PanicTier.sessionPurge] / tile disabled on any
  /// failure -- the same defaults PanicSettings.kt itself falls back to
  /// before Settings has ever been visited, so a read failure here never
  /// *looks* more dangerous (or more configured) than what's actually
  /// stored on the native side.
  Future<PanicSettingsSnapshot> getPanicSettings() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        ChannelMethods.getPanicSettings,
      );
      return (
        configuredTier: PanicTier.fromLevel(
          result?['configuredTier'] as int?,
        ),
        quickTileEnabled: result?['quickTileEnabled'] as bool? ?? false,
      );
    } catch (e) {
      logSwallowed('getPanicSettings', e);
      return (configuredTier: PanicTier.sessionPurge, quickTileEnabled: false);
    }
  }

  Future<bool> setPanicTier(PanicTier tier) async {
    try {
      final success = await _channel.invokeMethod<bool>(
        ChannelMethods.setPanicTier,
        {'level': tier.level},
      );
      return success ?? false;
    } catch (e) {
      logSwallowed('setPanicTier', e);
      return false;
    }
  }

  /// The settings screen should only report the tile as actually usable
  /// once this returns true *and* the user has manually added it from the
  /// system Quick Settings editor -- this call alone cannot place the
  /// tile there (no non-system-app API can); it only arms
  /// PanicTileService.onClick to treat a tap as a real trigger once it is
  /// added.
  Future<bool> setQuickTileEnabled(bool enabled) async {
    try {
      final success = await _channel.invokeMethod<bool>(
        ChannelMethods.setQuickTileEnabled,
        {'enabled': enabled},
      );
      return success ?? false;
    } catch (e) {
      logSwallowed('setQuickTileEnabled', e);
      return false;
    }
  }

  /// Falls back to enforcement *on* and nothing paired -- PanicKitSettings.kt's
  /// own defaults -- so a failed read never makes an unpaired trigger
  /// app look accepted, and never makes pairing enforcement look
  /// disabled when it isn't.
  Future<PanicKitStatus> getPanicKitStatus() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        ChannelMethods.getPanicKitStatus,
      );
      return (
        responderEnabled: result?['responderEnabled'] as bool? ?? false,
        pairingEnforcementEnabled:
            result?['pairingEnforcementEnabled'] as bool? ?? true,
        trustedPackage: result?['trustedPackage'] as String?,
        hasTrustedCert: result?['hasTrustedCert'] as bool? ?? false,
      );
    } catch (e) {
      logSwallowed('getPanicKitStatus', e);
      return (
        responderEnabled: false,
        pairingEnforcementEnabled: true,
        trustedPackage: null,
        hasTrustedCert: false,
      );
    }
  }

  Future<bool> setPanicKitEnabled(bool enabled) async {
    try {
      final success = await _channel.invokeMethod<bool>(
        ChannelMethods.setPanicKitEnabled,
        {'enabled': enabled},
      );
      return success ?? false;
    } catch (e) {
      logSwallowed('setPanicKitEnabled', e);
      return false;
    }
  }

  /// Verifying the paired app's UID and certificate on every trigger
  /// (PanicKitTriggerReceiver.kt) is the only thing standing between "any
  /// app that knows the broadcast action" and "only the one app the user
  /// actually paired" -- turning this off is a real security trade-off
  /// (e.g. for a trigger app that re-signs itself on every build), not a
  /// convenience toggle, and Settings copy for it should say so.
  Future<bool> setPanicKitPairingEnforcement(bool enabled) async {
    try {
      final success = await _channel.invokeMethod<bool>(
        ChannelMethods.setPanicKitPairingEnforcement,
        {'enabled': enabled},
      );
      return success ?? false;
    } catch (e) {
      logSwallowed('setPanicKitPairingEnforcement', e);
      return false;
    }
  }

  Future<bool> unpairPanicKit() async {
    try {
      final success = await _channel.invokeMethod<bool>(
        ChannelMethods.unpairPanicKit,
      );
      return success ?? false;
    } catch (e) {
      logSwallowed('unpairPanicKit', e);
      return false;
    }
  }

  /// Runs [tier] (or, if omitted, whatever PanicSettings.kt has configured)
  /// to completion and reports what it actually did -- see
  /// PanicManager.execute's doc comment on the native side for the full
  /// threading/return contract. In particular: a [PanicTier.nuclearWipe]
  /// call does not return in the normal case at all, since the process
  /// dies partway through -- a caller triggering that tier from an
  /// in-app "wipe now" button should not expect this Future to resolve,
  /// only for the app to disappear out from under it.
  Future<PanicTriggerResult> triggerPanic({PanicTier? tier}) async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        ChannelMethods.triggerPanic,
        {'level': tier?.level},
      );
      return (
        success: result?['success'] as bool? ?? false,
        containersLocked: result?['containersLocked'] as int? ?? 0,
        keystoreAliasesPurged: result?['keystoreAliasesPurged'] as int? ?? 0,
        filesWiped: result?['filesWiped'] as int? ?? 0,
      );
    } catch (e) {
      logSwallowed('triggerPanic', e);
      return (
        success: false,
        containersLocked: 0,
        keystoreAliasesPurged: 0,
        filesWiped: 0,
      );
    }
  }
}
