import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/features/camera/active_recording_registry.dart';

void main() {
  group('ActiveRecordingRegistry Tests', () {
    test('register and unregister track active recording state', () async {
      final registry = ActiveRecordingRegistry();

      expect(registry.isActiveFor('vault://1'), isFalse);

      bool stopped = false;
      registry.register('vault://1', () async {
        stopped = true;
      });

      expect(registry.isActiveFor('vault://1'), isTrue);

      await registry.stopIfActive('vault://1');
      expect(stopped, isTrue);

      registry.unregister('vault://1');
      expect(registry.isActiveFor('vault://1'), isFalse);
    });

    test('stopIfActive on unknown uri does nothing', () async {
      final registry = ActiveRecordingRegistry();
      await registry.stopIfActive('vault://unknown');
      expect(registry.isActiveFor('vault://unknown'), isFalse);
    });

    test('stopIfActive catches errors gracefully', () async {
      final registry = ActiveRecordingRegistry();
      registry.register('vault://err', () async {
        throw Exception('stop failed');
      });

      // Should not throw
      await registry.stopIfActive('vault://err');
    });

    test('activeRecordingRegistryProvider provides distinct instances in separate containers', () {
      final container1 = ProviderContainer();
      final container2 = ProviderContainer();
      addTearDown(container1.dispose);
      addTearDown(container2.dispose);

      final reg1 = container1.read(activeRecordingRegistryProvider);
      final reg2 = container2.read(activeRecordingRegistryProvider);

      expect(identical(reg1, reg2), isFalse);
    });
  });
}
