import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/library/index/cover_overrides_codec.dart';

Uint8List _img(int n, [int seed = 1]) =>
    Uint8List.fromList(List.generate(n, (i) => (i * seed) & 0xFF));

void main() {
  test('round trip keeps every key and every byte', () {
    final src = {
      'album|a:x|y': _img(5000, 3),
      'artist|björk ✓': _img(10, 7),
      'album|n:empty': Uint8List(0),
    };
    final back = CoverOverridesCodec.decode(CoverOverridesCodec.encode(src));
    expect(back.keys.toList(), src.keys.toList());
    for (final k in src.keys) {
      expect(back[k], src[k], reason: k);
    }
  });

  test('empty map round trips', () {
    expect(CoverOverridesCodec.decode(CoverOverridesCodec.encode({})), isEmpty);
  });

  void expectRejected(Uint8List blob) {
    var threw = false;
    try {
      CoverOverridesCodec.decode(blob);
    } on FormatException {
      threw = true;
    }
    expect(threw, isTrue);
  }

  test('wrong magic, truncation and trailing bytes are rejected', () {
    final good = CoverOverridesCodec.encode({'k': _img(100)});
    expectRejected(Uint8List.fromList([1, 2, 3]));
    expectRejected(Uint8List(0));
    expectRejected(Uint8List.fromList([0, 0, 0, 0, 0, 0, 0, 0]));
    expectRejected(Uint8List.sublistView(good, 0, good.length - 1));
    expectRejected(Uint8List.fromList([...good, 9]));
  });

  test('an absurd length is rejected instead of allocating', () {
    final b = BytesBuilder()
      ..add([0x56, 0x45, 0x43, 0x31, 0, 0, 0, 1, 0, 1, 0x6B, 0xFF, 0xFF, 0xFF, 0xFF]);
    expectRejected(b.takeBytes());
    final many = Uint8List.fromList([0x56, 0x45, 0x43, 0x31, 0xFF, 0xFF, 0xFF, 0xFF]);
    expectRejected(many);
  });
}
