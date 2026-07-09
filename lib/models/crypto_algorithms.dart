library;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  /// Canonical id order — must mirror `HashId` in crypto/cipher_shim.h.
  static const List<HashAlgo> concrete = [
    sha512,
    sha256,
    whirlpool,
    streebog,
    blake2s256,
  ];

  static const List<HashAlgo> withAuto = [auto, ...concrete];

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
  static const _channel = MethodChannel('com.aeidolon.vaultexplorer/engine');
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
  ];

  static const List<CipherAlgo> withAuto = [auto, ...concrete];

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