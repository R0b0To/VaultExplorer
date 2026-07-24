import 'package:test/test.dart';
import 'package:vaultexplorer/data/models/container_format.dart';

void main() {
  group('ContainerFormat.fromWire', () {
    test('round-trips every real member through its own wire string', () {
      for (final format in ContainerFormat.values) {
        if (format == ContainerFormat.other) continue; // not a real wire value
        expect(ContainerFormat.fromWire(format.wire), format);
      }
    });

    test('falls back to .other for an unrecognized string', () {
      expect(ContainerFormat.fromWire('not_a_real_format'), ContainerFormat.other);
    });

    test('falls back to .other for the empty string', () {
      expect(ContainerFormat.fromWire(''), ContainerFormat.other);
    });

    test(
        "falls back to .other (not .veracrypt) for unlock_sheet.dart's "
        "'container' sentinel — regression guard: this used to collapse "
        "into veracrypt, which would misrender an unresolved pick as "
        '"VC" before auto-detect actually confirmed VeraCrypt', () {
      expect(ContainerFormat.fromWire('container'), ContainerFormat.other);
      expect(ContainerFormat.fromWire('container').isBitlocker, isFalse);
      expect(ContainerFormat.fromWire('container').isLuks, isFalse);
      expect(ContainerFormat.fromWire('container').isFolderVault, isFalse);
    });
  });

  group('classification getters', () {
    test('isLuks is true only for luks1/luks2', () {
      expect(ContainerFormat.luks1.isLuks, isTrue);
      expect(ContainerFormat.luks2.isLuks, isTrue);
      for (final format in ContainerFormat.values) {
        if (format == ContainerFormat.luks1 || format == ContainerFormat.luks2) {
          continue;
        }
        expect(format.isLuks, isFalse, reason: '$format should not be isLuks');
      }
    });

    test('isFolderVault covers directoryVault + cryptomator + gocryptfs + cryfs', () {
      const folderFormats = {
        ContainerFormat.directoryVault,
        ContainerFormat.cryptomator,
        ContainerFormat.gocryptfs,
        ContainerFormat.cryfs,
      };
      for (final format in ContainerFormat.values) {
        expect(
          format.isFolderVault,
          folderFormats.contains(format),
          reason: '$format.isFolderVault should be ${folderFormats.contains(format)}',
        );
      }
    });

    test('isBitlocker is true only for .bitlocker', () {
      for (final format in ContainerFormat.values) {
        expect(format.isBitlocker, format == ContainerFormat.bitlocker);
      }
    });
  });

  group('*Wire static helpers match their instance-getter equivalents', () {
    test('agree across every real wire string', () {
      for (final format in ContainerFormat.values) {
        if (format == ContainerFormat.other) continue;
        expect(ContainerFormat.isLuksWire(format.wire), format.isLuks);
        expect(ContainerFormat.isBitlockerWire(format.wire), format.isBitlocker);
        expect(ContainerFormat.isCryptomatorWire(format.wire), format.isCryptomator);
        expect(ContainerFormat.isGocryptfsWire(format.wire), format.isGocryptfs);
        expect(ContainerFormat.isCryfsWire(format.wire), format.isCryfs);
        expect(ContainerFormat.isFolderVaultWire(format.wire), format.isFolderVault);
      }
    });
  });
}
