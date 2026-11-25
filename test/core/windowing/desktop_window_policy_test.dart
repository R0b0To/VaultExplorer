import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/windowing/desktop_window_policy.dart';

/// A stand-in for the windows: it counts what is open and records what the
/// policy asked for, in order.
class _Windows {
  _Windows() {
    policy = DesktopWindowPolicy(
      independentWindowCount: () => independent.length,
      closeWindowsServingMain: () {
        log.add('closeServingMain');
        serving.clear();
      },
      closeAllSecondaryWindows: () {
        log.add('closeAllSecondary');
        independent.clear();
        serving.clear();
        // Closing a window tells the policy, as the registry does.
        policy.secondaryWindowsChanged();
      },
      openMainWindow: () => log.add('openMain'),
      exitApp: () => log.add('exit'),
    );
  }

  late final DesktopWindowPolicy policy;
  final log = <String>[];
  final independent = <String>{};
  final serving = <String>{};

  void openIndependent(String key) {
    independent.add(key);
    policy.secondaryWindowsChanged();
  }

  void closeIndependent(String key) {
    independent.remove(key);
    policy.secondaryWindowsChanged();
  }
}

void main() {
  group('DesktopWindowPolicy', () {
    test('closing the main window leaves an independent window running', () {
      final w = _Windows()..policy.mainWindowOpened();
      w.openIndependent('files:1');
      w.policy.mainWindowClosed();

      expect(w.log, equals(<String>['closeServingMain']));
      expect(w.policy.isExiting, isFalse);
    });

    test('the app ends when the last independent window closes', () {
      final w = _Windows()..policy.mainWindowOpened();
      w.openIndependent('files:1');
      w.policy.mainWindowClosed();
      w.closeIndependent('files:1');

      expect(w.log, equals(<String>['closeServingMain', 'exit']));
    });

    test('with two independent windows it ends only after the second', () {
      final w = _Windows()..policy.mainWindowOpened();
      w.openIndependent('files:1');
      w.openIndependent('files:2');
      w.policy.mainWindowClosed();
      w.closeIndependent('files:1');
      expect(w.policy.isExiting, isFalse);
      w.closeIndependent('files:2');

      expect(w.log.last, equals('exit'));
    });

    test(
      'closing independent windows never ends the app while main is open',
      () {
        final w = _Windows()..policy.mainWindowOpened();
        w.openIndependent('files:1');
        w.closeIndependent('files:1');

        expect(w.log, isEmpty);
        expect(w.policy.isExiting, isFalse);
      },
    );

    test('closing the main window with nothing else open ends the app', () {
      final w = _Windows()..policy.mainWindowOpened();
      w.policy.mainWindowClosed();

      expect(w.log, equals(<String>['closeServingMain', 'exit']));
    });

    test(
      'a lock with the main window closed reopens it instead of exiting',
      () {
        final w = _Windows()..policy.mainWindowOpened();
        w.openIndependent('files:1');
        w.policy.mainWindowClosed();
        w.log.clear();

        w.policy.lockRequested();

        // The main window comes back first; only then do the others close.
        expect(w.log, equals(<String>['openMain', 'closeAllSecondary']));
        expect(w.policy.isMainOpen, isTrue);
        expect(w.policy.isExiting, isFalse);
      },
    );

    test('a lock with the main window open just closes the others', () {
      final w = _Windows()..policy.mainWindowOpened();
      w.openIndependent('files:1');

      w.policy.lockRequested();

      expect(w.log, equals(<String>['closeAllSecondary']));
      expect(w.policy.isExiting, isFalse);
    });

    test('after a lock reopened the main window, closing it ends the app', () {
      final w = _Windows()..policy.mainWindowOpened();
      w.openIndependent('files:1');
      w.policy.mainWindowClosed();
      w.policy.lockRequested();
      w.log.clear();

      w.policy.mainWindowClosed();

      expect(w.log, equals(<String>['closeServingMain', 'exit']));
    });

    test('the app is asked to exit only once', () {
      final w = _Windows()..policy.mainWindowOpened();
      w.policy.mainWindowClosed();
      w.policy.secondaryWindowsChanged();
      w.policy.secondaryWindowsChanged();

      expect(w.log.where((e) => e == 'exit'), hasLength(1));
    });
  });
}
