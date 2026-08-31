import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/services.dart' show rootBundle;
import 'package:vaultexplorer/core/api/vault_hash_api.dart';

enum PasswordCasing { lowercase, titleCase, uppercase }

/// Qualitative password/passphrase strength bucket -- see
/// [KeyfilePassphraseGeneratorService.evaluatePasswordStrength]. Callers
/// map this to a localized string via `context.l10n`, not a display
/// string baked into the service.
enum PasswordStrengthLevel { weak, good, strong, unbreakable }

/// Very rough, order-of-magnitude brute-force crack-time estimate
/// paired with a [PasswordStrengthLevel]. Callers map this to a
/// localized string via `context.l10n`, not a display string baked
/// into the service.
enum PasswordCrackTimeEstimate { instant, shortTerm, centuries, millionsOfYears }

enum KeyfileSizePreset {
  bytes64(64),
  bytes256(256),
  bytes2048(2048),
  bytes64kb(64 * 1024),
  bytes1mb(1024 * 1024);

  final int bytes;
  const KeyfileSizePreset(this.bytes);
}

enum ImageKeyfileResolution {
  res64(64),
  res256(256),
  res512(512);

  final int dimension;
  const ImageKeyfileResolution(this.dimension);
}

/// Service providing cryptographically secure passphrase and keyfile generation.
class KeyfilePassphraseGeneratorService {
  static final Random _secureRandom = Random.secure();

  // ── EFF 7,776 Large Wordlist ────────────────────────────────────────────────
  static List<String>? _cachedWordlist;

  /// Loads (and caches) the EFF Large Wordlist from its bundled asset
  /// (assets/data/eff_large_wordlist.txt) instead of a ~1,000-line Dart
  /// source literal. Also the seam
  /// [keyfile_passphrase_generator_service_test.dart]'s integrity test
  /// uses to verify the bundled list is still the real, unmodified
  /// 7,776-word EFF list (exactly that many unique entries) rather than
  /// silently drifting, as the previous embedded copy had (it had grown
  /// to 9,954 entries with 219 duplicates before this change).
  static Future<List<String>> loadWordlist() async {
    final cached = _cachedWordlist;
    if (cached != null) return cached;
    final raw = await rootBundle.loadString('assets/data/eff_large_wordlist.txt');
    final words = raw.split('\n').where((w) => w.trim().isNotEmpty).toList(growable: false);
    _cachedWordlist = words;
    return words;
  }

  // ── 1. Diceware Passphrase Generation ──────────────────────────────────────

  /// Generates an EFF Diceware passphrase.
  static Future<({String passphrase, double entropyBits})> generateDicewarePassphrase({
    int wordCount = 5,
    String separator = '-',
    PasswordCasing casing = PasswordCasing.lowercase,
    bool includeNumber = false,
    bool includeSymbol = false,
  }) async {
    final wordlist = await loadWordlist();
    final count = wordCount.clamp(3, 12);
    final chosenWords = <String>[];

    for (int i = 0; i < count; i++) {
      final index = _secureRandom.nextInt(wordlist.length);
      var word = wordlist[index];
      switch (casing) {
        case PasswordCasing.lowercase:
          word = word.toLowerCase();
          break;
        case PasswordCasing.titleCase:
          word = word.isEmpty ? word : '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}';
          break;
        case PasswordCasing.uppercase:
          word = word.toUpperCase();
          break;
      }
      chosenWords.add(word);
    }

    var result = chosenWords.join(separator);

    double extraEntropy = 0.0;
    if (includeNumber) {
      final digit = _secureRandom.nextInt(10);
      result += '$separator$digit';
      extraEntropy += 3.32; // log2(10)
    }

    if (includeSymbol) {
      const symbols = '!@#\$%^&*';
      final sym = symbols[_secureRandom.nextInt(symbols.length)];
      result += '$separator$sym';
      extraEntropy += 3.0; // log2(8)
    }

    // 12.924 bits per word from 7,776-word dictionary
    final entropyBits = (count * 12.924) + extraEntropy;

    return (passphrase: result, entropyBits: entropyBits);
  }

  // ── 2. Custom Character Password Generation ─────────────────────────────────

