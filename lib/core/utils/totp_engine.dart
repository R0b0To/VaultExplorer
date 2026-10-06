// Built-in TOTP authenticator's code-generation core: RFC 4648 base32
// decoding plus RFC 6238 (TOTP), built on RFC 4226 (HOTP)'s dynamic
// truncation. Owns the RFC logic (base32, counters, truncation, Steam's
// alphabet) but not the hash: the HMAC itself is computed by the native
// layer through [VaultCryptoApi.hmac], so no third-party Dart hashing or
// `otp`/`base32` package is involved. Because that is a platform-channel
// call, code generation is asynchronous -- see [TotpEngine.stepFor] for how
// a caller that refreshes on a timer avoids asking for a new code more often
// than one can actually change.
//
// Storage model: a TOTP secret lives as a plain field (`totp_secret`) on a
// [VaultItem] -- either a dedicated [VaultItemType.authenticator] item, or
// (unchanged, pre-existing) a `password` item's optional 2FA field. This
// file never touches [VaultItem] itself; [TotpConfig.fromFields] takes the
// raw field map so the model layer stays free of algorithm concerns, the
// same separation [ExchangeRecord] keeps from the codecs that use it.
library;

import 'dart:typed_data';

import 'package:vaultexplorer/core/api/vault_crypto_api.dart';

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

/// Encodes raw bytes into an RFC 4648 base32 string, no '=' padding --
/// [base32Decode]'s counterpart, needed by codecs that receive a secret as
/// raw bytes (e.g. Google Authenticator's migration export) rather than an
/// already-base32 string.
String base32Encode(Uint8List bytes) {
  if (bytes.isEmpty) return '';
  final buffer = StringBuffer();
  int bitBuffer = 0;
  int bitsLeft = 0;
  for (final byte in bytes) {
    bitBuffer = (bitBuffer << 8) | byte;
    bitsLeft += 8;
    while (bitsLeft >= 5) {
      bitsLeft -= 5;
      buffer.write(_base32Alphabet[(bitBuffer >> bitsLeft) & 0x1F]);
    }
    // Keep only the not-yet-emitted bits so the buffer can't grow without
    // bound on a long input.
    bitBuffer &= (1 << bitsLeft) - 1;
  }
  if (bitsLeft > 0) {
    buffer.write(_base32Alphabet[(bitBuffer << (5 - bitsLeft)) & 0x1F]);
  }
  return buffer.toString();
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

  HmacHash get _hmacHash => switch (this) {
    TotpAlgorithm.sha1 => HmacHash.sha1,
    TotpAlgorithm.sha256 => HmacHash.sha256,
    TotpAlgorithm.sha512 => HmacHash.sha512,
  };

  /// Canonical uppercase name, as written back into an item's
  /// `totp_algorithm` field and into an exported `otpauth://` URI.
  String get wireName => switch (this) {
    TotpAlgorithm.sha1 => 'SHA1',
    TotpAlgorithm.sha256 => 'SHA256',
    TotpAlgorithm.sha512 => 'SHA512',
  };
}

/// Which one-time-password scheme an entry uses.
enum OtpKind {
  /// RFC 6238 time-based codes -- the overwhelming majority of entries.
  totp,

  /// RFC 4226 counter-based codes. The counter lives on the item
  /// (`hotp_counter`) and only moves when the person asks for a new code --
  /// see AuthenticatorRegistry.advanceHotpCounter.
  hotp,

  /// Steam Guard: the same HMAC-SHA1 over a 30-second counter as TOTP, but
  /// the truncated value is rendered as five characters from Steam's own
  /// 26-letter alphabet rather than as decimal digits.
  steam;

  /// Parses the free-text `totp_type` field (or an otpauth:// host);
  /// anything blank or unrecognized is plain TOTP.
  static OtpKind fromFieldValue(String? raw) {
    return switch ((raw ?? '').trim().toLowerCase()) {
      'hotp' => OtpKind.hotp,
      'steam' => OtpKind.steam,
      _ => OtpKind.totp,
    };
  }

  /// Lower-case name as written into an item's `totp_type` field and an
  /// exported `otpauth://` URI's host.
  String get wireName => name;
}

/// Steam Guard's 26-character code alphabet (no vowels or easily confused
/// characters), in the order Steam maps a code's base-26 digits onto it.
const String _steamAlphabet = '23456789BCDFGHJKMNPQRTVWXY';

