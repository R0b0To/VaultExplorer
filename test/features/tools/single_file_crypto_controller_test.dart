import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/tools/models/tool_models.dart';
import 'package:vaultexplorer/features/tools/widgets/single_file_crypto_controller.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
  });

  tearDown(() {
    container.dispose();
  });

  group('SingleFileCryptoController Tests', () {
    test('initializes with default encrypt direction and cipher', () {
      final provider = singleFileCryptoProvider(null, null, null);
      final state = container.read(provider);

      expect(state.direction, CryptoDirection.encrypt);
      expect(state.cipher, StandaloneCipher.xChaCha20Poly1305);
      expect(state.sources, isEmpty);
      expect(state.destination, isNull);
    });

    test('setDirection flips direction and clears error', () {
      final provider = singleFileCryptoProvider(null, null, null);
      final controller = container.read(provider.notifier);

      controller.setDirection(CryptoDirection.decrypt);
      final state = container.read(provider);

      expect(state.direction, CryptoDirection.decrypt);
      expect(state.error, isNull);
    });

    test('setCipher and setDeleteOriginal update respective options', () {
      final provider = singleFileCryptoProvider(null, null, null);
      final controller = container.read(provider.notifier);

      controller.setCipher(StandaloneCipher.aes256Gcm);
      expect(container.read(provider).cipher, StandaloneCipher.aes256Gcm);

      controller.setDeleteOriginal(true);
      expect(container.read(provider).deleteOriginal, isTrue);
    });

    test('addSources, removeSource, and clearSources manage item list', () {
      final provider = singleFileCryptoProvider(null, null, null);
      final controller = container.read(provider.notifier);

      final itemA = CryptoSourceItem.external(displayName: 'a.txt', externalUri: 'file:///a.txt');
      final itemB = CryptoSourceItem.external(displayName: 'b.txt', externalUri: 'file:///b.txt');

      controller.addSources([itemA, itemB]);
      expect(container.read(provider).sources, hasLength(2));

      controller.removeSource(itemA);
      expect(container.read(provider).sources, [itemB]);

      controller.clearSources();
      expect(container.read(provider).sources, isEmpty);
    });

    test('setDestination assigns destination properly', () {
      final provider = singleFileCryptoProvider(null, null, null);
      final controller = container.read(provider.notifier);

      const dest = CryptoDestination.external(displayName: 'Downloads', externalPath: '/storage/downloads');
      controller.setDestination(dest);

      expect(container.read(provider).destination, equals(dest));
    });
  });
}