// Built-in TOTP authenticator's code-generation core: RFC 4648 base32
// decoding plus RFC 6238 (TOTP), built on RFC 4226 (HOTP)'s dynamic
// truncation. Deliberately dependency-free beyond `package:crypto` --
// already vendored transitively (see pubspec.yaml) -- rather than pulling
// in a third-party `otp`/`base32` package, consistent with this app's
// general preference for owning its own crypto-adjacent code (see the
// native engine's bundled cipher implementations).
//
// Storage model: a TOTP secret lives as a plain field (`totp_secret`) on a
// [VaultItem] -- either a dedicated [VaultItemType.authenticator] item, or
// (unchanged, pre-existing) a `password` item's optional 2FA field. This
// file never touches [VaultItem] itself; [TotpConfig.fromFields] takes the
// raw field map so the model layer stays free of algorithm concerns, the
// same separation [ExchangeRecord] keeps from the codecs that use it.
library;

import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

/// Thrown by [base32Decode] when the input isn't valid RFC 4648 base32.
class Base32Exception implements Exception {
  final String message;
  const Base32Exception(this.message);
  @override
  String toString() => message;
}

/// Thrown by [TotpEngine.generateCode] when [TotpConfig.secret] can't
/// produce a code -- callers should show an error state rather than a
/// wrong or stale one.
class TotpCodeException implements Exception {
  final String message;
  const TotpCodeException(this.message);
  @override
  String toString() => message;
}

const String _base32Alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

/// Decodes an RFC 4648 base32 string into raw bytes. Tolerant of the messy
/// real-world shape a TOTP secret actually arrives in -- lower case,
/// stray spaces/dashes (many issuers print it in 4-character groups),
/// and missing '=' padding -- rather than demanding a canonical encoding.
Uint8List base32Decode(String input) {
  final cleaned = input.toUpperCase().replaceAll(RegExp(r'[\s\-]'), '').replaceAll('=', '');
  if (cleaned.isEmpty) {
    throw const Base32Exception('Secret is empty.');
  }
  final bytes = <int>[];
  int buffer = 0;
  int bitsLeft = 0;
  for (var i = 0; i < cleaned.length; i++) {
    final ch = cleaned[i];
    final idx = _base32Alphabet.indexOf(ch);
    if (idx == -1) {
      throw Base32Exception('Invalid character "$ch" in secret -- only A-Z and 2-7 are valid.');
    }
    buffer = (buffer << 5) | idx;
    bitsLeft += 5;
    if (bitsLeft >= 8) {
      bitsLeft -= 8;
      bytes.add((buffer >> bitsLeft) & 0xFF);
    }
  }
  return Uint8List.fromList(bytes);
}

enum TotpAlgorithm {
  sha1,
  sha256,
  sha512;

  /// Parses the free-text `totp_algorithm` field -- tolerant of case and
  /// separators ("SHA-256", "sha_256", "Sha256" all resolve the same way)
  /// -- falling back to SHA1, the default essentially every real-world TOTP
  /// issuer uses, for blank or unrecognized input.
  static TotpAlgorithm fromFieldValue(String? raw) {
    final normalized = (raw ?? '').toUpperCase().replaceAll(RegExp(r'[\s\-_]'), '');
    return switch (normalized) {
      'SHA256' => TotpAlgorithm.sha256,
      'SHA512' => TotpAlgorithm.sha512,
      _ => TotpAlgorithm.sha1,
    };
  }

  crypto.Hash get _hash => switch (this) {
    TotpAlgorithm.sha1 => crypto.sha1,
    TotpAlgorithm.sha256 => crypto.sha256,
    TotpAlgorithm.sha512 => crypto.sha512,
  };

  /// Canonical uppercase name, as written back into an item's
  /// `totp_algorithm` field and into an exported `otpauth://` URI.
  String get wireName => switch (this) {
    TotpAlgorithm.sha1 => 'SHA1',
    TotpAlgorithm.sha256 => 'SHA256',
    TotpAlgorithm.sha512 => 'SHA512',
  };
}

/// Everything [TotpEngine] needs to generate a code, parsed from a
/// [VaultItem]'s raw field map (works the same whether the item is a
/// dedicated [VaultItemType.authenticator] entry or a `password` item's
/// `totp_secret` field -- both use identical field keys).
class TotpConfig {
  /// Raw as stored -- may contain spaces/dashes/lower case; [generateCode]
  /// normalizes it via [base32Decode].
  final String secret;
  final TotpAlgorithm algorithm;
  final int digits;
  final int period;

  const TotpConfig({
    required this.secret,
    this.algorithm = TotpAlgorithm.sha1,
    this.digits = 6,
    this.period = 30,
  });

  /// True when [secret] has any non-whitespace content -- doesn't validate
  /// it's *decodable* base32 (that's [generateCode]'s job); just enough to
  /// decide whether an item is TOTP-capable at all, e.g. for the aggregate
  /// Authenticator registry scan.
  bool get hasSecret => secret.trim().isNotEmpty;

