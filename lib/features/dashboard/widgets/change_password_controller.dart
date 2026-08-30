// ChangePasswordScreen was a plain StatefulWidget holding domain state
// (old/new keyfile lists + picking flags, processing/error) directly as
// State fields. The five TextEditingControllers and the three obscure-text
// toggles stay local in the widget -- genuinely ephemeral UI state, same
// reasoning as every other converted screen with password fields.
//
// Family-keyed by (uri, containerFormat, initialCipherId, initialHashId):
// a fresh screen instance is pushed per container being reconfigured, so
// this scopes cleanly to "this screen's session".
import 'package:flutter/services.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/api/vault_engine_types.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/data/models/container_format.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

part 'change_password_controller.g.dart';

class ChangePasswordState {
  final List<KeyfileRef> oldKeyfiles;
  final bool pickingOldKeyfiles;
  final List<KeyfileRef> newKeyfiles;
  final bool pickingNewKeyfiles;
  final bool isProcessing;
  final String? errorMsg;

  /// Bumped on a successful password change; the widget's `ref.listen`
  /// pops the screen on any increase, mirroring the `navigateTick` pattern
  /// used by LockGateScreen.
  final int successTick;

  const ChangePasswordState({
    this.oldKeyfiles = const [],
    this.pickingOldKeyfiles = false,
    this.newKeyfiles = const [],
    this.pickingNewKeyfiles = false,
    this.isProcessing = false,
    this.errorMsg,
    this.successTick = 0,
  });
}

@riverpod
class ChangePassword extends _$ChangePassword {
  @override
  ChangePasswordState build(
    String uri,
    String containerFormat,
    int initialCipherId,
    int initialHashId,
  ) => const ChangePasswordState();

  bool get _isCryptomator => ContainerFormat.isCryptomatorWire(containerFormat);
  bool get _isGocryptfs => ContainerFormat.isGocryptfsWire(containerFormat);
  bool get _isCryfs => ContainerFormat.isCryfsWire(containerFormat);
  bool get _isFolderVault => _isCryptomator || _isGocryptfs || _isCryfs;
  bool get _isLuks => ContainerFormat.isLuksWire(containerFormat);

  ChangePasswordState _copy({
    List<KeyfileRef>? oldKeyfiles,
    bool? pickingOldKeyfiles,
    List<KeyfileRef>? newKeyfiles,
    bool? pickingNewKeyfiles,
    bool? isProcessing,
    String? errorMsg,
    bool clearError = false,
    int? successTick,
  }) => ChangePasswordState(
    oldKeyfiles: oldKeyfiles ?? state.oldKeyfiles,
    pickingOldKeyfiles: pickingOldKeyfiles ?? state.pickingOldKeyfiles,
    newKeyfiles: newKeyfiles ?? state.newKeyfiles,
    pickingNewKeyfiles: pickingNewKeyfiles ?? state.pickingNewKeyfiles,
    isProcessing: isProcessing ?? state.isProcessing,
    errorMsg: clearError ? null : (errorMsg ?? state.errorMsg),
    successTick: successTick ?? state.successTick,
  );

  Future<void> pickOldKeyfiles(AppLocalizations l10n) async {
    state = _copy(pickingOldKeyfiles: true);
    try {
      final picked = await ref.read(vaultLifecycleApiProvider).pickKeyfiles();
      if (picked.isNotEmpty) {
        final next = [...state.oldKeyfiles];
        for (final k in picked) {
          if (!next.any((existing) => existing.uri == k.uri)) next.add(k);
        }
        state = _copy(oldKeyfiles: next);
      }
    } on PlatformException catch (e) {
      if (ref.mounted) {
        state = _copy(errorMsg: e.message ?? l10n.couldNotPickKeyfiles);
      }
    } finally {
      if (ref.mounted) state = _copy(pickingOldKeyfiles: false);
    }
  }

