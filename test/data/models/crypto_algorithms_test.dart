import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/models/crypto_algorithms.dart';

void main() {
  group('HashAlgo', () {
    test('concrete ids are 0..N-1, in canonical native-mirroring order',
        () {
      final ids = HashAlgo.concrete.map((h) => h.id).toList();
      expect(ids, List.generate(HashAlgo.concrete.length, (i) => i));
    });

    test('no two concrete hash algorithms share an id', () {
      final ids = HashAlgo.concrete.map((h) => h.id).toSet();
      expect(ids, hasLength(HashAlgo.concrete.length));
    });

    test('auto is the 255 sentinel and is not itself a concrete choice',
        () {
      expect(HashAlgo.auto.id, 255);
      expect(HashAlgo.concrete, isNot(contains(HashAlgo.auto)));
    });

    test('withAuto prepends auto to the concrete list', () {
      expect(HashAlgo.withAuto.first, HashAlgo.auto);
      expect(HashAlgo.withAuto.length, HashAlgo.concrete.length + 1);
      expect(HashAlgo.withAuto.skip(1), HashAlgo.concrete);
    });

    test('nameFor resolves known ids, including the auto sentinel, and '
        'falls back to "Unknown"', () {
      expect(HashAlgo.nameFor(0), 'SHA-512');
      expect(HashAlgo.nameFor(1), 'SHA-256');
      expect(HashAlgo.nameFor(5), 'Argon2id');
      expect(HashAlgo.nameFor(255), 'Auto-detect');
      expect(HashAlgo.nameFor(999), 'Unknown');
    });

    test('luks1Choices is exactly [sha256, sha512] — no Argon2, matching '
        'the LUKS1 spec', () {
      expect(HashAlgo.luks1Choices, [HashAlgo.sha256, HashAlgo.sha512]);
    });

    test('luks2Choices adds argon2id on top of the LUKS1 choices', () {
      expect(
        HashAlgo.luks2Choices,
        [HashAlgo.sha256, HashAlgo.sha512, HashAlgo.argon2id],
      );
    });

    test('every luks1Choices/luks2Choices entry is a real concrete '
        'algorithm', () {
      for (final h in [...HashAlgo.luks1Choices, ...HashAlgo.luks2Choices]) {
        expect(HashAlgo.concrete, contains(h));
      }
    });

    test('dropdownItems(includeAuto: true) has one entry per withAuto '
        'entry, in the same order, with matching values', () {
      final items = HashAlgo.dropdownItems();
      expect(items, hasLength(HashAlgo.withAuto.length));
      for (var i = 0; i < items.length; i++) {
        expect(items[i].value, HashAlgo.withAuto[i].id);
      }
    });

    test('dropdownItems(includeAuto: false) excludes the auto sentinel',
        () {
      final items = HashAlgo.dropdownItems(includeAuto: false);
      expect(items, hasLength(HashAlgo.concrete.length));
      expect(items.map((i) => i.value), isNot(contains(255)));
    });
  });

  group('CipherAlgo', () {
    test('concrete ids are 0..N-1, in canonical native-mirroring order',
        () {
      final ids = CipherAlgo.concrete.map((c) => c.id).toList();
      expect(ids, List.generate(CipherAlgo.concrete.length, (i) => i));
    });

    test('no two concrete ciphers share an id', () {
      final ids = CipherAlgo.concrete.map((c) => c.id).toSet();
      expect(ids, hasLength(CipherAlgo.concrete.length));
    });

    test('auto is the 255 sentinel and is not itself a concrete choice',
        () {
      expect(CipherAlgo.auto.id, 255);
      expect(CipherAlgo.concrete, isNot(contains(CipherAlgo.auto)));
    });

    test('withAuto prepends auto to the concrete list', () {
      expect(CipherAlgo.withAuto.first, CipherAlgo.auto);
      expect(CipherAlgo.withAuto.length, CipherAlgo.concrete.length + 1);
    });

    test('nameFor resolves known ids and falls back to "Unknown"', () {
      expect(CipherAlgo.nameFor(0), 'AES');
      expect(CipherAlgo.nameFor(7), 'Serpent-Twofish-AES');
      expect(CipherAlgo.nameFor(255), 'Auto-detect');
      expect(CipherAlgo.nameFor(-1), 'Unknown');
    });

    test('ids 0..7 are preserved exactly for backward compatibility with '
        'previously stored container headers', () {
      const legacyOrder = [
        CipherAlgo.aes,
        CipherAlgo.serpent,
        CipherAlgo.twofish,
        CipherAlgo.aesTwofish,
        CipherAlgo.serpentAes,
        CipherAlgo.twofishSerpent,
        CipherAlgo.aesTwofishSerpent,
        CipherAlgo.serpentTwofishAes,
      ];
      for (var i = 0; i < legacyOrder.length; i++) {
        expect(legacyOrder[i].id, i, reason: legacyOrder[i].label);
      }
    });

    test('luks2Choices contains only single (non-cascaded) ciphers with '
        'real dm-crypt equivalents', () {
      expect(
        CipherAlgo.luks2Choices,
        [
          CipherAlgo.aes,
          CipherAlgo.serpent,
          CipherAlgo.twofish,
          CipherAlgo.camellia,
          CipherAlgo.kuznyechik,
        ],
      );
      // No cascades: LUKS/dm-crypt can't express AES-Twofish etc.
      expect(CipherAlgo.luks2Choices, isNot(contains(CipherAlgo.aesTwofish)));
    });

    test('luks1Choices matches luks2Choices\' cipher set', () {
      expect(CipherAlgo.luks1Choices, CipherAlgo.luks2Choices);
    });

    test('every luks1Choices/luks2Choices entry is a real concrete cipher',
        () {
      for (final c in [
        ...CipherAlgo.luks1Choices,
        ...CipherAlgo.luks2Choices,
      ]) {
        expect(CipherAlgo.concrete, contains(c));
      }
    });

    test('dropdownItems(includeAuto: true) matches withAuto 1:1', () {
      final items = CipherAlgo.dropdownItems();
      expect(items, hasLength(CipherAlgo.withAuto.length));
      for (var i = 0; i < items.length; i++) {
        expect(items[i].value, CipherAlgo.withAuto[i].id);
      }
    });

    test('dropdownItems(includeAuto: false) excludes the auto sentinel',
        () {
      final items = CipherAlgo.dropdownItems(includeAuto: false);
      expect(items.map((i) => i.value), isNot(contains(255)));
    });
  });

  group('CreateFormat', () {
    test('ids match the native containerFormat creation parameter', () {
      expect(CreateFormat.veracrypt.id, 0);
      expect(CreateFormat.luks1.id, 1);
      expect(CreateFormat.luks2.id, 2);
    });

    test('labels are human-readable format names', () {
      expect(CreateFormat.veracrypt.label, 'VeraCrypt');
      expect(CreateFormat.luks1.label, 'LUKS1');
      expect(CreateFormat.luks2.label, 'LUKS2');
    });
  });
}
