import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/api/vault_engine_events.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_lock_controller.dart';

void main() {
  late ProviderContainer container;
  late VaultEngineEvents events;
  late ProviderSubscription<bool> subscription;

  final provider = mediaViewerLockProvider(4);

  setUp(() {
    events = VaultEngineEvents();
    container = ProviderContainer(
      overrides: [vaultEngineEventsProvider.overrideWithValue(events)],
    );
    subscription = container.listen(provider, (_, _) {});
  });

  tearDown(() {
    subscription.close();
    container.dispose();
  });

  test('locks only when its owning container locks', () {
    expect(container.read(provider), isFalse);

    events.notifyContainerLocked(5);
    expect(container.read(provider), isFalse);

    events.notifyContainerLocked(4);
    expect(container.read(provider), isTrue);
  });
}
