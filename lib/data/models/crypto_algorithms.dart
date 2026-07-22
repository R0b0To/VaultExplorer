library;

import 'package:flutter/material.dart';

/// Canonical cipher/hash algorithm catalogs.
///
/// Previously the mapping from a raw `int` id to a display name was
/// duplicated across five places: [cipherAlgorithmName]/[hashAlgorithmName]
/// in vaultexplorer_api.dart (two `const` arrays), plus hand-written
/// `DropdownMenuItem<int>` lists in unlock_sheet.dart, usb_unlock_sheet.dart,
/// container_config_sheet.dart, and create_container_sheet.dart. All five
/// had to agree, purely by convention, with the numeric order of `CascadeId`
/// in android/app/src/main/cpp/crypto/cascade.h and `HashId` in
/// android/app/src/main/cpp/crypto/cipher_shim.h. Adding a cipher meant
/// remembering to touch all seven places (5 Dart + 2 C++ enums); missing one
/// silently mismatched a label to the wrong id.
///
/// This file is now the ONE Dart-side source of truth. [CipherAlgo.concrete]
/// and [HashAlgo.concrete] are listed in canonical-id order — that order
/// MUST always match `CascadeId`/`HashId` in the C++ headers above. If you
/// add a cipher or hash on the native side, add it here in the same
/// position (and nowhere else on the Dart side).
///
/// `255` is the shared "auto-detect" sentinel used by the unlock/mount flow
/// (native tries every combination). It is NOT a valid choice when
/// *creating* a container — a concrete algorithm must be picked up front —
/// so every dropdown-builder here takes `includeAuto` to control that.

class HashAlgo {
  final int id;
  final String label;
  const HashAlgo(this.id, this.label);

  /// "Let native auto-detect by trying every hash." Unlock-only.
  static const auto = HashAlgo(255, 'Auto-detect');

  static const sha512 = HashAlgo(0, 'SHA-512');
  static const sha256 = HashAlgo(1, 'SHA-256');
  static const whirlpool = HashAlgo(2, 'Whirlpool');
  static const streebog = HashAlgo(3, 'Streebog');
  static const blake2s256 = HashAlgo(4, 'BLAKE2s-256');
  static const argon2id = HashAlgo(5, 'Argon2id');

  /// Canonical id order — must mirror `HashId` in crypto/cipher_shim.h.
  static const List<HashAlgo> concrete = [
    sha512,
    sha256,
    whirlpool,
    streebog,
    blake2s256,
    argon2id,
  ];

  static const List<HashAlgo> withAuto = [auto, ...concrete];

  /// LUKS1 keyslot KDF is always PBKDF2 (no Argon2 support in the LUKS1
  /// spec). SHA-256 matches modern cryptsetup's own default (`--hash
  /// sha256`); SHA-512 is offered as a stronger alternative. Whirlpool/
  /// Streebog/BLAKE2s aren't real `cryptsetup --hash` options, so they're
  /// excluded here even though they're valid for VeraCrypt.
  static const List<HashAlgo> luks1Choices = [sha256, sha512];

  /// LUKS2 additionally supports Argon2id — real cryptsetup's own default
  /// keyslot KDF (`luksFormat --type luks2` defaults to `--pbkdf argon2id`).
  /// SHA-256/512 remain available as PBKDF2 choices.
  static const List<HashAlgo> luks2Choices = [sha256, sha512, argon2id];

  static String nameFor(int id) {
    for (final h in withAuto) {
      if (h.id == id) return h.label;
    }
    return 'Unknown';
  }

  /// Ready-to-use `items:` list for a `DropdownButtonFormField<int>`.
  /// Pass `includeAuto: false` for creation flows (no auto-detect there).
  static List<DropdownMenuItem<int>> dropdownItems({bool includeAuto = true}) {
    final list = includeAuto ? withAuto : concrete;
    return list
        .map((h) => DropdownMenuItem(value: h.id, child: Text(h.label)))
        .toList();
  }
}

class CipherAlgo {
  final int id;
  final String label;
  const CipherAlgo(this.id, this.label);

  static const auto = CipherAlgo(255, 'Auto-detect');

