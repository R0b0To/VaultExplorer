import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/features/tools/services/keyfile_passphrase_generator_service.dart';

part 'quick_password_generator_controller.g.dart';

class QuickPasswordGeneratorState {
  final String preset;
  final String generated;

  const QuickPasswordGeneratorState({this.preset = 'dice5', this.generated = ''});
}

@riverpod
class QuickPasswordGenerator extends _$QuickPasswordGenerator {
  @override
  QuickPasswordGeneratorState build() {
    const initial = QuickPasswordGeneratorState();
    Future.microtask(regenerate);
    return initial;
  }

  Future<void> regenerate() async {
    final preset = state.preset;
    String pwd = '';
    switch (preset) {
      case 'dice5':
        final res = await KeyfilePassphraseGeneratorService.generateDicewarePassphrase(
          wordCount: 5,
          separator: '-',
          casing: PasswordCasing.lowercase,
          includeNumber: true,
        );
        pwd = res.passphrase;
        break;
      case 'dice6':
        final res = await KeyfilePassphraseGeneratorService.generateDicewarePassphrase(
          wordCount: 6,
          separator: '-',
          casing: PasswordCasing.lowercase,
          includeNumber: true,
        );
        pwd = res.passphrase;
        break;
      case 'char24':
        pwd = KeyfilePassphraseGeneratorService.generateCustomPassword(
          length: 24,
          useUppercase: true,
          useLowercase: true,
          useNumbers: true,
          useSymbols: true,
        ).password;
        break;
      default:
        pwd = KeyfilePassphraseGeneratorService.generateCustomPassword(
          length: 32,
          useUppercase: true,
          useLowercase: true,
          useNumbers: true,
          useSymbols: true,
        ).password;
    }
    if (ref.mounted) {
      state = QuickPasswordGeneratorState(preset: preset, generated: pwd);
    }
  }

  void selectPreset(String key) {
    if (state.preset == key) return;
    state = QuickPasswordGeneratorState(preset: key, generated: state.generated);
    regenerate();
  }
}