  /// Generates a random character password based on toggled character sets.
  static ({String password, double entropyBits}) generateCustomPassword({
    int length = 24,
    bool useUppercase = true,
    bool useLowercase = true,
    bool useNumbers = true,
    bool useSymbols = true,
    bool excludeAmbiguous = false,
  }) {
    final len = length.clamp(8, 128);

    String upper = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    String lower = 'abcdefghijklmnopqrstuvwxyz';
    String numbers = '0123456789';
    String symbols = '!@#\$%^&*()_+-=[]{}|;:,.<>?';

    if (excludeAmbiguous) {
      upper = upper.replaceAll(RegExp(r'[I O]'), '');
      lower = lower.replaceAll(RegExp(r'[l o]'), '');
      numbers = numbers.replaceAll(RegExp(r'[0 1]'), '');
    }

    String pool = '';
    final requiredChars = <String>[];

    if (useUppercase && upper.isNotEmpty) {
      pool += upper;
      requiredChars.add(upper[_secureRandom.nextInt(upper.length)]);
    }
    if (useLowercase && lower.isNotEmpty) {
      pool += lower;
      requiredChars.add(lower[_secureRandom.nextInt(lower.length)]);
    }
    if (useNumbers && numbers.isNotEmpty) {
      pool += numbers;
      requiredChars.add(numbers[_secureRandom.nextInt(numbers.length)]);
    }
    if (useSymbols && symbols.isNotEmpty) {
      pool += symbols;
      requiredChars.add(symbols[_secureRandom.nextInt(symbols.length)]);
    }

    if (pool.isEmpty) {
      pool = lower;
      requiredChars.add(lower[_secureRandom.nextInt(lower.length)]);
    }

    final passwordChars = <String>[...requiredChars];

    while (passwordChars.length < len) {
      final char = pool[_secureRandom.nextInt(pool.length)];
      passwordChars.add(char);
    }

    // Shuffle password using secure random
    for (int i = passwordChars.length - 1; i > 0; i--) {
      final j = _secureRandom.nextInt(i + 1);
      final temp = passwordChars[i];
      passwordChars[i] = passwordChars[j];
      passwordChars[j] = temp;
    }

    final password = passwordChars.join('');
    final entropyBits = len * (log(pool.length) / log(2));

    return (password: password, entropyBits: entropyBits);
  }

  // ── 3. Keyfile Generation ──────────────────────────────────────────────────

  /// Generates a binary keyfile filled with cryptographically secure random bytes.
  static Uint8List generateBinaryKeyfile(int sizeBytes) {
    final clampedSize = sizeBytes.clamp(16, 10 * 1024 * 1024); // max 10 MB limit
    final bytes = Uint8List(clampedSize);
    for (int i = 0; i < clampedSize; i++) {
      bytes[i] = _secureRandom.nextInt(256);
    }
    return bytes;
  }

  /// Generates a valid high-entropy PNG RGBA noise image keyfile.
  ///
  /// Encodes via the platform's own (Skia) PNG encoder through `dart:ui`
  /// -- the same [ui.decodeImageFromPixels] this app already uses for
  /// AVIF frame display (see `native_avif_widget.dart`) -- rather than a
  /// hand-rolled PNG/CRC32/Adler32 implementation. That means no new
  /// package and no bespoke binary-format code to get subtly wrong.
  static Future<Uint8List> generateImageKeyfile(int dimension) async {
    final dim = dimension.clamp(16, 1024);
    final rawPixels = Uint8List(dim * dim * 4);

    for (int i = 0; i < rawPixels.length; i += 4) {
      rawPixels[i] = _secureRandom.nextInt(256); // R
      rawPixels[i + 1] = _secureRandom.nextInt(256); // G
      rawPixels[i + 2] = _secureRandom.nextInt(256); // B
      rawPixels[i + 3] = 255; // Alpha (fully opaque)
    }

    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rawPixels,
      dim,
      dim,
      ui.PixelFormat.rgba8888,
      (image) => completer.complete(image),
    );
    final image = await completer.future;
    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw StateError('Failed to encode keyfile image as PNG');
      }
      return byteData.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  /// Calculates SHA-256 fingerprint hex of keyfile bytes via the
  /// platform's `java.security.MessageDigest` (see
  /// [VaultHashApi.hashBytesSha256] / HashVerifierHandlers.kt) rather
  /// than a Dart hashing package.
  static Future<String> calculateKeyfileFingerprint(
    VaultHashApi hashApi,
    Uint8List bytes,
  ) {
    return hashApi.hashBytesSha256(bytes);
  }

  /// Qualitative password strength classification and a matching
  /// (very rough, order-of-magnitude) brute-force crack-time estimate.
  /// Returns semantic enums rather than display strings -- callers
  /// localize via `context.l10n` (see [PasswordStrengthLevel] and
  /// [PasswordCrackTimeEstimate]) instead of baking English text in here.
  static ({
    PasswordStrengthLevel level,
    double scoreFraction,
    PasswordCrackTimeEstimate crackTime,
  }) evaluatePasswordStrength(double entropyBits) {
    if (entropyBits < 40) {
      return (
        level: PasswordStrengthLevel.weak,
        scoreFraction: 0.25,
        crackTime: PasswordCrackTimeEstimate.instant,
      );
    } else if (entropyBits < 60) {
      return (
        level: PasswordStrengthLevel.good,
        scoreFraction: 0.5,
        crackTime: PasswordCrackTimeEstimate.shortTerm,
      );
    } else if (entropyBits < 80) {
      return (
        level: PasswordStrengthLevel.strong,
        scoreFraction: 0.75,
        crackTime: PasswordCrackTimeEstimate.centuries,
      );
    } else {
      return (
        level: PasswordStrengthLevel.unbreakable,
        scoreFraction: 1.0,
        crackTime: PasswordCrackTimeEstimate.millionsOfYears,
      );
    }
  }
}