/// Length of a Steam Guard code.
const int kSteamCodeLength = 5;

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

  /// Time-based (default), counter-based or Steam Guard -- see [OtpKind].
  final OtpKind kind;

  /// The HOTP counter the next code is generated for. Ignored unless
  /// [kind] is [OtpKind.hotp].
  final int counter;

  const TotpConfig({
    required this.secret,
    this.algorithm = TotpAlgorithm.sha1,
    this.digits = 6,
    this.period = 30,
    this.kind = OtpKind.totp,
    this.counter = 0,
  });

  /// True when [secret] has any non-whitespace content -- doesn't validate
  /// it's *decodable* base32 (that's [generateCode]'s job); just enough to
  /// decide whether an item is OTP-capable at all, e.g. for the aggregate
  /// Authenticator registry scan.
  bool get hasSecret => secret.trim().isNotEmpty;

  /// False for HOTP, whose code changes when the counter is advanced rather
  /// than when a period rolls over -- so there's no countdown to show.
  bool get isTimeBased => kind != OtpKind.hotp;

  /// This config with a different HOTP [counter].
  TotpConfig withCounter(int newCounter) => TotpConfig(
        secret: secret,
        algorithm: algorithm,
        digits: digits,
        period: period,
        kind: kind,
        counter: newCounter,
      );

  /// Reads `totp_secret`/`totp_algorithm`/`totp_digits`/`totp_period`
  /// (plus `totp_type`/`hotp_counter` for HOTP and Steam Guard entries) out
  /// of a [VaultItem.fields] map (or an [ExchangeRecord.fields] map -- same
  /// keys either way), applying the same SHA1/6-digit/30-second defaults
  /// every mainstream issuer uses when the advanced fields are left blank.
  /// A full `otpauth://` URI in `totp_secret` is also understood.
  factory TotpConfig.fromFields(Map<String, String> fields) {
    var rawSecret = (fields['totp_secret'] ?? '').trim();
    String? uriAlgorithm;
    String? uriKind;
    int? uriDigits;
    int? uriPeriod;
    int? uriCounter;

    if (rawSecret.toLowerCase().startsWith('otpauth://')) {
      try {
        final uri = Uri.parse(rawSecret);
        final qp = uri.queryParameters;
        uriKind = uri.host;
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
        if (qp.containsKey('counter')) {
          uriCounter = int.tryParse(qp['counter']!);
        }
      } catch (_) {
        // A malformed otpauth:// URI just leaves the defaults in place. Not logged: the exception text can quote the secret.
      }
    }

    final typeField = (fields['totp_type'] ?? '').trim();
    final kind = OtpKind.fromFieldValue(typeField.isNotEmpty ? typeField : uriKind);

    final rawCounter = int.tryParse((fields['hotp_counter'] ?? '').trim()) ?? uriCounter ?? 0;
    final counter = rawCounter < 0 ? 0 : rawCounter;

    // Steam Guard is fixed by its own protocol -- HMAC-SHA1, 30-second
    // steps, five characters -- whatever a source app happened to write
    // into the advanced fields.
    if (kind == OtpKind.steam) {
      return TotpConfig(
        secret: rawSecret,
        algorithm: TotpAlgorithm.sha1,
        digits: kSteamCodeLength,
        period: 30,
        kind: kind,
      );
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
      kind: kind,
      counter: counter,
    );
  }
}

/// RFC 6238 (TOTP) / RFC 4226 (HOTP) code generation, plus Steam Guard's
/// variant. Dynamic truncation per RFC 4226 §5.3 is shared by all three.
class TotpEngine {
  const TotpEngine._();

  /// Generates the current code for [config] at [at] (defaults to now --
  /// ignored for HOTP, whose code depends only on [TotpConfig.counter]).
  /// The HMAC is computed by [crypto] (the native layer).
  ///
  /// Throws [TotpCodeException] if [config.secret] isn't valid base32 or the
  /// platform returned no MAC -- callers should catch this and show an error
  /// state rather than a wrong code. A `PlatformException` from the channel
  /// itself propagates as-is.
  static Future<String> generateCode(
    TotpConfig config, {
    required VaultCryptoApi crypto,
    DateTime? at,
  }) async {
    final Uint8List keyBytes;
    try {
      keyBytes = base32Decode(config.secret);
    } on Base32Exception catch (e) {
      throw TotpCodeException(e.message);
    }
    if (keyBytes.isEmpty) {
      throw const TotpCodeException('Secret is empty.');
    }

    switch (config.kind) {
      case OtpKind.hotp:
        final value = _truncate(await _hmac(crypto, config.algorithm, keyBytes, config.counter));
        return _decimal(value, config.digits);
      case OtpKind.steam:
        final value = _truncate(
          await _hmac(crypto, TotpAlgorithm.sha1, keyBytes, _counterFor(config, at)),
        );
        return _steam(value);
      case OtpKind.totp:
        final value = _truncate(
          await _hmac(crypto, config.algorithm, keyBytes, _counterFor(config, at)),
        );
        return _decimal(value, config.digits);
    }
  }