  void removeOldKeyfile(KeyfileRef keyfile) {
    state = _copy(
      oldKeyfiles: state.oldKeyfiles.where((k) => k != keyfile).toList(),
    );
  }

  Future<void> pickNewKeyfiles(AppLocalizations l10n) async {
    state = _copy(pickingNewKeyfiles: true);
    try {
      final picked = await ref.read(vaultLifecycleApiProvider).pickKeyfiles();
      if (picked.isNotEmpty) {
        final next = [...state.newKeyfiles];
        for (final k in picked) {
          if (!next.any((existing) => existing.uri == k.uri)) next.add(k);
        }
        state = _copy(newKeyfiles: next);
      }
    } on PlatformException catch (e) {
      if (ref.mounted) {
        state = _copy(errorMsg: e.message ?? l10n.couldNotPickKeyfiles);
      }
    } finally {
      if (ref.mounted) state = _copy(pickingNewKeyfiles: false);
    }
  }

  void removeNewKeyfile(KeyfileRef keyfile) {
    state = _copy(
      newKeyfiles: state.newKeyfiles.where((k) => k != keyfile).toList(),
    );
  }

  /// Returns nothing directly -- success/failure is reflected in `state`
  /// (successTick bump vs. errorMsg), matching the ref.listen-driven
  /// navigation pattern used elsewhere.
  Future<void> submit({
    required String oldPassword,
    required String newPassword,
    required String confirmPassword,
    required String oldPim,
    required String newPim,
    required AppLocalizations l10n,
  }) async {
    if (newPassword.isEmpty && state.newKeyfiles.isEmpty) {
      state = _copy(errorMsg: l10n.newPasswordOrKeyfilesRequired);
      return;
    }
    if (newPassword != confirmPassword) {
      state = _copy(errorMsg: l10n.newPasswordsDoNotMatch);
      return;
    }
    state = _copy(isProcessing: true, clearError: true);
    final api = ref.read(vaultLifecycleApiProvider);
    try {
      bool success;
      if (_isCryptomator) {
        success = await api.changeCryptomatorVaultPassword(uri, oldPassword, newPassword);
      } else if (_isGocryptfs) {
        success = await api.changeGocryptfsVaultPassword(uri, oldPassword, newPassword);
      } else if (_isCryfs) {
        success = await api.changeCryfsVaultPassword(uri, oldPassword, newPassword);
      } else if (_isLuks) {
        success = await api.changeLuksContainerPassword(
          uri: uri,
          oldPassword: oldPassword,
          newPassword: newPassword,
          oldKeyfilePaths: state.oldKeyfiles.map((k) => k.uri).toList(),
          newKeyfilePaths: state.newKeyfiles.map((k) => k.uri).toList(),
        );
      } else {
        success = await api.changeContainerPassword(
          uri: uri,
          oldPassword: oldPassword,
          newPassword: newPassword,
          oldPim: int.tryParse(oldPim) ?? 0,
          newPim: int.tryParse(newPim) ?? 0,
          cipherId: initialCipherId,
          hashId: initialHashId,
          oldKeyfilePaths: state.oldKeyfiles.map((k) => k.uri).toList(),
          newKeyfilePaths: state.newKeyfiles.map((k) => k.uri).toList(),
        );
      }
      if (!ref.mounted) return;
      if (success) {
        state = _copy(isProcessing: false, successTick: state.successTick + 1);
      } else {
        state = _copy(isProcessing: false, errorMsg: l10n.failedToChangePasswordMessage);
      }
    } on PlatformException catch (e) {
      // Folder vaults report specific failures (wrong password, unreadable
      // config, ...) as PlatformExceptions with a pre-formatted message --
      // see changeCryptomatorVaultPassword's doc comment.
      if (ref.mounted) {
        state = _copy(
          isProcessing: false,
          errorMsg: e.message ?? l10n.failedToChangePasswordMessage,
        );
      }
    }
  }
}
