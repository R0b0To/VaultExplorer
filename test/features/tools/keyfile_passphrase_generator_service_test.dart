import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/tools/services/keyfile_passphrase_generator_service.dart';

void main() {
  group('KeyfilePassphraseGeneratorService Tests', () {
    test('generateDicewarePassphrase produces correct word count and entropy', () {
      final res = KeyfilePassphraseGeneratorService.generateDicewarePassphrase(
        wordCount: 6,
        separator: '-',
        casing: PasswordCasing.lowercase,
      );

      final words = res.passphrase.split('-');
      expect(words.length, equals(6));
      expect(res.entropyBits, greaterThanOrEqualTo(77.0));
      for (final word in words) {
        expect(word, equals(word.toLowerCase()));
      }
    });

    test('generateDicewarePassphrase respects Title Case and appends digits/symbols', () {
      final res = KeyfilePassphraseGeneratorService.generateDicewarePassphrase(
        wordCount: 4,
        separator: '_',
        casing: PasswordCasing.titleCase,
        includeNumber: true,
        includeSymbol: true,
      );

      final parts = res.passphrase.split('_');
      expect(parts.length, equals(6)); // 4 words + 1 digit + 1 symbol
      expect(res.entropyBits, greaterThan(50.0));
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

    test('generateBinaryKeyfile generates correct size and non-empty byte stream', () {
      final bytes = KeyfilePassphraseGeneratorService.generateBinaryKeyfile(256);
      expect(bytes.length, equals(256));

      final fp = KeyfilePassphraseGeneratorService.calculateKeyfileFingerprint(bytes);
      expect(fp.length, equals(64)); // SHA-256 hex string is 64 characters
    });

    test('generateImageKeyfile creates valid PNG file header and RGBA structure', () {
      final pngBytes = KeyfilePassphraseGeneratorService.generateImageKeyfile(64);
      expect(pngBytes.length, greaterThan(100));

      // Standard PNG file signature: 89 50 4E 47 0D 0A 1A 0A
      final pngHeader = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
      expect(pngBytes.sublist(0, 8), equals(pngHeader));

      final fp = KeyfilePassphraseGeneratorService.calculateKeyfileFingerprint(pngBytes);
      expect(fp.length, equals(64));
    });

    test('evaluatePasswordStrength returns proper classification categories', () {
      final weak = KeyfilePassphraseGeneratorService.evaluatePasswordStrength(30.0);
      expect(weak.label, equals('Weak'));

      final strong = KeyfilePassphraseGeneratorService.evaluatePasswordStrength(70.0);
      expect(strong.label, equals('Strong'));

      final unbreakable = KeyfilePassphraseGeneratorService.evaluatePasswordStrength(100.0);
      expect(unbreakable.label, equals('Unbreakable'));
    });
  });
}
