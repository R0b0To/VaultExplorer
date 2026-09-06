import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/services/container_repository.dart';
import 'package:vaultexplorer/features/tools/widgets/composite_container_controller.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
  });

  tearDown(() {
    container.dispose();
  });

  group('CompositeContainer remember', () {
    test('initializes with remember defaulting to false', () {
      final state = container.read(compositeContainerProvider);
      // Unlike CreateContainerState.remember (defaults true), composite's
      // remember defaults false: persisting it writes down which
      // otherwise-unrelated files are secretly linked together, which is
      // more sensitive than an ordinary "remember this container" bookmark
      // and should stay opt-in rather than opt-out.
      expect(state.remember, isFalse);
    });

    test('setRemember toggles whether the composite record is saved', () {
      final controller = container.read(compositeContainerProvider.notifier);

      controller.setRemember(true);
      expect(container.read(compositeContainerProvider).remember, isTrue);

      controller.setRemember(false);
      expect(container.read(compositeContainerProvider).remember, isFalse);
    });
  });

  group('CompositeContainer loadCarriersFromRecord', () {
    test('pre-populates picked carriers from a remembered record and switches to unlock mode', () {
      final controller = container.read(compositeContainerProvider.notifier);
      final record = ContainerRecord(
        uri: 'composite:content://carrier1',
        label: 'Composite Container (2 files)',
        compositeCarriers: const [
          {'uri': 'content://carrier1', 'name': 'photo1.jpg'},
          {'uri': 'content://carrier2', 'name': 'photo2.jpg'},
        ],
      );

      controller.loadCarriersFromRecord(record);

      final state = container.read(compositeContainerProvider);
      expect(state.isCreating, isFalse);
      expect(state.pickedCarriers, hasLength(2));
      expect(state.pickedCarriers.first.uri, 'content://carrier1');
      expect(state.pickedCarriers.first.displayName, 'photo1.jpg');
    });
  });
}
