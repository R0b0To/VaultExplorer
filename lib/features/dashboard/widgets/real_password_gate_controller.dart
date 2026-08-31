// _RealPasswordGateDialog (in container_config_dialogs.dart, a `part of
// container_config_sheet.dart` file) already resolved its platform
// dependencies via ref.read(vaultLifecycleApiProvider)/vaultEngineEventsProvider
// directly -- what's extracted here is the actual async verify orchestration
// (multi-format unlock branches, keyfile picking, unlock-started tracking
// for cancellation) into a proper controller, matching how ChangePasswordScreen
// and AutomationSettingsScreen (similarly self-contained single-modal
// screens) were treated, for consistency and Phase 6 testability
// (overrideWithValue on vaultLifecycleApiProvider to test this without a
// real container).
//
// _PatternVerifySheet/_PinVerifySheet/_DisplayNameDialog in the same file
// are NOT touched -- confirmed (again, on a fresh read) to be genuinely
// trivial ephemeral UI state (error-flash timing, a bare TextEditingController
// wrapper), nothing domain/async/shared to extract.
import 'package:flutter/services.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/api/vault_engine_events.dart';
import 'package:vaultexplorer/core/api/vault_engine_types.dart';
import 'package:vaultexplorer/core/api/vault_lifecycle_api.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/utils/validation_utils.dart' show clampPim;
import 'package:vaultexplorer/data/models/container_format.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

part 'real_password_gate_controller.g.dart';

typedef RealPasswordGateResult = ({
  String password,
  List<KeyfileRef> keyfiles,
  int cipherId,
  int hashId,
});

class RealPasswordGateState {
  final bool loading;
  final String? error;
  final int? activeVolId;
  final List<KeyfileRef> keyfiles;
  final bool pickingKeyfiles;

  const RealPasswordGateState({
    this.loading = false,
    this.error,
    this.activeVolId,
    this.keyfiles = const [],
    this.pickingKeyfiles = false,
  });
}

@riverpod
class RealPasswordGate extends _$RealPasswordGate {
  // Captured once in build() -- Riverpod disallows calling ref.read() from
  // inside a ref.onDispose() callback body ("Cannot use Ref or modify other
  // providers inside life-cycles/selectors"; both providers below are
  // keepAlive singleton-style wrappers, so caching the instance here is
  // behaviorally identical to reading it fresh every time).
  late final VaultEngineEvents _events;
  late final VaultLifecycleApi _lifecycle;

  @override
  RealPasswordGateState build(List<Map<String, String>> initialKeyfiles) {
    _events = ref.read(vaultEngineEventsProvider);
    _lifecycle = ref.read(vaultLifecycleApiProvider);

    final initial = initialKeyfiles
        .map((k) => (uri: k['uri']!, displayName: k['name']!))
        .toList();

    void onUnlockStarted(int volId) {
      state = _copy(activeVolId: volId);
    }

    _events.addUnlockStartedListener(onUnlockStarted);
    ref.onDispose(() {
      _events.removeUnlockStartedListener(onUnlockStarted);
      // Backup cancel path for dismissals that don't go through the
      // dialog's own Cancel button (back gesture, barrier tap).
      if (state.loading && state.activeVolId != null) {
        _lifecycle.cancelUnlock(state.activeVolId!);
      }
    });

    return RealPasswordGateState(keyfiles: initial);
  }

  RealPasswordGateState _copy({
    bool? loading,
    String? error,
    bool clearError = false,
    int? activeVolId,
    List<KeyfileRef>? keyfiles,
    bool? pickingKeyfiles,
  }) => RealPasswordGateState(
    loading: loading ?? state.loading,
    error: clearError ? null : (error ?? state.error),
    activeVolId: activeVolId ?? state.activeVolId,
    keyfiles: keyfiles ?? state.keyfiles,
    pickingKeyfiles: pickingKeyfiles ?? state.pickingKeyfiles,
  );

  /// Explicit, immediate cancel for the dialog's own Cancel button --
  /// don't rely solely on the [ref.onDispose] backup above, since
  /// autoDispose's teardown isn't necessarily as immediate as the user
  /// tapping Cancel.
  void cancelActiveUnlock() {
    final volId = state.activeVolId;
    if (state.loading && volId != null) {
      ref.read(vaultLifecycleApiProvider).cancelUnlock(volId);
    }
  }

  Future<void> pickKeyfiles() async {
    state = _copy(pickingKeyfiles: true);
    try {
      final picked = await ref.read(vaultLifecycleApiProvider).pickKeyfiles();
      if (!ref.mounted) return;
      if (picked.isNotEmpty) {
        final existingUris = state.keyfiles.map((k) => k.uri).toSet();
        final merged = [...state.keyfiles];
        for (final k in picked) {
          if (existingUris.add(k.uri)) merged.add(k);
        }
        state = _copy(keyfiles: merged);
      }
    } finally {
      if (ref.mounted) state = _copy(pickingKeyfiles: false);
    }
  }