  /// Reads `totp_secret`/`totp_algorithm`/`totp_digits`/`totp_period` out
  /// of a [VaultItem.fields] map (or an [ExchangeRecord.fields] map --
  /// same keys either way), applying the same SHA1/6-digit/30-second
  /// defaults every mainstream issuer uses when the advanced fields are
  /// left blank.
   factory TotpConfig.fromFields(Map<String, String> fields) {
    var rawSecret = (fields['totp_secret'] ?? '').trim();
    String? uriAlgorithm;
    int? uriDigits;
    int? uriPeriod;

    if (rawSecret.toLowerCase().startsWith('otpauth://')) {
      try {
        final uri = Uri.parse(rawSecret);
        final qp = uri.queryParameters;
        if (qp.containsKey('secret')) {
          rawSecret = qp['secret'] ?? rawSecret;
        }
        if (qp.containsKey('algorithm')) {
          uriAlgorithm = qp['algorithm'];
        }
        if (qp.containsKey('digits')) {
          uriDigits = int.tryParse(qp['digits']!);
        }
        if (qp.containsKey('period')) {
          uriPeriod = int.tryParse(qp['period']!);
        }
      } catch (_) {}
    }

    final parsedDigits = int.tryParse((fields['totp_digits'] ?? '').trim()) ?? uriDigits ?? 6;
    final parsedPeriod = int.tryParse((fields['totp_period'] ?? '').trim()) ?? uriPeriod ?? 30;
    return TotpConfig(
      secret: rawSecret,
      algorithm: TotpAlgorithm.fromFieldValue(fields['totp_algorithm'] ?? uriAlgorithm),
      // A handful of real issuers use 7 or 8 digits; anything outside
      // 6-10 is almost certainly a typo, not an intentional value, so
      // falls back to the standard 6 rather than producing a code no
      // authenticator app (including this one, elsewhere) would agree on.
      digits: (parsedDigits >= 6 && parsedDigits <= 10) ? parsedDigits : 6,
      period: parsedPeriod > 0 ? parsedPeriod : 30,
    );
  }
}

/// RFC 6238 (TOTP) code generation, dynamic truncation per RFC 4226 §5.3.
class TotpEngine {
  const TotpEngine._();

  /// Generates the current code for [config] at [at] (defaults to now).
  /// Throws [TotpCodeException] if [config.secret] isn't valid base32 --
  /// callers should catch this and show an error state rather than a wrong
  /// code.
  static String generateCode(TotpConfig config, {DateTime? at}) {
    final Uint8List keyBytes;
    try {
      keyBytes = base32Decode(config.secret);
    } on Base32Exception catch (e) {
      throw TotpCodeException(e.message);
    }
    if (keyBytes.isEmpty) {
      throw const TotpCodeException('Secret is empty.');
    }

    final counter = _counterFor(config, at);
    final counterBytes = ByteData(8)..setUint64(0, counter, Endian.big);
   final hash = crypto.Hmac(config.algorithm._hash, keyBytes).convert(counterBytes.buffer.asUint8List()).bytes;

    // RFC 4226 §5.3 dynamic truncation.
    final offset = hash[hash.length - 1] & 0x0f;
    final binCode = ((hash[offset] & 0x7f) << 24) |
        ((hash[offset + 1] & 0xff) << 16) |
        ((hash[offset + 2] & 0xff) << 8) |
        (hash[offset + 3] & 0xff);
  final code = binCode % _pow10(config.digits);
    return code.toString().padLeft(config.digits, '0');
  }

  /// Generates the code for the period immediately following [at] (defaults to now).
  static String generateNextCode(TotpConfig config, {DateTime? at}) {
    final period = config.period > 0 ? config.period : 30;
    final nextTime = (at ?? DateTime.now()).add(Duration(seconds: period));
    return generateCode(config, at: nextTime);
  }

  /// Seconds remaining in the current period at [at] (defaults to now) --
  /// drives a per-second countdown label.
  static int secondsRemaining(TotpConfig config, {DateTime? at}) {
    final period = config.period > 0 ? config.period : 30;
    final secs = (at ?? DateTime.now()).toUtc().millisecondsSinceEpoch ~/ 1000;
    return period - (secs % period);
  }

  /// Fraction of the current period elapsed, in `[0, 1)` -- 0 right after a
  /// new code is generated, approaching 1 just before it rolls over. Meant
  /// to be sampled frequently (e.g. every 100-200ms) against real
  /// wall-clock time to drive a smoothly-animating countdown ring without
  /// drifting, rather than stepping once a second.
  static double fractionElapsed(TotpConfig config, {DateTime? at}) {
    final period = config.period > 0 ? config.period : 30;
    final millis = (at ?? DateTime.now()).toUtc().millisecondsSinceEpoch;
    final periodMs = period * 1000;
    return (millis % periodMs) / periodMs;
  }

  static int _counterFor(TotpConfig config, DateTime? at) {
    final period = config.period > 0 ? config.period : 30;
    final secs = (at ?? DateTime.now()).toUtc().millisecondsSinceEpoch ~/ 1000;
    return secs ~/ period;
  }

  static int _pow10(int n) {
    var result = 1;
    for (var i = 0; i < n; i++) {
      result *= 10;
    }
    return result;
  }
}

/// Groups a code into readable triads/quads (e.g. "123456" -> "123 456",
/// "1234567" -> "1234 567") -- the tabular-monospace convention every
/// mainstream authenticator app displays codes in.
String formatTotpCode(String code) {
  if (code.length <= 4) return code;
  final mid = (code.length / 2).ceil();
  return '${code.substring(0, mid)} ${code.substring(mid)}';
}
