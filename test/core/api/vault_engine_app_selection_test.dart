import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/api/vault_engine_events.dart';

void main() {
  group('VaultEngineEvents app selection', () {
    test('delivers a pick to the request that asked for it, exactly once', () {
      final events = VaultEngineEvents();
      final picks = <String>[];
      final a = events.expectAppSelection((pkg) => picks.add('a:$pkg'));
      final b = events.expectAppSelection((pkg) => picks.add('b:$pkg'));

      expect(events.deliverAppSelection(b, 'com.example.viewer'), isTrue);
      expect(events.deliverAppSelection(b, 'com.example.other'), isFalse);

      expect(picks, ['b:com.example.viewer']);
      events.cancelAppSelection(a);
    });

    test('a request that was never answered cannot capture a later pick', () {
      // The old design kept one global listener per extension, so a cancelled
      // chooser could silently remember whatever was picked next. Ids make the
      // two requests independent.
      final events = VaultEngineEvents();
      final picks = <String>[];
      final abandoned = events.expectAppSelection(
        (pkg) => picks.add('abandoned:$pkg'),
      );
      final live = events.expectAppSelection((pkg) => picks.add('live:$pkg'));

      expect(events.deliverAppSelection(live, 'com.example.viewer'), isTrue);

      expect(picks, ['live:com.example.viewer']);
      events.cancelAppSelection(abandoned);
    });

    test('ignores unknown and cancelled request ids', () {
      final events = VaultEngineEvents();
      final picks = <String>[];
      final id = events.expectAppSelection(picks.add);
      events.cancelAppSelection(id);

      expect(events.deliverAppSelection(id, 'com.example.viewer'), isFalse);
      expect(
        events.deliverAppSelection('no-such-id', 'com.example.x'),
        isFalse,
      );
      expect(picks, isEmpty);
    });

    test('drops the listener once its timeout has passed', () async {
      final events = VaultEngineEvents();
      final picks = <String>[];
      final id = events.expectAppSelection(
        picks.add,
        timeout: const Duration(milliseconds: 1),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(events.deliverAppSelection(id, 'com.example.viewer'), isFalse);
      expect(picks, isEmpty);
    });

    test('keeps only the most recent listeners waiting', () {
      final events = VaultEngineEvents();
      final picks = <String>[];
      final oldest = events.expectAppSelection(picks.add);
      var newest = '';
      for (var i = 0; i < 40; i++) {
        newest = events.expectAppSelection(picks.add);
      }

      expect(events.deliverAppSelection(oldest, 'com.example.old'), isFalse);
      expect(events.deliverAppSelection(newest, 'com.example.new'), isTrue);
      expect(picks, ['com.example.new']);
    });

    test('a listener that throws does not break delivery', () {
      final events = VaultEngineEvents();
      final id = events.expectAppSelection((_) => throw StateError('boom'));

      expect(events.deliverAppSelection(id, 'com.example.viewer'), isTrue);
    });
  });
}
