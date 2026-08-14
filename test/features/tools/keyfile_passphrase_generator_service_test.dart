import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/features/tools/services/keyfile_passphrase_generator_service.dart';

/// Stands in for the real SHA-256 platform call (`MessageDigest` on the
/// Kotlin side -- see HashVerifierHandlers.kt) so these tests don't need
/// a real Android platform channel. Deliberately not a real SHA-256: this
/// file tests KeyfilePassphraseGeneratorService's own logic, not the
/// platform's digest implementation, so the fake only needs to be
/// deterministic and shaped like a real one (64 lowercase hex chars).
class _FakeHashVaultExplorerApi extends VaultExplorerApi {
  const _FakeHashVaultExplorerApi();

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

  setUp(() => vaultExplorerApi = const _FakeHashVaultExplorerApi());
  tearDown(() => vaultExplorerApi = const VaultExplorerApi());

  group('KeyfilePassphraseGeneratorService Tests', () {
    test('EFF wordlist asset is the real, unmodified 7,776-word list', () async {
      // Regression test: the wordlist used to be a ~1,000-line Dart
      // source literal that had drifted to 9,954 entries with 219
      // duplicates -- silently weakening the diceware entropy claims
      // shown to users. This asserts the bundled asset is exactly the
      // canonical EFF Large Wordlist shape: 7,776 unique entries.
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
      for (final word in words) {
        expect(word, equals(word.toLowerCase()));
      }
    });

    test('generateDicewarePassphrase respects Title Case and appends digits/symbols', () async {
      final res = await KeyfilePassphraseGeneratorService.generateDicewarePassphrase(
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

    test('generateBinaryKeyfile generates correct size and fingerprint shape', () async {
      final bytes = KeyfilePassphraseGeneratorService.generateBinaryKeyfile(256);
      expect(bytes.length, equals(256));

      final fp = await KeyfilePassphraseGeneratorService.calculateKeyfileFingerprint(bytes);
      expect(fp.length, equals(64));
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(fp), isTrue);
    });

    test('calculateKeyfileFingerprint is deterministic for the same bytes', () async {
      final bytes = KeyfilePassphraseGeneratorService.generateBinaryKeyfile(64);
      final fp1 = await KeyfilePassphraseGeneratorService.calculateKeyfileFingerprint(bytes);
      final fp2 = await KeyfilePassphraseGeneratorService.calculateKeyfileFingerprint(bytes);
      expect(fp1, equals(fp2));
    });

    test('generateImageKeyfile creates a valid PNG file with matching fingerprint shape', () async {
      final pngBytes = await KeyfilePassphraseGeneratorService.generateImageKeyfile(64);
      expect(pngBytes.length, greaterThan(100));

      // Standard PNG file signature: 89 50 4E 47 0D 0A 1A 0A
      final pngHeader = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
      expect(pngBytes.sublist(0, 8), equals(pngHeader));

      final fp = await KeyfilePassphraseGeneratorService.calculateKeyfileFingerprint(pngBytes);
      expect(fp.length, equals(64));
    });

    test('evaluatePasswordStrength returns proper classification categories', () {
      final weak = KeyfilePassphraseGeneratorService.evaluatePasswordStrength(30.0);
      expect(weak.level, equals(PasswordStrengthLevel.weak));
      expect(weak.crackTime, equals(PasswordCrackTimeEstimate.instant));

      final strong = KeyfilePassphraseGeneratorService.evaluatePasswordStrength(70.0);
      expect(strong.level, equals(PasswordStrengthLevel.strong));
      expect(strong.crackTime, equals(PasswordCrackTimeEstimate.centuries));

      final unbreakable = KeyfilePassphraseGeneratorService.evaluatePasswordStrength(100.0);
      expect(unbreakable.level, equals(PasswordStrengthLevel.unbreakable));
      expect(unbreakable.crackTime, equals(PasswordCrackTimeEstimate.millionsOfYears));
    });
  });
}