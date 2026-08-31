import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/api/vault_engine_events.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/features/browser/viewer/pdf_viewer_lock_controller.dart';

void main() {
  late ProviderContainer container;
  late VaultEngineEvents events;
  late ProviderSubscription<bool> subscription;

  final provider = pdfViewerLockProvider(7);

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

  test('starts unlocked and responds only to its own vault lock event', () {
    expect(container.read(provider), isFalse);

    events.notifyContainerLocked(8);
    expect(container.read(provider), isFalse);

    events.notifyContainerLocked(7);
    expect(container.read(provider), isTrue);
  });
}
