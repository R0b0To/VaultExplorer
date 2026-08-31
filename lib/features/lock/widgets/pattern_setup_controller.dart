// PatternSetupSheet was a plain StatefulWidget holding the draw/confirm
// step, first-drawn pattern, and error/reset state directly as State
// fields. No family key needed -- only one instance of this sheet is ever
// open at a time (it's a modal).
//
// The Notifier can't call Navigator.pop itself (no BuildContext), so
// `completedHash` is bumped from null -> non-null when the confirmed
// pattern's hash is ready; the widget's `ref.listen` reacts and pops,
// mirroring the `navigateTick`/`loadedText` patterns used elsewhere.
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/features/lock/widgets/pattern_lock_view.dart';

part 'pattern_setup_controller.g.dart';

enum PatternSetupStep { draw, confirm }

class PatternSetupState {
  final PatternSetupStep step;
  final List<int>? firstPattern;
  final String? error;
  final bool showError;
  final int resetKey;
  final String? completedHash;

  const PatternSetupState({
    this.step = PatternSetupStep.draw,
    this.firstPattern,
    this.error,
    this.showError = false,
    this.resetKey = 0,
    this.completedHash,
  });
}

@riverpod
class PatternSetup extends _$PatternSetup {
  @override
  PatternSetupState build() => const PatternSetupState();

  PatternSetupState _copy({
    PatternSetupStep? step,
    List<int>? firstPattern,
    bool clearFirstPattern = false,
    String? error,
    bool clearError = false,
    bool? showError,
    int? resetKey,
  }) => PatternSetupState(
    step: step ?? state.step,
    firstPattern: clearFirstPattern
        ? null
        : (firstPattern ?? state.firstPattern),
    error: clearError ? null : (error ?? state.error),
    showError: showError ?? state.showError,
    resetKey: resetKey ?? state.resetKey,
    completedHash: state.completedHash,
  );

  /// Requires at least 4 connected dots, same as the original -- too short
  /// a pattern shows a transient error and resets rather than advancing.
  Future<void> submitPattern(
    List<int> pattern, {
    required String tooShortMessage,
    required String mismatchMessage,
  }) async {
    if (pattern.length < 4) {
      state = _copy(error: tooShortMessage, showError: true);
      await Future<void>.delayed(const Duration(milliseconds: 800));
      if (ref.mounted) {
        state = _copy(showError: false, resetKey: state.resetKey + 1);
      }
      return;
    }

    switch (state.step) {
      case PatternSetupStep.draw:
        state = _copy(
          firstPattern: pattern,
          step: PatternSetupStep.confirm,
          clearError: true,
          showError: false,
          resetKey: state.resetKey + 1,
        );
        break;

      case PatternSetupStep.confirm:
        if (listEquals(state.firstPattern, pattern)) {
          final cryptoApi = ref.read(vaultCryptoApiProvider);
          final hash = await hashPattern(cryptoApi, pattern);
          if (ref.mounted) {
            state = PatternSetupState(
              step: state.step,
              firstPattern: state.firstPattern,
              resetKey: state.resetKey,
              completedHash: hash,
            );
          }
        } else {
          state = _copy(error: mismatchMessage, showError: true);
          await Future<void>.delayed(const Duration(milliseconds: 800));
          if (ref.mounted) {
            state = _copy(
              step: PatternSetupStep.draw,
              clearFirstPattern: true,
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
