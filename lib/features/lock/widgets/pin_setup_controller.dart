// PinSetupSheet was a plain StatefulWidget holding the enter/confirm step,
// first-entered PIN, and error/reset state directly as State fields.
// Mirrors PatternSetupController step-for-step -- see its header comment
// for the `completedHash`/`ref.listen` pop pattern.
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/features/lock/widgets/pin_lock_view.dart';

part 'pin_setup_controller.g.dart';

enum PinSetupStep { enter, confirm }

class PinSetupState {
  final PinSetupStep step;
  final String? firstPin;
  final String? error;
  final bool showError;
  final int resetKey;
  final String? completedHash;

  const PinSetupState({
    this.step = PinSetupStep.enter,
    this.firstPin,
    this.error,
    this.showError = false,
    this.resetKey = 0,
    this.completedHash,
  });
}

@riverpod
class PinSetup extends _$PinSetup {
  @override
  PinSetupState build() => const PinSetupState();

  PinSetupState _copy({
    PinSetupStep? step,
    String? firstPin,
    bool clearFirstPin = false,
    String? error,
    bool clearError = false,
    bool? showError,
    int? resetKey,
  }) => PinSetupState(
    step: step ?? state.step,
    firstPin: clearFirstPin ? null : (firstPin ?? state.firstPin),
    error: clearError ? null : (error ?? state.error),
    showError: showError ?? state.showError,
    resetKey: resetKey ?? state.resetKey,
    completedHash: state.completedHash,
  );

  Future<void> submitPin(String pin, {required String mismatchMessage}) async {
    switch (state.step) {
      case PinSetupStep.enter:
        state = _copy(
          firstPin: pin,
          step: PinSetupStep.confirm,
          clearError: true,
          showError: false,
          resetKey: state.resetKey + 1,
        );
        break;

      case PinSetupStep.confirm:
        if (state.firstPin == pin) {
          final cryptoApi = ref.read(vaultCryptoApiProvider);
          final hash = await hashPin(cryptoApi, pin);
          if (ref.mounted) {
            state = PinSetupState(
              step: state.step,
              firstPin: state.firstPin,
              resetKey: state.resetKey,
              completedHash: hash,
            );
          }
        } else {
          state = _copy(error: mismatchMessage, showError: true);
          await Future<void>.delayed(const Duration(milliseconds: 800));
          if (ref.mounted) {
            state = _copy(
              step: PinSetupStep.enter,
              clearFirstPin: true,
              showError: false,
              clearError: true,
              resetKey: state.resetKey + 1,
            );
          }
        }
        break;
    }
  }
}
