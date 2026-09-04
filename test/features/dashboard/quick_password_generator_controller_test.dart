import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/dashboard/widgets/quick_password_generator_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late ProviderSubscription subscription;

  setUp(() {
    container = ProviderContainer();
    subscription = container.listen(quickPasswordGeneratorProvider, (_, _) {});
  });

  tearDown(() {
    subscription.close();
    container.dispose();
  });

  group('QuickPasswordGeneratorController Tests', () {
    test('initializes with default dice5 preset', () {
      final state = container.read(quickPasswordGeneratorProvider);

      expect(state.preset, 'dice5');
    });

    test('selectPreset to char24 generates 24-character password', () async {
      final controller = container.read(quickPasswordGeneratorProvider.notifier);

      controller.selectPreset('char24');
      await controller.regenerate();

      final state = container.read(quickPasswordGeneratorProvider);
      expect(state.preset, 'char24');
      expect(state.generated, isNotEmpty);
      expect(state.generated.length, 24);
    });

    test('selectPreset to char32 generates 32-character password', () async {
      final controller = container.read(quickPasswordGeneratorProvider.notifier);

      controller.selectPreset('char32');
      await controller.regenerate();

      final state = container.read(quickPasswordGeneratorProvider);
      expect(state.preset, 'char32');
      expect(state.generated, isNotEmpty);
      expect(state.generated.length, 32);
    });
  });
}