// State for MigrateCryptomatorVaultScreen: the one-way Cryptomator format 7 -> 8 upgrade.
//
// Family-keyed by the vault's uri: a fresh screen is pushed per vault, so this scopes to "this screen's
// session". The password itself stays in the widget's TextEditingController (ephemeral UI state, same
// reasoning as ChangePasswordScreen); the state only knows whether one has been typed, so the Upgrade
// button can enable itself without the secret ever living in provider state.
import 'package:flutter/services.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

part 'migrate_cryptomator_vault_controller.g.dart';

class MigrateCryptomatorVaultState {
  final bool passwordFilled;

  /// The "I understand this can't be undone" checkbox.
  final bool confirmed;
  final bool isProcessing;
  final String? errorMsg;

  /// Bumped on a successful upgrade; the widget's `ref.listen` pops the screen on any increase (same
  /// pattern as ChangePasswordState.successTick).
  final int successTick;

  const MigrateCryptomatorVaultState({
    this.passwordFilled = false,
    this.confirmed = false,
    this.isProcessing = false,
    this.errorMsg,
    this.successTick = 0,
  });

  /// The upgrade cannot be undone, so it needs both a password and the explicit confirmation.
  bool get canSubmit => passwordFilled && confirmed && !isProcessing;
}

@riverpod
class MigrateCryptomatorVault extends _$MigrateCryptomatorVault {
  @override
  MigrateCryptomatorVaultState build(String uri) =>
      const MigrateCryptomatorVaultState();

  MigrateCryptomatorVaultState _copy({
    bool? passwordFilled,
    bool? confirmed,
    bool? isProcessing,
    String? errorMsg,
    bool clearError = false,
    int? successTick,
  }) => MigrateCryptomatorVaultState(
    passwordFilled: passwordFilled ?? state.passwordFilled,
    confirmed: confirmed ?? state.confirmed,
    isProcessing: isProcessing ?? state.isProcessing,
    errorMsg: clearError ? null : (errorMsg ?? state.errorMsg),
    successTick: successTick ?? state.successTick,
  );

  void setPasswordFilled(bool filled) {
    if (filled == state.passwordFilled) return;
    state = _copy(passwordFilled: filled);
  }

  void setConfirmed(bool confirmed) => state = _copy(confirmed: confirmed);

  /// Success or failure is reflected in `state` (successTick bump vs. errorMsg). Does nothing unless
  /// [MigrateCryptomatorVaultState.canSubmit]. Never unlocks the vault, caches the password or touches the
  /// ContainerRecord: the masterkey is unchanged, so a saved or automation password stays valid.
  Future<void> submit({
    required String password,
    required AppLocalizations l10n,
  }) async {
    if (!state.canSubmit) return;
    state = _copy(isProcessing: true, clearError: true);
    try {
      final ok = await ref
          .read(vaultLifecycleApiProvider)
          .migrateCryptomatorVault(uri, password);
      if (!ref.mounted) return;
      state = ok
          ? _copy(isProcessing: false, successTick: state.successTick + 1)
          : _copy(
              isProcessing: false,
              errorMsg: l10n.cryptomatorUpgradeFailedMessage,
            );
    } on PlatformException catch (e) {
      if (!ref.mounted) return;
      state = _copy(isProcessing: false, errorMsg: _messageFor(e, l10n));
    }
  }

  /// AUTH_FAIL and VAULT_UNLOCKED have fixed, localised messages; INVALID_VAULT carries the engine's own
  /// explanation (not a format 7 vault, key file not writable, ...).
  static String _messageFor(PlatformException e, AppLocalizations l10n) {
    switch (e.code) {
      case 'AUTH_FAIL':
        return l10n.incorrectPasswordError;
      case 'VAULT_UNLOCKED':
        return l10n.cryptomatorUpgradeUnlockedError;
      default:
        final message = e.message;
        return (message == null || message.isEmpty)
            ? l10n.cryptomatorUpgradeFailedMessage
            : message;
    }
  }
}