  static const aes = CipherAlgo(0, 'AES');
  static const serpent = CipherAlgo(1, 'Serpent');
  static const twofish = CipherAlgo(2, 'Twofish');
  static const aesTwofish = CipherAlgo(3, 'AES-Twofish');
  static const serpentAes = CipherAlgo(4, 'Serpent-AES');
  static const twofishSerpent = CipherAlgo(5, 'Twofish-Serpent');
  static const aesTwofishSerpent = CipherAlgo(6, 'AES-Twofish-Serpent');
  static const serpentTwofishAes = CipherAlgo(7, 'Serpent-Twofish-AES');
  // These IDs are appended to retain compatibility with stored IDs 0..7.
  static const camellia = CipherAlgo(8, 'Camellia');
  static const kuznyechik = CipherAlgo(9, 'Kuznyechik');
  static const camelliaKuznyechik = CipherAlgo(10, 'Camellia-Kuznyechik');
  static const camelliaSerpent = CipherAlgo(11, 'Camellia-Serpent');
  static const kuznyechikAes = CipherAlgo(12, 'Kuznyechik-AES');
  static const kuznyechikSerpentCamellia = CipherAlgo(
    13,
    'Kuznyechik-Serpent-Camellia',
  );
  static const kuznyechikTwofish = CipherAlgo(14, 'Kuznyechik-Twofish');

  /// Canonical id order — must mirror `CascadeId` in crypto/cascade.h.
  static const List<CipherAlgo> concrete = [
    aes,
    serpent,
    twofish,
    aesTwofish,
    serpentAes,
    twofishSerpent,
    aesTwofishSerpent,
    serpentTwofishAes,
    camellia,
    kuznyechik,
    camelliaKuznyechik,
    camelliaSerpent,
    kuznyechikAes,
    kuznyechikSerpentCamellia,
    kuznyechikTwofish,
  ];

  static const List<CipherAlgo> withAuto = [auto, ...concrete];

  /// LUKS2 data-cipher choices — aes-xts-plain64/serpent-xts-plain64/
  /// twofish-xts-plain64/camellia-xts-plain64/kuznyechik-xts-plain64 are
  /// all real, single (non-cascaded) `cryptsetup luksFormat --cipher`
  /// options (matching Linux kernel crypto API cipher names — Camellia and
  /// Kuznyechik need that specific cipher module built into the target
  /// kernel, same caveat Serpent/Twofish already carry). Cascades
  /// (multi-layer combos like AES-Twofish-Serpent) aren't included: LUKS/
  /// dm-crypt has no way to express a cascade — one segment maps to
  /// exactly one dm-crypt cipher spec — so those stay VeraCrypt-only.
  static const List<CipherAlgo> luks2Choices = [
    aes,
    serpent,
    twofish,
    camellia,
    kuznyechik,
  ];

  /// LUKS1 creation only ever offers AES: this app's own LUKS1 unlock path
  /// always decrypts the keyslot with AES-CBC regardless of the header's
  /// declared cipher (see luksCreateHeader()'s doc comment in
  /// luks_header.h), so creating a LUKS1 container with a different data
  /// cipher here would make it unopenable by this app again afterward —
  /// real cryptsetup would still open it fine, just not this app.
  static const List<CipherAlgo> luks1Choices = [aes, serpent, twofish, camellia, kuznyechik];

  static String nameFor(int id) {
    for (final c in withAuto) {
      if (c.id == id) return c.label;
    }
    return 'Unknown';
  }

  static List<DropdownMenuItem<int>> dropdownItems({bool includeAuto = true}) {
    final list = includeAuto ? withAuto : concrete;
    return list
        .map((c) => DropdownMenuItem(value: c.id, child: Text(c.label)))
        .toList();
  }
}

/// Container format chosen at CREATION time. Numeric values match
/// container_format.h / ContainerEngine.ContainerFormat.fromNative() in
/// Kotlin so they can be sent directly as the native `containerFormat`
/// creation parameter — independent of the (already-mounted) [ContainerFormat]
/// wire strings used elsewhere ("veracrypt"/"luks1"/"luks2").
enum CreateFormat {
  veracrypt(0, 'VeraCrypt'),
  luks1(1, 'LUKS1'),
  luks2(2, 'LUKS2');

  final int id;
  final String label;
  const CreateFormat(this.id, this.label);
}