  void removeKeyfile(KeyfileRef k) {
    state = _copy(keyfiles: state.keyfiles.where((e) => e != k).toList());
  }

  /// Returns the verified credentials on success (widget pops the dialog
  /// with this), or null on any failure/validation-rejection (widget stays
  /// open, `state.error` has the message to show).
  Future<RealPasswordGateResult?> verify({
    required String uri,
    required String containerFormat,
    required int cipherId,
    required int hashId,
    required bool documentProvider,
    required bool cacheDerivedKey,
    required String password,
    required String pimText,
    required AppLocalizations l10n,
    bool isCurrentlyMounted = false,
  }) async {
    if (password.isEmpty && state.keyfiles.isEmpty) {
      state = _copy(error: l10n.passwordOrKeyfilesRequired);
      return null;
    }
    state = _copy(loading: true, clearError: true);

    final lifecycle = ref.read(vaultLifecycleApiProvider);
    final isUsb = uri.startsWith('usb:');
    final usbDeviceName = isUsb ? uri.substring(4) : '';
    final isCryptomator = ContainerFormat.isCryptomatorWire(containerFormat);
    final isGocryptfs = ContainerFormat.isGocryptfsWire(containerFormat);
    final isCryfs = ContainerFormat.isCryfsWire(containerFormat);

    if (isCryptomator || isGocryptfs || isCryfs) {
      try {
        final result = isCryptomator
            ? await lifecycle.unlockCryptomatorVault(
                uri,
                password,
                displayName: '',
                documentProvider: documentProvider,
              )
            : isGocryptfs
            ? await lifecycle.unlockGocryptfsVault(
                uri,
                password,
                displayName: '',
                documentProvider: documentProvider,
              )
            : await lifecycle.unlockCryfsVault(
                uri,
                password,
                displayName: '',
                documentProvider: documentProvider,
              );
        if (result == null) {
          if (ref.mounted) {
            state = _copy(loading: false, error: l10n.incorrectPasswordError);
          }
          return null;
        }
        // Only lock if this was a temporary unlock test on a closed vault
        if (!isCurrentlyMounted) {
          await lifecycle.lockContainer(uri);
        }
        return (
          password: password,
          keyfiles: List<KeyfileRef>.from(state.keyfiles),
          cipherId: 255,
          hashId: 255,
        );
      } catch (e) {
        final isCancelled = e is PlatformException && e.code == 'CANCELLED';
        if (ref.mounted && !isCancelled) {
          state = _copy(loading: false, error: l10n.verificationFailedError);
        }
        return null;
      } finally {
        if (ref.mounted) state = _copy(loading: false);
      }
    }

    try {
      final pim = clampPim(pimText.isEmpty ? 0 : int.tryParse(pimText) ?? 0);
      final keyfilePaths = state.keyfiles.map((k) => k.uri).toList();
      final result = isUsb
          ? await lifecycle.unlockUsbContainer(
              usbDeviceName,
              password,
              pim,
              displayName: '',
              documentProvider: documentProvider,
              cipherId: cipherId,
              hashId: hashId,
              preservedKey: null,
              cacheDerivedKey: cacheDerivedKey,
              keyfilePaths: keyfilePaths,
            )
          : await lifecycle.unlockContainer(
              uri,
              password,
              pim,
              displayName: '',
              documentProvider: documentProvider,
              cipherId: cipherId,
              hashId: hashId,
              preservedKey: null,
              cacheDerivedKey: cacheDerivedKey,
              keyfilePaths: keyfilePaths,
            );
      if (result == null) {
        if (ref.mounted) {
          state = _copy(loading: false, error: l10n.incorrectCredentialsError);
        }
        return null;
      }
      // Only lock if this was a temporary unlock test on a closed vault
      if (!isCurrentlyMounted) {
        await lifecycle.lockContainer(isUsb ? usbDeviceName : uri);
      }
      return (
        password: password,
        keyfiles: List<KeyfileRef>.from(state.keyfiles),
        cipherId: result.matchedCipherId,
        hashId: result.matchedHashId,
      );
    } catch (e) {
      final isCancelled = e is PlatformException && e.code == 'CANCELLED';
      if (ref.mounted && !isCancelled) {
        state = _copy(loading: false, error: l10n.verificationFailedError);
      }
      return null;
    } finally {
      if (ref.mounted) state = _copy(loading: false);
    }
  }
}