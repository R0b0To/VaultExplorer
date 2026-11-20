import 'package:test/test.dart';
import 'package:vaultexplorer/core/utils/md5_hex.dart';

void main() {
  group('md5HexOfString — RFC 1321 test suite', () {
    const vectors = <String, String>{
      '': 'd41d8cd98f00b204e9800998ecf8427e',
      'a': '0cc175b9c0f1b6a831c399e269772661',
      'abc': '900150983cd24fb0d6963f7d28e17f72',
      'message digest': 'f96b697d7cb7938d525a2f31aaf161d0',
      'abcdefghijklmnopqrstuvwxyz': 'c3fcd3d76192e4007dfb496cca67e13b',
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789':
          'd174ab98d277d9f5a5611c2c9f419d9f',
      '1234567890123456789012345678901234567890'
              '1234567890123456789012345678901234567890':
          '57edf4a22be3c955ac49da2e2107b67a',
    };
    vectors.forEach((input, digest) {
      test('"${input.length > 20 ? '${input.substring(0, 20)}…' : input}"', () {
        expect(md5HexOfString(input), digest);
      });
    });
  });

  group('md5Hex — padding boundaries', () {
    // Lengths either side of the 56-byte / 64-byte block edges, where the
    // length field spills into an extra block. Digests of 'a' * n.
    const repeatedA = <int, String>{
      55: 'ef1772b6dff9a122358552954ad0df65',
      56: '3b0c8ac703f828b04c6c197006d17218',
      57: '652b906d60af96844ebd21b674f35e93',
      63: 'b06521f39153d618550606be297466d5',
      64: '014842d480b571495a4a0363793f7367',
      65: 'c743a45e0d2e6a95cb859adae0248435',
      119: '8a7bd0732ed6a28ce75f6dabc90e1613',
      120: '5f61c0ccad4cac44c75ff505e1f1e537',
      128: 'e510683b3f5ffe4093d021808bc6ff70',
    };
    repeatedA.forEach((length, digest) {
      test('$length bytes', () {
        expect(md5Hex(List<int>.filled(length, 0x61)), digest);
      });
    });
  });

  group('md5HexOfString — the strings the thumbnail cache really hashes', () {
    // Digests produced by java.security.MessageDigest("MD5") / Python hashlib
    // over the UTF-8 bytes: the same bytes the native hashBytesMd5 handler was
    // given, so existing on-disk cache names keep matching.
    test('a container URI', () {
      expect(
        md5HexOfString(
          'content://com.android.externalstorage.documents/tree/primary%3AVault',
        ),
        'c2f6565e91dfd6d8c670d0bd5825a8cf',
      );
    });

    test('a qualified file path', () {
      expect(
        md5HexOfString('DCIM/Camera/IMG_0001.jpg|180|70'),
        '78c202202eed3a605e95afe090de7fc8',
      );
    });

    test('non-ASCII text is hashed as UTF-8', () {
      expect(
        md5HexOfString('Фото/海边 😀.jpg|video:poster|320|80'),
        '67dead3910f6b7478c0a80c56f742b67',
      );
    });

    test('output is always 32 lowercase hex characters', () {
      for (final s in ['', 'x', 'a' * 1000, 'ÿ']) {
        expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(md5HexOfString(s)), isTrue);
      }
    });
  });
}