  /// The code that follows the current one: for TOTP/Steam, the code for
  /// the period immediately following [at] (defaults to now); for HOTP, the
  /// code for the *next counter value* (the tile doesn't preview this --
  /// see AuthenticatorRegistry.advanceHotpCounter for how a counter
  /// actually moves).
  static Future<String> generateNextCode(
    TotpConfig config, {
    required VaultCryptoApi crypto,
    DateTime? at,
  }) {
    if (config.kind == OtpKind.hotp) {
      return generateCode(config.withCounter(config.counter + 1), crypto: crypto);
    }
    final period = config.period > 0 ? config.period : 30;
    final nextTime = (at ?? DateTime.now()).add(Duration(seconds: period));
    return generateCode(config, crypto: crypto, at: nextTime);
  }

  /// The value [generateCode] derives its code from at [at]: the HOTP counter
  /// for counter-based entries, otherwise the current time step. A caller that
  /// re-checks on a timer can compare this against the step it last generated
  /// for and only ask for a new code when it changes -- the code itself is a
  /// (platform-channel) round trip, the step is plain arithmetic.
  static int stepFor(TotpConfig config, {DateTime? at}) =>
      config.kind == OtpKind.hotp ? config.counter : _counterFor(config, at);

  /// Seconds remaining in the current period at [at] (defaults to now) --
  /// drives a per-second countdown label. Meaningless for HOTP.
  static int secondsRemaining(TotpConfig config, {DateTime? at}) {
    final period = config.period > 0 ? config.period : 30;
    final secs = (at ?? DateTime.now()).toUtc().millisecondsSinceEpoch ~/ 1000;
    return period - (secs % period);
  }

  /// Fraction of the current period elapsed, in `[0, 1)` -- 0 right after a
  /// new code is generated, approaching 1 just before it rolls over. Meant
  /// to be sampled frequently (e.g. every 100-200ms) against real
  /// wall-clock time to drive a smoothly-animating countdown ring without
  /// drifting, rather than stepping once a second. Meaningless for HOTP.
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

  static Future<Uint8List> _hmac(
    VaultCryptoApi crypto,
    TotpAlgorithm algorithm,
    Uint8List key,
    int counter,
  ) async {
    final counterBytes = ByteData(8)..setUint64(0, counter, Endian.big);
    final mac = await crypto.hmac(
      key: key,
      data: counterBytes.buffer.asUint8List(),
      hash: algorithm._hmacHash,
    );
    if (mac == null || mac.isEmpty) {
      throw const TotpCodeException('Could not compute a code.');
    }
    return mac;
  }

  /// RFC 4226 §5.3 dynamic truncation -> a 31-bit integer.
  static int _truncate(List<int> hash) {
    final offset = hash[hash.length - 1] & 0x0f;
    return ((hash[offset] & 0x7f) << 24) |
        ((hash[offset + 1] & 0xff) << 16) |
        ((hash[offset + 2] & 0xff) << 8) |
        (hash[offset + 3] & 0xff);
  }

  static String _decimal(int value, int digits) =>
      (value % _pow10(digits)).toString().padLeft(digits, '0');

  /// Steam Guard: the truncated value's base-26 digits, least significant
  /// first, each mapped through [_steamAlphabet].
  static String _steam(int value) {
    final out = StringBuffer();
    var v = value;
    for (var i = 0; i < kSteamCodeLength; i++) {
      out.write(_steamAlphabet[v % _steamAlphabet.length]);
      v ~/= _steamAlphabet.length;
    }
    return out.toString();
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

/// [formatTotpCode] for any [OtpKind]: Steam Guard's five-character codes
/// are shown as one unbroken word, the way the Steam app itself shows them.
String formatOtpCode(String code, OtpKind kind) =>
    kind == OtpKind.steam ? code : formatTotpCode(code);
