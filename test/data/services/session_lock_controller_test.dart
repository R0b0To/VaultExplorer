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
  DateTime Function() now = DateTime.now;

  void buildController() {
    enforceAppLockCalls = 0;
    lockAllMountedContainersCalls = 0;
    controller = SessionLockController(now: now)
      ..configure(
        settings: () => settings,
        lockAllMountedContainers: () async {
          lockAllMountedContainersCalls++;
        },
        enforceAppLock: () {
          enforceAppLockCalls++;
        },
        now: now,
      );
  }

  setUp(() {
    settings = AppSettings();
    now = DateTime.now;
    buildController();
  });

  group('scheduleAutoLock - Vault Lock (Inactivity)', () {
    test('does not schedule vault lock when autoLockMins is 0', () {
      fakeAsync((async) {
        settings = AppSettings(autoLockMins: 0, lockContainersOnScreenLock: true);
        buildController();

        controller.scheduleAutoLock();
        async.elapse(const Duration(hours: 1));

        expect(lockAllMountedContainersCalls, 0);
        controller.dispose();
      });
    });

    test('does not schedule vault lock when lockContainersOnScreenLock is false', () {
      fakeAsync((async) {
        settings = AppSettings(
          autoLockMins: 5,
          lockContainersOnScreenLock: false,
        );
        buildController();

        controller.scheduleAutoLock();
        async.elapse(const Duration(minutes: 10));

        expect(lockAllMountedContainersCalls, 0);
        controller.dispose();
      });
    });

    test('fires performVaultLock after autoLockMins elapses when lockContainersOnScreenLock is true', () {
      fakeAsync((async) {
        settings = AppSettings(
          autoLockMins: 5,
          lockContainersOnScreenLock: true,
        );
        buildController();

        controller.scheduleAutoLock();
        async.elapse(const Duration(minutes: 4, seconds: 59));
        expect(lockAllMountedContainersCalls, 0);

        async.elapse(const Duration(seconds: 1));
        expect(lockAllMountedContainersCalls, 1);
        expect(enforceAppLockCalls, 0); // App lock is independent

        controller.dispose();
      });
    });
  });

  group('scheduleAutoLock - App Lock (Inactivity)', () {
    test('does not schedule app lock when appLockAfterMins is 0', () {
      fakeAsync((async) {
        settings = AppSettings(
          appLockAfterMins: 0,
          useMasterPassword: true,
          masterPasswordHash: 'h',
        );
        buildController();

        controller.scheduleAutoLock();
        async.elapse(const Duration(hours: 1));

        expect(enforceAppLockCalls, 0);
        controller.dispose();
      });
    });

    test('does not schedule app lock when there is no master password', () {
      fakeAsync((async) {
        settings = AppSettings(
          appLockAfterMins: 5,
          useMasterPassword: false,
        );
        buildController();

        controller.scheduleAutoLock();
        async.elapse(const Duration(minutes: 10));

        expect(enforceAppLockCalls, 0);
        controller.dispose();
      });
    });

    test('fires performAppLock after appLockAfterMins elapses when master password is set', () {
      fakeAsync((async) {
        settings = AppSettings(
          appLockAfterMins: 5,
          useMasterPassword: true,
          masterPasswordHash: 'stored-hash',
        );
        buildController();

        controller.scheduleAutoLock();
        async.elapse(const Duration(minutes: 4, seconds: 59));
        expect(enforceAppLockCalls, 0);

        async.elapse(const Duration(seconds: 1));
        expect(enforceAppLockCalls, 1);
        expect(lockAllMountedContainersCalls, 0); // Vault lock is independent

        controller.dispose();
      });
    });

    test('app lock and vault lock timers fire independently on their configured timeouts', () {
      fakeAsync((async) {
        settings = AppSettings(
          autoLockMins: 2,
          lockContainersOnScreenLock: true,
          appLockAfterMins: 5,
          useMasterPassword: true,
          masterPasswordHash: 'h',
        );
        buildController();

        controller.scheduleAutoLock();

        // 2 minutes: vault lock unmounts containers
        async.elapse(const Duration(minutes: 2));
        expect(lockAllMountedContainersCalls, 1);
        expect(enforceAppLockCalls, 0);

        // 3 more minutes (5 min total): app gate locks
        async.elapse(const Duration(minutes: 3));
        expect(lockAllMountedContainersCalls, 1);
        expect(enforceAppLockCalls, 1);

        controller.dispose();
      });
    });

    test('a second call to scheduleAutoLock resets the timers instead of stacking', () {
      fakeAsync((async) {
        settings = AppSettings(
          appLockAfterMins: 5,
          useMasterPassword: true,
          masterPasswordHash: 'h',
        );
        buildController();

        controller.scheduleAutoLock();
        async.elapse(const Duration(minutes: 3));
        controller.scheduleAutoLock(); // resets timer
        async.elapse(const Duration(minutes: 3));
        expect(enforceAppLockCalls, 0);

        async.elapse(const Duration(minutes: 2));
        expect(enforceAppLockCalls, 1);

        controller.dispose();
      });
    });

    test('setMediaPlaying suppresses inactivity timers', () {
      fakeAsync((async) {
        settings = AppSettings(
          appLockAfterMins: 5,
          useMasterPassword: true,
          masterPasswordHash: 'h',
        );
        buildController();

        controller.scheduleAutoLock();
        controller.setMediaPlaying(true);
        async.elapse(const Duration(minutes: 10));
        expect(enforceAppLockCalls, 0);

        controller.setMediaPlaying(false);
        async.elapse(const Duration(minutes: 5));
        expect(enforceAppLockCalls, 1);

        controller.dispose();
      });
    });
  });

  group('performAppLock, performVaultLock, performAutoLock', () {
    test('performAppLock locks app gate when master password is set', () {
      settings = AppSettings(
        useMasterPassword: true,
        masterPasswordHash: 'h',
      );
      buildController();

      controller.performAppLock();

      expect(enforceAppLockCalls, 1);
      expect(controller.isAppLocked, isTrue);
    });

    test('performAppLock skips duplicate call when already locked', () {
      settings = AppSettings(
        useMasterPassword: true,
        masterPasswordHash: 'h',
      );
      buildController();

      controller.performAppLock();
      controller.performAppLock();

      expect(enforceAppLockCalls, 1);
    });

    test('performAppLock does nothing without master password', () {
      settings = AppSettings(
        useMasterPassword: false,
      );
      buildController();

      controller.performAppLock();

      expect(enforceAppLockCalls, 0);
      expect(controller.isAppLocked, isFalse);
    });

    test('performVaultLock unmounts open containers directly', () async {
      settings = AppSettings();
      buildController();

      await controller.performVaultLock();

      expect(lockAllMountedContainersCalls, 1);
      expect(enforceAppLockCalls, 0);
    });

    test('performAutoLock fires both performAppLock and performVaultLock', () async {
      settings = AppSettings(
        useMasterPassword: true,
        masterPasswordHash: 'h',
      );
      buildController();

      await controller.performAutoLock();

      expect(enforceAppLockCalls, 1);
      expect(lockAllMountedContainersCalls, 1);
    });
  });

  group('handleAppLifecycleState', () {
    test('resuming shortly after pausing reschedules app lock instead of locking immediately', () {
      fakeAsync((async) {
        settings = AppSettings(
          appLockAfterMins: 10,
          useMasterPassword: true,
          masterPasswordHash: 'h',
        );
        var fakeNow = DateTime(2024);
        now = () => fakeNow;
        buildController();

        controller.handleAppLifecycleState(AppLifecycleState.paused);
        fakeNow = fakeNow.add(const Duration(minutes: 2));
        async.elapse(const Duration(minutes: 2));
        controller.handleAppLifecycleState(AppLifecycleState.resumed);

        expect(enforceAppLockCalls, 0);

        async.elapse(const Duration(minutes: 9, seconds: 59));
        expect(enforceAppLockCalls, 0);
        async.elapse(const Duration(seconds: 1));
        expect(enforceAppLockCalls, 1);

        controller.dispose();
      });
    });

    test('resuming after being away longer than appLockAfterMins locks app gate immediately', () {
      fakeAsync((async) {
        settings = AppSettings(
          appLockAfterMins: 10,
          useMasterPassword: true,
          masterPasswordHash: 'h',
        );
        var fakeNow = DateTime(2024);
        now = () => fakeNow;
        buildController();

        controller.handleAppLifecycleState(AppLifecycleState.paused);
        fakeNow = fakeNow.add(const Duration(minutes: 15));
        async.elapse(const Duration(minutes: 15));
        controller.handleAppLifecycleState(AppLifecycleState.resumed);

        expect(enforceAppLockCalls, 1);
        controller.dispose();
      });
    });

    test('resuming after being away longer than autoLockMins unmounts containers immediately', () {
      fakeAsync((async) {
        settings = AppSettings(
          autoLockMins: 10,
          lockContainersOnScreenLock: true,
        );
        var fakeNow = DateTime(2024);
        now = () => fakeNow;
        buildController();

        controller.handleAppLifecycleState(AppLifecycleState.paused);
        fakeNow = fakeNow.add(const Duration(minutes: 15));
        async.elapse(const Duration(minutes: 15));
        controller.handleAppLifecycleState(AppLifecycleState.resumed);

        expect(lockAllMountedContainersCalls, 1);
        expect(enforceAppLockCalls, 0);
        controller.dispose();
      });
    });

    test('app lock and vault lock respect different away thresholds on resume', () {
      fakeAsync((async) {
        settings = AppSettings(
          appLockAfterMins: 5,
          useMasterPassword: true,
          masterPasswordHash: 'h',
          autoLockMins: 15,
          lockContainersOnScreenLock: true,
        );
        var fakeNow = DateTime(2024);
        now = () => fakeNow;
        buildController();

        controller.handleAppLifecycleState(AppLifecycleState.paused);
        fakeNow = fakeNow.add(const Duration(minutes: 8));
        async.elapse(const Duration(minutes: 8));
        controller.handleAppLifecycleState(AppLifecycleState.resumed);

        // 8 min away >= 5 min app lock, but < 15 min vault lock:
        expect(enforceAppLockCalls, 1);
        expect(lockAllMountedContainersCalls, 0);

        controller.dispose();
      });
    });

    test('inactive lifecycle state is ignored for background duration', () {
      fakeAsync((async) {
        settings = AppSettings(
          appLockAfterMins: 5,
          useMasterPassword: true,
          masterPasswordHash: 'h',
        );
        var fakeNow = DateTime(2024);
        now = () => fakeNow;
        buildController();

        controller.handleAppLifecycleState(AppLifecycleState.inactive);
        fakeNow = fakeNow.add(const Duration(minutes: 10));
        async.elapse(const Duration(minutes: 10));
        controller.handleAppLifecycleState(AppLifecycleState.resumed);

        expect(enforceAppLockCalls, 0);
        controller.dispose();
      });
    });
  });

  group('handleScreenOff', () {
    test('locks app gate immediately when lockAppOnScreenLock is true and appLockAfterMins is 0 ("Immediately")', () {
      settings = AppSettings(
        useMasterPassword: true,
        masterPasswordHash: 'h',
        lockAppOnScreenLock: true,
        appLockAfterMins: 0,
        lockContainersOnScreenLock: false, // Prevents default vault lock on screen off
      );
      buildController();

      controller.handleScreenOff();

      expect(enforceAppLockCalls, 1);
      expect(lockAllMountedContainersCalls, 0);
    });

    test('locks containers immediately when lockContainersOnScreenLock is true and autoLockMins is 0 ("Immediately")', () {
      settings = AppSettings(
        lockContainersOnScreenLock: true,
        autoLockMins: 0,
      );
      buildController();

      controller.handleScreenOff();

      expect(lockAllMountedContainersCalls, 1);
      expect(enforceAppLockCalls, 0);
    });

    test('locks both app gate and containers immediately when both are set to 0', () {
      settings = AppSettings(
        useMasterPassword: true,
        masterPasswordHash: 'h',
        lockAppOnScreenLock: true,
        appLockAfterMins: 0,
        lockContainersOnScreenLock: true,
        autoLockMins: 0,
      );
      buildController();

      controller.handleScreenOff();

      expect(enforceAppLockCalls, 1);
      expect(lockAllMountedContainersCalls, 1);
    });

    test('does nothing on screen off when lock options are disabled', () {
      settings = AppSettings(
        useMasterPassword: true,
        masterPasswordHash: 'h',
        lockAppOnScreenLock: false,
        lockContainersOnScreenLock: false,
      );
      buildController();

      controller.handleScreenOff();

      expect(enforceAppLockCalls, 0);
      expect(lockAllMountedContainersCalls, 0);
    });

    test('waits for appLockAfterMins when a real timeout is configured on screen off', () {
      fakeAsync((async) {
        settings = AppSettings(
          useMasterPassword: true,
          masterPasswordHash: 'h',
          lockAppOnScreenLock: true,
          appLockAfterMins: 30,
        );
        buildController();

        controller.handleScreenOff();

        async.elapse(const Duration(minutes: 29, seconds: 59));
        expect(enforceAppLockCalls, 0);

        async.elapse(const Duration(seconds: 1));
        expect(enforceAppLockCalls, 1);

        controller.dispose();
      });
    });

    test('waits for autoLockMins when a real timeout is configured for vault lock on screen off', () {
      fakeAsync((async) {
        settings = AppSettings(
          lockContainersOnScreenLock: true,
          autoLockMins: 60,
        );
        buildController();

        controller.handleScreenOff();

        async.elapse(const Duration(minutes: 59, seconds: 59));
        expect(lockAllMountedContainersCalls, 0);

        async.elapse(const Duration(seconds: 1));
        expect(lockAllMountedContainersCalls, 1);

        controller.dispose();
      });
    });

    test('repeated handleScreenOff calls restart countdowns instead of stacking', () {
      fakeAsync((async) {
        settings = AppSettings(
          lockContainersOnScreenLock: true,
          autoLockMins: 10,
        );
        buildController();

        controller.handleScreenOff();
        async.elapse(const Duration(minutes: 6));
        controller.handleScreenOff();
        async.elapse(const Duration(minutes: 6));
        expect(lockAllMountedContainersCalls, 0);

        async.elapse(const Duration(minutes: 4));
        expect(lockAllMountedContainersCalls, 1);

        controller.dispose();
      });
    });

    test('screen-off lock flags prevent duplicate locking on immediate app resume', () {
      fakeAsync((async) {
        settings = AppSettings(
          useMasterPassword: true,
          masterPasswordHash: 'h',
          lockAppOnScreenLock: true,
          appLockAfterMins: 0,
          lockContainersOnScreenLock: true,
          autoLockMins: 0,
        );
        var fakeNow = DateTime(2024);
        now = () => fakeNow;
        buildController();

        controller.handleScreenOff();
        expect(enforceAppLockCalls, 1);
        expect(lockAllMountedContainersCalls, 1);

        // Resume after screen off: should not duplicate
        controller.handleAppLifecycleState(AppLifecycleState.paused);
        fakeNow = fakeNow.add(const Duration(seconds: 5));
        async.elapse(const Duration(seconds: 5));
        controller.handleAppLifecycleState(AppLifecycleState.resumed);

        expect(enforceAppLockCalls, 1);
        expect(lockAllMountedContainersCalls, 1);

        controller.dispose();
      });
    });
  });

  group('notifyAppUnlocked, dispose, and suppression', () {
    test('notifyAppUnlocked resets isAppLocked and reschedules auto-lock', () {
      fakeAsync((async) {
        settings = AppSettings(
          useMasterPassword: true,
          masterPasswordHash: 'h',
          appLockAfterMins: 5,
        );
        buildController();

        controller.performAppLock();
        expect(controller.isAppLocked, isTrue);

        controller.notifyAppUnlocked();
        expect(controller.isAppLocked, isFalse);

        async.elapse(const Duration(minutes: 5));
        expect(enforceAppLockCalls, 2); // 1 initial + 1 rescheduled

        controller.dispose();
      });
    });

    test('dispose cancels pending timers', () {
      fakeAsync((async) {
        settings = AppSettings(
          useMasterPassword: true,
          masterPasswordHash: 'h',
          appLockAfterMins: 5,
          autoLockMins: 5,
          lockContainersOnScreenLock: true,
        );
        buildController();

        controller.scheduleAutoLock();
        controller.dispose();
        async.elapse(const Duration(minutes: 10));

        expect(enforceAppLockCalls, 0);
        expect(lockAllMountedContainersCalls, 0);
      });
    });

    test('suppressLock suppresses lifecycle locking', () {
      fakeAsync((async) {
        settings = AppSettings(
          useMasterPassword: true,
          masterPasswordHash: 'h',
          appLockAfterMins: 0,
        );
        var fakeNow = DateTime(2024);
        now = () => fakeNow;
        buildController();

        controller.suppressLock();
        expect(controller.isLockSuppressed, isTrue);

        controller.handleAppLifecycleState(AppLifecycleState.paused);
        fakeNow = fakeNow.add(const Duration(minutes: 5));
        async.elapse(const Duration(minutes: 5));
        controller.handleAppLifecycleState(AppLifecycleState.resumed);

        expect(enforceAppLockCalls, 0);

        controller.unsuppressLock();
        expect(controller.isLockSuppressed, isFalse);

        controller.dispose();
      });
    });

    test('withLockSuppression suppresses auto-lock during async operation', () async {
      await controller.withLockSuppression(() async {
        expect(controller.isLockSuppressed, isTrue);
      });
      expect(controller.isLockSuppressed, isFalse);
    });
  });
}