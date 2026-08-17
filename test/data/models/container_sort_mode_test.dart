import 'package:test/test.dart';
import 'package:vaultexplorer/data/models/container_sort_mode.dart';

void main() {
  group('toJson', () {
    test('serializes to the enum\'s name', () {
      expect(ContainerSortMode.manual.toJson(), 'manual');
      expect(ContainerSortMode.unlockStatus.toJson(), 'unlockStatus');
      expect(ContainerSortMode.nameAZ.toJson(), 'nameAZ');
      expect(ContainerSortMode.nameZA.toJson(), 'nameZA');
      expect(ContainerSortMode.newest.toJson(), 'newest');
      expect(ContainerSortMode.oldest.toJson(), 'oldest');
    });
  });

  group('fromJson', () {
    test('every value round-trips through toJson/fromJson', () {
      for (final mode in ContainerSortMode.values) {
        expect(ContainerSortMode.fromJson(mode.toJson()), mode);
      }
    });

    test('null falls back to manual', () {
      expect(ContainerSortMode.fromJson(null), ContainerSortMode.manual);
    });

    test('an unrecognized string falls back to manual rather than '
        'throwing — important since this reads a value a future app '
        'version (or an older one after a rename) may have written', () {
      expect(ContainerSortMode.fromJson('sizeDescending'), ContainerSortMode.manual);
      expect(ContainerSortMode.fromJson(''), ContainerSortMode.manual);
    });
  });
}
