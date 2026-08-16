import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/services/session_lock_controller.dart';

void main() {
  late AppSettings settings;
  late int enforceAppLockCalls;
  late int lockAllMountedContainersCalls;
  late SessionLockController controller;

  void buildController() {
    enforceAppLockCalls = 0;
    lockAllMountedContainersCalls = 0;
    controller = SessionLockController(
      settings: () => settings,
      lockAllMountedContainers: () async {
        lockAllMountedContainersCalls++;
      },
      enforceAppLock: () {
        enforceAppLockCalls++;
      },
    );
  }

  setUp(() {
    settings = AppSettings();
    buildController();
  });

  group('scheduleAutoLock', () {
    test('does not schedule when autoLockMins is 0', () {
      fakeAsync((async) {
        settings = AppSettings(autoLockMins: 0, lockContainersOnScreenLock: true);
        buildController();

        controller.scheduleAutoLock();
        async.elapse(const Duration(hours: 1));

        expect(enforceAppLockCalls, 0);
        controller.dispose();
      });
    });

    test('does not schedule when there is no master password and '
        'lockContainersOnScreenLock is false', () {
      fakeAsync((async) {
        settings = AppSettings(
          autoLockMins: 5,
          useMasterPassword: false,
          lockContainersOnScreenLock: false,
        );
        buildController();

        controller.scheduleAutoLock();
        async.elapse(const Duration(minutes: 10));

        expect(enforceAppLockCalls, 0);
        controller.dispose();
      });
    });

    test('fires performAutoLock after autoLockMins elapses when a master '
        'password is set', () {
      fakeAsync((async) {
        settings = AppSettings(
          autoLockMins: 5,
          useMasterPassword: true,
          masterPasswordHash: 'stored-hash',
          lockContainersOnScreenLock: false,
        );
        buildController();

        controller.scheduleAutoLock();
        async.elapse(const Duration(minutes: 4, seconds: 59));
        expect(enforceAppLockCalls, 0);

        async.elapse(const Duration(seconds: 1));
        expect(enforceAppLockCalls, 1);

        controller.dispose();
      });
    });

    test('fires when lockContainersOnScreenLock is true even without a '
        'master password', () {
      fakeAsync((async) {
        settings = AppSettings(
          autoLockMins: 2,
          useMasterPassword: false,
          lockContainersOnScreenLock: true,
        );
        buildController();

        controller.scheduleAutoLock();
        async.elapse(const Duration(minutes: 2));

        expect(enforceAppLockCalls, 1);
        expect(lockAllMountedContainersCalls, 1);
        controller.dispose();
      });
    });

    test('a second call to scheduleAutoLock resets the timer instead of '
        'stacking another one', () {
      fakeAsync((async) {
        settings = AppSettings(
          autoLockMins: 5,
          useMasterPassword: true,
          masterPasswordHash: 'h',
        );
        buildController();

        controller.scheduleAutoLock();
        async.elapse(const Duration(minutes: 3));
        controller.scheduleAutoLock(); // resets the 5-minute window
        async.elapse(const Duration(minutes: 3));
        expect(enforceAppLockCalls, 0);

        async.elapse(const Duration(minutes: 2));
        expect(enforceAppLockCalls, 1);

        controller.dispose();
      });
    });
  });

  group('performAutoLock', () {
    test('locks containers only when lockContainersOnScreenLock is true, '
        'even with a master password set', () async {
      settings = AppSettings(
        useMasterPassword: true,
        masterPasswordHash: 'h',
        lockContainersOnScreenLock: false,
      );
      buildController();

      await controller.performAutoLock();

      expect(enforceAppLockCalls, 1);
      expect(lockAllMountedContainersCalls, 0);
    });

    test('does nothing when neither a master password nor '
        'lockContainersOnScreenLock is set', () async {
      settings = AppSettings(
        useMasterPassword: false,
        lockContainersOnScreenLock: false,
      );
      buildController();

      await controller.performAutoLock();

      expect(enforceAppLockCalls, 0);
      expect(lockAllMountedContainersCalls, 0);
    });
  });

  group('handleAppLifecycleState', () {
    test('resuming shortly after pausing reschedules instead of locking '
        'immediately', () {
      fakeAsync((async) {
        settings = AppSettings(
          autoLockMins: 10,
          useMasterPassword: true,
          masterPasswordHash: 'h',
        );
        buildController();

        controller.handleAppLifecycleState(AppLifecycleState.paused);
        async.elapse(const Duration(minutes: 2));
        controller.handleAppLifecycleState(AppLifecycleState.resumed);

        // Should not lock immediately -- away time (2 min) was under the
        // 10-minute threshold, so it just reschedules a fresh 10-minute
        // window from now.
        expect(enforceAppLockCalls, 0);

        async.elapse(const Duration(minutes: 9, seconds: 59));
        expect(enforceAppLockCalls, 0);
        async.elapse(const Duration(seconds: 1));
        expect(enforceAppLockCalls, 1);

        controller.dispose();
      });
    });

    test('resuming after being away longer than autoLockMins locks '
        'immediately', () {
      fakeAsync((async) {
        settings = AppSettings(
          autoLockMins: 10,
          useMasterPassword: true,
          masterPasswordHash: 'h',
        );
        buildController();

        controller.handleAppLifecycleState(AppLifecycleState.paused);
        async.elapse(const Duration(minutes: 15));
        controller.handleAppLifecycleState(AppLifecycleState.resumed);

        expect(enforceAppLockCalls, 1);
        controller.dispose();
      });
    });
  });

  group('handleScreenOff', () {
    test('locks immediately when lockContainersOnScreenLock is true', () async {
      settings = AppSettings(lockContainersOnScreenLock: true);
      buildController();

      controller.handleScreenOff();
      await Future<void>.delayed(Duration.zero);

      expect(enforceAppLockCalls, 1);
      expect(lockAllMountedContainersCalls, 1);
    });

    test('does nothing when lockContainersOnScreenLock is false', () async {
      settings = AppSettings(lockContainersOnScreenLock: false);
      buildController();

      controller.handleScreenOff();
      await Future<void>.delayed(Duration.zero);

      expect(enforceAppLockCalls, 0);
    });
  });

  group('dispose', () {
    test('cancels a pending auto-lock timer', () {
      fakeAsync((async) {
        settings = AppSettings(
          autoLockMins: 5,
          useMasterPassword: true,
          masterPasswordHash: 'h',
        );
        buildController();

        controller.scheduleAutoLock();
        controller.dispose();
        async.elapse(const Duration(minutes: 10));

        expect(enforceAppLockCalls, 0);
      });
    });
  });
}
