// _PatternVerifySheet/_PinVerifySheet (in container_config_dialogs.dart,
// a `part of container_config_sheet.dart` file) were plain StatefulWidgets
// holding a single-attempt verify flow's error/reset state directly. Mirrors
// PatternSetupController/PinSetupController's shape, but simpler -- this is
// a one-shot "check against an already-known hash" flow, not a two-step
// draw/confirm flow, so there's no `step` field.
//
// Family-keyed by `storedHash`: a fresh dialog instance is shown per
// verification attempt, and the hash being checked against is the only
// thing that identifies "which verification this is."
//
// Lives in its own file (not inside container_config_dialogs.dart itself)
// because that file is a `part of` container_config_sheet.dart -- a part
// file can't also declare its own `part 'xxx.g.dart';` for codegen.
// container_config_sheet.dart imports this file so both it and its part
// file can use the resulting providers.
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/features/lock/widgets/pattern_lock_view.dart';
import 'package:vaultexplorer/features/lock/widgets/pin_lock_view.dart';

part 'pattern_pin_verify_controller.g.dart';

class VerifyState {
  final String? error;
  final bool showError;
  final int resetKey;
  final bool verified;

  const VerifyState({
    this.error,
    this.showError = false,
    this.resetKey = 0,
    this.verified = false,
  });
}

@riverpod
class PatternVerify extends _$PatternVerify {
  @override
  VerifyState build(String storedHash) => const VerifyState();

  Future<void> submitPattern(List<int> pattern, {required String incorrectMessage}) async {
    final ok = await verifyPattern(pattern, storedHash);
    if (!ref.mounted) return;
    if (ok) {
      state = VerifyState(resetKey: state.resetKey, verified: true);
      return;
    }
    state = VerifyState(error: incorrectMessage, showError: true, resetKey: state.resetKey);
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (ref.mounted) {
      state = VerifyState(resetKey: state.resetKey + 1);
    }
  }
}

@riverpod
class PinVerify extends _$PinVerify {
  @override
  VerifyState build(String storedHash) => const VerifyState();

  Future<void> submitPin(String pin, {required String incorrectMessage}) async {
    final ok = await verifyPin(pin, storedHash);
    if (!ref.mounted) return;
    if (ok) {
      state = VerifyState(resetKey: state.resetKey, verified: true);
      return;
    }
    state = VerifyState(error: incorrectMessage, showError: true, resetKey: state.resetKey);
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (ref.mounted) {
      state = VerifyState(resetKey: state.resetKey + 1);
    }
  }
}
