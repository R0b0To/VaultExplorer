import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/api/vault_hash_api.dart';
import 'package:vaultexplorer/features/tools/services/keyfile_passphrase_generator_service.dart';

class _FakeHashApi extends VaultHashApi {
  const _FakeHashApi() : super(const MethodChannel('test'));

  @override
  Future<String> hashBytesSha256(Uint8List bytes) async {
    var acc = bytes.length;
    for (final b in bytes) {
      acc = (acc * 31 + b) & 0x7fffffff;
    }
    return acc.toRadixString(16).padLeft(64, '0');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('KeyfilePassphraseGeneratorService Tests', () {
    test('EFF wordlist asset is the real, unmodified 7,776-word list', () async {
      final wordlist = await KeyfilePassphraseGeneratorService.loadWordlist();
      expect(wordlist.length, equals(7776));
      expect(wordlist.toSet().length, equals(7776));
      for (final word in wordlist) {
        expect(word, equals(word.trim()));
        expect(word, isNotEmpty);
      }
    });

    test('generateDicewarePassphrase produces correct word count and entropy', () async {
      final res = await KeyfilePassphraseGeneratorService.generateDicewarePassphrase(
        wordCount: 6,
        separator: '-',
        casing: PasswordCasing.lowercase,
      );

      final words = res.passphrase.split('-');
      expect(words.length, equals(6));
      expect(res.entropyBits, greaterThanOrEqualTo(77.0));
    });

    test('generateCustomPassword adheres to length and character pool requirements', () {
      final res = KeyfilePassphraseGeneratorService.generateCustomPassword(
        length: 32,
        useUppercase: true,
        useLowercase: true,
        useNumbers: true,
        useSymbols: true,
        excludeAmbiguous: true,
      );

      expect(res.password.length, equals(32));
      expect(res.entropyBits, greaterThan(150.0));
      expect(res.password.contains('l'), isFalse);
      expect(res.password.contains('I'), isFalse);
      expect(res.password.contains('0'), isFalse);
      expect(res.password.contains('O'), isFalse);
    });

    test('generateBinaryKeyfile generates correct size and fingerprint shape', () async {
      final bytes = KeyfilePassphraseGeneratorService.generateBinaryKeyfile(256);
      expect(bytes.length, equals(256));
    });

    test('generateImageKeyfile creates a valid PNG file signature', () async {
      final pngBytes = await KeyfilePassphraseGeneratorService.generateImageKeyfile(64);
      expect(pngBytes.length, greaterThan(100));

      final pngHeader = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
      expect(pngBytes.sublist(0, 8), equals(pngHeader));
    });

    test('evaluatePasswordStrength returns proper classification categories', () {
      final weak = KeyfilePassphraseGeneratorService.evaluatePasswordStrength(30.0);
      expect(weak.level, equals(PasswordStrengthLevel.weak));

      final strong = KeyfilePassphraseGeneratorService.evaluatePasswordStrength(70.0);
      expect(strong.level, equals(PasswordStrengthLevel.strong));

      final unbreakable = KeyfilePassphraseGeneratorService.evaluatePasswordStrength(100.0);
      expect(unbreakable.level, equals(PasswordStrengthLevel.unbreakable));
    });
  });
}