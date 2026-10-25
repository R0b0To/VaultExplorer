import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/services/session_lock_controller.dart';

void main() {
  late AppSettings settings;
  late int enforceAppLockCalls;
  late int lockAllMountedContainersCalls;
  late int lockImmediateOverrideContainersCalls;
  late int lockScreenLockOnlyContainersCalls;
  late SessionLockController controller;
  DateTime Function() now = DateTime.now;

  void buildController({
    bool withImmediateOverrideCallback = true,
    bool withScreenLockOnlyCallback = true,
  }) {
    enforceAppLockCalls = 0;
    lockAllMountedContainersCalls = 0;
    lockImmediateOverrideContainersCalls = 0;
    lockScreenLockOnlyContainersCalls = 0;
    controller = SessionLockController(now: now)
      ..configure(
        settings: () => settings,
        lockAllMountedContainers: () async {
          lockAllMountedContainersCalls++;
        },
        enforceAppLock: () {
          enforceAppLockCalls++;
        },
        lockImmediateOverrideContainers: withImmediateOverrideCallback
            ? () async {
                lockImmediateOverrideContainersCalls++;
              }
            : null,
        lockScreenLockOnlyContainers: withScreenLockOnlyCallback
            ? () async {
                lockScreenLockOnlyContainersCalls++;
              }
            : null,
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

  group('background media playback', () {
    test('returning after a long away period does not vault-lock while media is still playing', () {
      fakeAsync((async) {
        settings = AppSettings(autoLockMins: 5, lockContainersOnScreenLock: true);
        var fakeNow = DateTime(2024);
        now = () => fakeNow;
        buildController();

        controller.setMediaPlaying(true);
        controller.handleAppLifecycleState(AppLifecycleState.paused);
        fakeNow = fakeNow.add(const Duration(minutes: 30));
        async.elapse(const Duration(minutes: 30));
        controller.handleAppLifecycleState(AppLifecycleState.resumed);

        expect(lockAllMountedContainersCalls, 0);

        controller.dispose();
      });
    });

    test('vault inactivity lock re-arms once background playback stops', () {
      fakeAsync((async) {
        settings = AppSettings(autoLockMins: 5, lockContainersOnScreenLock: true);
        var fakeNow = DateTime(2024);
        now = () => fakeNow;
        buildController();

        controller.setMediaPlaying(true);
        controller.handleAppLifecycleState(AppLifecycleState.paused);
        fakeNow = fakeNow.add(const Duration(minutes: 30));
        async.elapse(const Duration(minutes: 30));
        controller.handleAppLifecycleState(AppLifecycleState.resumed);
        expect(lockAllMountedContainersCalls, 0);

        controller.setMediaPlaying(false);
        async.elapse(const Duration(minutes: 4, seconds: 59));
        expect(lockAllMountedContainersCalls, 0);
        async.elapse(const Duration(seconds: 1));
        expect(lockAllMountedContainersCalls, 1);

        controller.dispose();
      });
    });

    test('returning after a long away period still vault-locks when nothing is playing', () {
      fakeAsync((async) {
        settings = AppSettings(autoLockMins: 5, lockContainersOnScreenLock: true);
        var fakeNow = DateTime(2024);
        now = () => fakeNow;
        buildController();

        controller.handleAppLifecycleState(AppLifecycleState.paused);
        fakeNow = fakeNow.add(const Duration(minutes: 30));
        async.elapse(const Duration(minutes: 30));
        controller.handleAppLifecycleState(AppLifecycleState.resumed);

        expect(lockAllMountedContainersCalls, 1);

        controller.dispose();
      });
    });

    test('"Immediately" (autoLockMins 0) still vault-locks on return even while media plays', () {
      fakeAsync((async) {
        settings = AppSettings(autoLockMins: 0, lockContainersOnScreenLock: true);
        var fakeNow = DateTime(2024);
        now = () => fakeNow;
        buildController();

        controller.setMediaPlaying(true);
        controller.handleAppLifecycleState(AppLifecycleState.paused);
        fakeNow = fakeNow.add(const Duration(minutes: 1));
        async.elapse(const Duration(minutes: 1));
        controller.handleAppLifecycleState(AppLifecycleState.resumed);

        expect(lockAllMountedContainersCalls, 1);

        controller.dispose();
      });
    });

    test('playing media does not stop the app-lock gate from applying on return', () {
      fakeAsync((async) {
        settings = AppSettings(
          appLockAfterMins: 5,
          useMasterPassword: true,
          masterPasswordHash: 'h',
        );
        var fakeNow = DateTime(2024);
        now = () => fakeNow;
        buildController();

        controller.setMediaPlaying(true);
        controller.handleAppLifecycleState(AppLifecycleState.paused);
        fakeNow = fakeNow.add(const Duration(minutes: 30));
        async.elapse(const Duration(minutes: 30));
        controller.handleAppLifecycleState(AppLifecycleState.resumed);

        expect(enforceAppLockCalls, 1);

        controller.dispose();
      });
    });
  });

  // pauseVaultAutoLock/resumeVaultAutoLock are held by the camera and audio
  // capture screens for the length of a recording: no *automatic* vault lock
  // (inactivity timer, return from the background, "Immediately", screen-off,
  // per-container overrides) may unmount the vault -- and so force-stop the
  // recording -- while one runs. The app-lock gate is deliberately unaffected:
  // it leaves mounted containers alone.
  group('recording hold (pauseVaultAutoLock)', () {
    test('pausing cancels the armed vault timer and activity does not re-arm it', () {
      fakeAsync((async) {
        settings = AppSettings(autoLockMins: 5, lockContainersOnScreenLock: true);
        buildController();

        controller.scheduleAutoLock();
        async.elapse(const Duration(minutes: 4));
        controller.pauseVaultAutoLock();
        expect(controller.isVaultAutoLockPaused, isTrue);

        async.elapse(const Duration(minutes: 30));
        expect(lockAllMountedContainersCalls, 0);

        // A tap anywhere in the app re-arms the timers -- not this one.
        controller.scheduleAutoLock();
        async.elapse(const Duration(minutes: 30));
        expect(lockAllMountedContainersCalls, 0);

        controller.dispose();
      });
    });

    test('timer re-arms with a fresh full timeout once the hold is released', () {
      fakeAsync((async) {
        settings = AppSettings(autoLockMins: 5, lockContainersOnScreenLock: true);
        buildController();

        controller.scheduleAutoLock();
        controller.pauseVaultAutoLock();
        async.elapse(const Duration(minutes: 30));
        controller.resumeVaultAutoLock();
        expect(controller.isVaultAutoLockPaused, isFalse);

        async.elapse(const Duration(minutes: 4, seconds: 59));
        expect(lockAllMountedContainersCalls, 0);
        async.elapse(const Duration(seconds: 1));
        expect(lockAllMountedContainersCalls, 1);

        controller.dispose();
      });
    });

    test('holds nest: the timer only re-arms after every hold is released', () {
      fakeAsync((async) {
        settings = AppSettings(autoLockMins: 5, lockContainersOnScreenLock: true);
        buildController();

        controller.pauseVaultAutoLock();
        controller.pauseVaultAutoLock();
        controller.resumeVaultAutoLock();
        expect(controller.isVaultAutoLockPaused, isTrue);

        controller.scheduleAutoLock();
        async.elapse(const Duration(minutes: 30));
        expect(lockAllMountedContainersCalls, 0);

        controller.resumeVaultAutoLock();
        expect(controller.isVaultAutoLockPaused, isFalse);
        async.elapse(const Duration(minutes: 5));
        expect(lockAllMountedContainersCalls, 1);

        controller.dispose();
      });
    });

    test('an unbalanced resumeVaultAutoLock is a no-op', () {
      fakeAsync((async) {
        settings = AppSettings(autoLockMins: 5, lockContainersOnScreenLock: true);
        buildController();

        controller.resumeVaultAutoLock();
        controller.pauseVaultAutoLock();
        expect(controller.isVaultAutoLockPaused, isTrue);

        controller.dispose();
      });
    });

    test('the app-lock gate still applies while the hold is active', () {
      fakeAsync((async) {
        settings = AppSettings(
          autoLockMins: 5,
          lockContainersOnScreenLock: true,
          appLockAfterMins: 5,
          useMasterPassword: true,
          masterPasswordHash: 'h',
        );
        buildController();

        controller.pauseVaultAutoLock();
        controller.scheduleAutoLock();
        async.elapse(const Duration(minutes: 5));

        // Like the lock screen: the gate comes up, the vault (and the
        // recording running in it) is left alone.
        expect(enforceAppLockCalls, 1);
        expect(lockAllMountedContainersCalls, 0);

        controller.dispose();
      });
    });

    test('performVaultLock does nothing while held and works again once released', () async {
      settings = AppSettings(autoLockMins: 5, lockContainersOnScreenLock: true);
      buildController();

      controller.pauseVaultAutoLock();
      await controller.performVaultLock();
      expect(lockAllMountedContainersCalls, 0);

      controller.resumeVaultAutoLock();
      await controller.performVaultLock();
      expect(lockAllMountedContainersCalls, 1);

      controller.dispose();
    });

    test('screen-off "Immediately" does not lock while held, and does again once released', () {
      fakeAsync((async) {
        settings = AppSettings(
          autoLockMins: 0,
          lockContainersOnScreenLock: true,
        );
        buildController();

        controller.pauseVaultAutoLock();
        controller.handleScreenOff();
        expect(lockAllMountedContainersCalls, 0);

        controller.resumeVaultAutoLock();
        controller.handleScreenOff();
        expect(lockAllMountedContainersCalls, 1);

        controller.dispose();
      });
    });

    test('screen-off "Screen Lock Only" does not lock while held', () {
      fakeAsync((async) {
        settings = AppSettings(
          autoLockScreenLockOnly: true,
          lockContainersOnScreenLock: true,
        );
        buildController();

        controller.pauseVaultAutoLock();
        controller.handleScreenOff();

        expect(lockAllMountedContainersCalls, 0);

        controller.dispose();
      });
    });

    test('per-container "Immediately" and "Screen Lock Only" overrides do not fire on screen-off while held', () {
      fakeAsync((async) {
        settings = AppSettings(autoLockMins: 5, lockContainersOnScreenLock: true);
        buildController();

        controller.pauseVaultAutoLock();
        controller.handleScreenOff();
        expect(lockImmediateOverrideContainersCalls, 0);
        expect(lockScreenLockOnlyContainersCalls, 0);

        controller.resumeVaultAutoLock();
        controller.handleScreenOff();
        expect(lockImmediateOverrideContainersCalls, 1);
        expect(lockScreenLockOnlyContainersCalls, 1);

        controller.dispose();
      });
    });

    test('a per-container "Immediately" override does not fire on return from the background while held', () {
      fakeAsync((async) {
        settings = AppSettings(autoLockMins: 5, lockContainersOnScreenLock: true);
        var fakeNow = DateTime(2024);
        now = () => fakeNow;
        buildController();

        controller.pauseVaultAutoLock();
        controller.handleAppLifecycleState(AppLifecycleState.paused);
        fakeNow = fakeNow.add(const Duration(minutes: 1));
        controller.handleAppLifecycleState(AppLifecycleState.resumed);
        expect(lockImmediateOverrideContainersCalls, 0);

        // Same flow once the recording is over: the override applies again.
        controller.resumeVaultAutoLock();
        controller.handleAppLifecycleState(AppLifecycleState.paused);
        fakeNow = fakeNow.add(const Duration(minutes: 1));
        controller.handleAppLifecycleState(AppLifecycleState.resumed);
        expect(lockImmediateOverrideContainersCalls, 1);

        controller.dispose();
      });
    });

    test('a screen-off countdown (timed autoLockMins) does not fire while held', () {
      fakeAsync((async) {
        settings = AppSettings(autoLockMins: 5, lockContainersOnScreenLock: true);
        buildController();

        controller.pauseVaultAutoLock();
        controller.handleScreenOff();
        async.elapse(const Duration(minutes: 30));

        expect(lockAllMountedContainersCalls, 0);

        controller.dispose();
      });
    });

    test('returning after a long away period does not vault-lock while the hold is active', () {
      fakeAsync((async) {
        settings = AppSettings(autoLockMins: 5, lockContainersOnScreenLock: true);
        var fakeNow = DateTime(2024);
        now = () => fakeNow;
        buildController();

        controller.pauseVaultAutoLock();
        controller.handleAppLifecycleState(AppLifecycleState.paused);
        fakeNow = fakeNow.add(const Duration(minutes: 30));
        async.elapse(const Duration(minutes: 30));
        controller.handleAppLifecycleState(AppLifecycleState.resumed);

        expect(lockAllMountedContainersCalls, 0);

        controller.dispose();
      });
    });

    test('vault inactivity lock re-arms once the hold is released after returning', () {
      fakeAsync((async) {
        settings = AppSettings(autoLockMins: 5, lockContainersOnScreenLock: true);
        var fakeNow = DateTime(2024);
        now = () => fakeNow;
        buildController();

        controller.pauseVaultAutoLock();
        controller.handleAppLifecycleState(AppLifecycleState.paused);
        fakeNow = fakeNow.add(const Duration(minutes: 30));
        async.elapse(const Duration(minutes: 30));
        controller.handleAppLifecycleState(AppLifecycleState.resumed);
        expect(lockAllMountedContainersCalls, 0);

        controller.resumeVaultAutoLock();
        async.elapse(const Duration(minutes: 4, seconds: 59));
        expect(lockAllMountedContainersCalls, 0);
        async.elapse(const Duration(seconds: 1));
        expect(lockAllMountedContainersCalls, 1);

        controller.dispose();
      });
    });

    test('"Immediately" (autoLockMins 0) does not vault-lock on return while the hold is active', () {
      fakeAsync((async) {
        settings = AppSettings(autoLockMins: 0, lockContainersOnScreenLock: true);
        var fakeNow = DateTime(2024);
        now = () => fakeNow;
        buildController();

        controller.pauseVaultAutoLock();
        controller.handleAppLifecycleState(AppLifecycleState.paused);
        fakeNow = fakeNow.add(const Duration(minutes: 1));
        async.elapse(const Duration(minutes: 1));
        controller.handleAppLifecycleState(AppLifecycleState.resumed);

        expect(lockAllMountedContainersCalls, 0);

        controller.dispose();
      });
    });

    test('the app-lock gate still applies on return while the hold is active', () {
      fakeAsync((async) {
        settings = AppSettings(
          autoLockMins: 5,
          lockContainersOnScreenLock: true,
          appLockAfterMins: 5,
          useMasterPassword: true,
          masterPasswordHash: 'h',
        );
        var fakeNow = DateTime(2024);
        now = () => fakeNow;
        buildController();

        controller.pauseVaultAutoLock();
        controller.handleAppLifecycleState(AppLifecycleState.paused);
        fakeNow = fakeNow.add(const Duration(minutes: 30));
        async.elapse(const Duration(minutes: 30));
        controller.handleAppLifecycleState(AppLifecycleState.resumed);

        expect(enforceAppLockCalls, 1);
        expect(lockAllMountedContainersCalls, 0);

        controller.dispose();
      });
    });

    test('a screen-off lock skipped while held does not make the next return skip its own check', () {
      fakeAsync((async) {
        settings = AppSettings(autoLockMins: 0, lockContainersOnScreenLock: true);
        var fakeNow = DateTime(2024);
        now = () => fakeNow;
        buildController();

        controller.pauseVaultAutoLock();
        controller.handleAppLifecycleState(AppLifecycleState.paused);
        controller.handleScreenOff(); // skipped: a recording is running
        expect(lockAllMountedContainersCalls, 0);

        // The recording ends while the app is still away; on return the usual
        // "Immediately" lock applies. (If the skipped screen-off had been
        // recorded as a completed lock, this check would be skipped too.)
        controller.resumeVaultAutoLock();
        fakeNow = fakeNow.add(const Duration(minutes: 1));
        controller.handleAppLifecycleState(AppLifecycleState.resumed);

        expect(lockAllMountedContainersCalls, 1);

        controller.dispose();
      });
    });

    test('hold released while backgrounded: idle time counts from the release, not from backgrounding', () {
      fakeAsync((async) {
        settings = AppSettings(autoLockMins: 5, lockContainersOnScreenLock: true);
        var fakeNow = DateTime(2024);
        now = () => fakeNow;
        buildController();

        // A long recording runs with the app in the background...
        controller.pauseVaultAutoLock();
        controller.handleAppLifecycleState(AppLifecycleState.paused);
        fakeNow = fakeNow.add(const Duration(minutes: 30));
        async.elapse(const Duration(minutes: 30));

        // ...and is stopped from its notification.
        controller.resumeVaultAutoLock();
        fakeNow = fakeNow.add(const Duration(minutes: 2));
        async.elapse(const Duration(minutes: 2));

        // Back in the app 2 minutes after the stop: 32 minutes away overall,
        // but the vault was only idle for 2 -- it must not lock.
        controller.handleAppLifecycleState(AppLifecycleState.resumed);
        expect(lockAllMountedContainersCalls, 0);

        // A normal fresh idle timeout is armed from here.
        async.elapse(const Duration(minutes: 4, seconds: 59));
        expect(lockAllMountedContainersCalls, 0);
        async.elapse(const Duration(seconds: 1));
        expect(lockAllMountedContainersCalls, 1);

        controller.dispose();
      });
    });

    test('hold released while backgrounded: still vault-locks if idle past the timeout after the release', () {
      fakeAsync((async) {
        settings = AppSettings(autoLockMins: 5, lockContainersOnScreenLock: true);
        var fakeNow = DateTime(2024);
        now = () => fakeNow;
        buildController();

        controller.pauseVaultAutoLock();
        controller.handleAppLifecycleState(AppLifecycleState.paused);
        fakeNow = fakeNow.add(const Duration(minutes: 30));
        controller.resumeVaultAutoLock();

        // Only the clock moves (as if the process was frozen), so this
        // exercises the check on return rather than the re-armed timer.
        fakeNow = fakeNow.add(const Duration(minutes: 6));
        controller.handleAppLifecycleState(AppLifecycleState.resumed);

        expect(lockAllMountedContainersCalls, 1);

        controller.dispose();
      });
    });

    test('a hold released in the foreground does not affect a later background period', () {
      fakeAsync((async) {
        settings = AppSettings(autoLockMins: 5, lockContainersOnScreenLock: true);
        var fakeNow = DateTime(2024);
        now = () => fakeNow;
        buildController();

        // Recording starts and ends entirely in the foreground.
        controller.pauseVaultAutoLock();
        fakeNow = fakeNow.add(const Duration(minutes: 30));
        async.elapse(const Duration(minutes: 30));
        controller.resumeVaultAutoLock();

        // Later the app is backgrounded for longer than the timeout: normal
        // behavior, the vault locks on return.
        controller.handleAppLifecycleState(AppLifecycleState.paused);
        fakeNow = fakeNow.add(const Duration(minutes: 10));
        async.elapse(const Duration(minutes: 10));
        controller.handleAppLifecycleState(AppLifecycleState.resumed);

        expect(lockAllMountedContainersCalls, 1);

        controller.dispose();
      });
    });

    test('a release time from an earlier background period is not reused', () {
      fakeAsync((async) {
        settings = AppSettings(autoLockMins: 5, lockContainersOnScreenLock: true);
        var fakeNow = DateTime(2024);
        now = () => fakeNow;
        buildController();

        // First background period: hold released while away, then back
        // shortly after -- no lock.
        controller.pauseVaultAutoLock();
        controller.handleAppLifecycleState(AppLifecycleState.paused);
        fakeNow = fakeNow.add(const Duration(minutes: 30));
        controller.resumeVaultAutoLock();
        fakeNow = fakeNow.add(const Duration(minutes: 1));
        controller.handleAppLifecycleState(AppLifecycleState.resumed);
        expect(lockAllMountedContainersCalls, 0);

        // Second, plain background period longer than the timeout: the first
        // period's release time must not shorten it.
        controller.handleAppLifecycleState(AppLifecycleState.paused);
        fakeNow = fakeNow.add(const Duration(minutes: 10));
        controller.handleAppLifecycleState(AppLifecycleState.resumed);
        expect(lockAllMountedContainersCalls, 1);

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

  group('lockImmediateOverrideContainers', () {
    test('handleScreenOff invokes it regardless of the screen-lock toggles', () {
      settings = AppSettings(
        lockAppOnScreenLock: false,
        lockContainersOnScreenLock: false,
      );
      buildController();

      controller.handleScreenOff();

      expect(lockImmediateOverrideContainersCalls, 1);
      // The two gated sweeps stay untouched -- this is a separate, always-on action.
      expect(enforceAppLockCalls, 0);
      expect(lockAllMountedContainersCalls, 0);
    });

    test('handleScreenOff does not invoke it while lock is suppressed', () {
      settings = AppSettings();
      buildController();
      controller.suppressLock();

      controller.handleScreenOff();

      expect(lockImmediateOverrideContainersCalls, 0);
    });

    test('resuming after a genuine background period invokes it once, regardless of away duration', () {
      fakeAsync((async) {
        settings = AppSettings(lockContainersOnScreenLock: false);
        var fakeNow = DateTime(2024);
        now = () => fakeNow;
        buildController();

        controller.handleAppLifecycleState(AppLifecycleState.paused);
        fakeNow = fakeNow.add(const Duration(seconds: 1));
        async.elapse(const Duration(seconds: 1));
        controller.handleAppLifecycleState(AppLifecycleState.resumed);

        // Away for only 1 second -- shorter than any real timeout -- but
        // "Immediately" containers don't wait for one; see
        // SessionLockController._lockImmediateOverrides.
        expect(lockImmediateOverrideContainersCalls, 1);
        expect(lockAllMountedContainersCalls, 0);

        controller.dispose();
      });
    });

    test('does not invoke it on resume with no prior background period', () {
      settings = AppSettings();
      buildController();

      controller.handleAppLifecycleState(AppLifecycleState.resumed);

      expect(lockImmediateOverrideContainersCalls, 0);
    });

    test('does not invoke it for a transient "inactive" state (no real backgrounding)', () {
      fakeAsync((async) {
        settings = AppSettings();
        var fakeNow = DateTime(2024);
        now = () => fakeNow;
        buildController();

        controller.handleAppLifecycleState(AppLifecycleState.inactive);
        fakeNow = fakeNow.add(const Duration(minutes: 10));
        async.elapse(const Duration(minutes: 10));
        controller.handleAppLifecycleState(AppLifecycleState.resumed);

        expect(lockImmediateOverrideContainersCalls, 0);
        controller.dispose();
      });
    });

    test('does not invoke it on resume while lock is suppressed', () {
      fakeAsync((async) {
        settings = AppSettings();
        var fakeNow = DateTime(2024);
        now = () => fakeNow;
        buildController();

        controller.suppressLock();
        controller.handleAppLifecycleState(AppLifecycleState.paused);
        fakeNow = fakeNow.add(const Duration(minutes: 5));
        async.elapse(const Duration(minutes: 5));
        controller.handleAppLifecycleState(AppLifecycleState.resumed);

        expect(lockImmediateOverrideContainersCalls, 0);

        controller.unsuppressLock();
        controller.dispose();
      });
    });

    test('a caller that never supplies the callback is unaffected (it is optional)', () {
      settings = AppSettings(lockContainersOnScreenLock: true, autoLockMins: 0);
      buildController(withImmediateOverrideCallback: false);

      expect(() => controller.handleScreenOff(), returnsNormally);
      expect(lockAllMountedContainersCalls, 1);
    });
  });

  group('lockScreenLockOnlyContainers (per-container Screen Lock Only)', () {
    test('handleScreenOff invokes it regardless of the screen-lock toggles', () {
      settings = AppSettings(
        lockAppOnScreenLock: false,
        lockContainersOnScreenLock: false,
      );
      buildController();

      controller.handleScreenOff();

      expect(lockScreenLockOnlyContainersCalls, 1);
      // The two gated sweeps stay untouched -- this is a separate, always-on action.
      expect(enforceAppLockCalls, 0);
      expect(lockAllMountedContainersCalls, 0);
    });

    test('handleScreenOff does not invoke it while lock is suppressed', () {
      settings = AppSettings();
      buildController();
      controller.suppressLock();

      controller.handleScreenOff();

      expect(lockScreenLockOnlyContainersCalls, 0);
    });

    test('resuming after a genuine background period does NOT invoke it, however long the absence', () {
      fakeAsync((async) {
        settings = AppSettings(lockContainersOnScreenLock: false);
        var fakeNow = DateTime(2024);
        now = () => fakeNow;
        buildController();

        controller.handleAppLifecycleState(AppLifecycleState.paused);
        fakeNow = fakeNow.add(const Duration(hours: 3));
        async.elapse(const Duration(hours: 3));
        controller.handleAppLifecycleState(AppLifecycleState.resumed);

        // The whole point of "Screen Lock Only": plain app backgrounding
        // (screen still on) must not lock it. Contrast with
        // lockImmediateOverrideContainers, which does fire here.
        expect(lockScreenLockOnlyContainersCalls, 0);
        expect(lockImmediateOverrideContainersCalls, 1);

        controller.dispose();
      });
    });

    test('backgrounding alone (paused/hidden) does not invoke it', () {
      settings = AppSettings();
      buildController();

      controller.handleAppLifecycleState(AppLifecycleState.paused);
      controller.handleAppLifecycleState(AppLifecycleState.hidden);

      expect(lockScreenLockOnlyContainersCalls, 0);
    });

    test('a genuine screen-off during a background period still invokes it', () {
      fakeAsync((async) {
        settings = AppSettings();
        var fakeNow = DateTime(2024);
        now = () => fakeNow;
        buildController();

        controller.handleAppLifecycleState(AppLifecycleState.paused);
        controller.handleScreenOff();
        fakeNow = fakeNow.add(const Duration(minutes: 1));
        async.elapse(const Duration(minutes: 1));
        controller.handleAppLifecycleState(AppLifecycleState.resumed);

        // Invoked once, by the screen-off -- not a second time by the resume.
        expect(lockScreenLockOnlyContainersCalls, 1);

        controller.dispose();
      });
    });

    test('a caller that never supplies the callback is unaffected (it is optional)', () {
      settings = AppSettings(lockContainersOnScreenLock: true, autoLockMins: 0);
      buildController(withScreenLockOnlyCallback: false);

      expect(() => controller.handleScreenOff(), returnsNormally);
      expect(lockAllMountedContainersCalls, 1);
    });
  });

  group('autoLockScreenLockOnly (global Vault Lock mode)', () {
    test('does not arm the inactivity timer, even with a positive autoLockMins', () {
      fakeAsync((async) {
        settings = AppSettings(
          lockContainersOnScreenLock: true,
          autoLockMins: 5,
          autoLockScreenLockOnly: true,
        );
        buildController();

        controller.scheduleAutoLock();
        async.elapse(const Duration(hours: 1));

        expect(lockAllMountedContainersCalls, 0);
        controller.dispose();
      });
    });

    test('handleScreenOff locks the vault immediately, even with a positive autoLockMins', () {
      fakeAsync((async) {
        settings = AppSettings(
          lockContainersOnScreenLock: true,
          autoLockMins: 5,
          autoLockScreenLockOnly: true,
        );
        buildController();

        controller.handleScreenOff();

        // No countdown to wait out -- unlike a plain autoLockMins: 5, which
        // arms a 5-minute timer here instead.
        expect(lockAllMountedContainersCalls, 1);
        controller.dispose();
      });
    });

    test('resuming after backgrounding does NOT lock the vault, however long the absence', () {
      fakeAsync((async) {
        settings = AppSettings(
          lockContainersOnScreenLock: true,
          autoLockMins: 0,
          autoLockScreenLockOnly: true,
        );
        var fakeNow = DateTime(2024);
        now = () => fakeNow;
        buildController();

        controller.handleAppLifecycleState(AppLifecycleState.paused);
        fakeNow = fakeNow.add(const Duration(hours: 3));
        async.elapse(const Duration(hours: 3));
        controller.handleAppLifecycleState(AppLifecycleState.resumed);

        expect(lockAllMountedContainersCalls, 0);
        controller.dispose();
      });
    });

    test('contrast: plain "Immediately" (autoLockMins 0) DOES lock the vault on the same resume', () {
      fakeAsync((async) {
        settings = AppSettings(
          lockContainersOnScreenLock: true,
          autoLockMins: 0,
          autoLockScreenLockOnly: false,
        );
        var fakeNow = DateTime(2024);
        now = () => fakeNow;
        buildController();

        controller.handleAppLifecycleState(AppLifecycleState.paused);
        fakeNow = fakeNow.add(const Duration(seconds: 1));
        async.elapse(const Duration(seconds: 1));
        controller.handleAppLifecycleState(AppLifecycleState.resumed);

        expect(lockAllMountedContainersCalls, 1);
        controller.dispose();
      });
    });

    test('a genuine screen-off during a background period locks once, and resume does not lock again', () {
      fakeAsync((async) {
        settings = AppSettings(
          lockContainersOnScreenLock: true,
          autoLockMins: 0,
          autoLockScreenLockOnly: true,
        );
        var fakeNow = DateTime(2024);
        now = () => fakeNow;
        buildController();

        controller.handleAppLifecycleState(AppLifecycleState.paused);
        controller.handleScreenOff();
        fakeNow = fakeNow.add(const Duration(minutes: 1));
        async.elapse(const Duration(minutes: 1));
        controller.handleAppLifecycleState(AppLifecycleState.resumed);

        expect(lockAllMountedContainersCalls, 1);
        controller.dispose();
      });
    });

    test('is still gated by the lockContainersOnScreenLock master toggle', () {
      settings = AppSettings(
        lockContainersOnScreenLock: false,
        autoLockScreenLockOnly: true,
      );
      buildController();

      controller.handleScreenOff();

      expect(lockAllMountedContainersCalls, 0);
    });

    test('does not affect App Lock, which has its own independent settings', () {
      settings = AppSettings(
        useMasterPassword: true,
        masterPasswordHash: 'h',
        lockAppOnScreenLock: true,
        appLockAfterMins: 0,
        lockContainersOnScreenLock: true,
        autoLockScreenLockOnly: true,
      );
      buildController();

      controller.handleScreenOff();

      expect(enforceAppLockCalls, 1);
      expect(lockAllMountedContainersCalls, 1);
    });
  });

  group('appLockScreenLockOnly (global App Lock mode)', () {
    AppSettings appLockSettings({
      int appLockAfterMins = 0,
      bool lockAppOnScreenLock = true,
      bool screenLockOnly = true,
      bool useMasterPassword = true,
    }) =>
        AppSettings(
          useMasterPassword: useMasterPassword,
          masterPasswordHash: 'h',
          appLockAfterMins: appLockAfterMins,
          lockAppOnScreenLock: lockAppOnScreenLock,
          appLockScreenLockOnly: screenLockOnly,
        );

    test('does not arm the inactivity timer, even with a positive appLockAfterMins', () {
      fakeAsync((async) {
        settings = appLockSettings(appLockAfterMins: 5);
        buildController();

        controller.scheduleAutoLock();
        async.elapse(const Duration(hours: 1));

        expect(enforceAppLockCalls, 0);
        controller.dispose();
      });
    });

    test('handleScreenOff locks the app immediately, even with a positive appLockAfterMins', () {
      settings = appLockSettings(appLockAfterMins: 5);
      buildController();

      controller.handleScreenOff();

      // No countdown to wait out -- unlike a plain appLockAfterMins: 5,
      // which arms a 5-minute timer here instead.
      expect(enforceAppLockCalls, 1);
    });

    test('handleScreenOff locks the app even when lockAppOnScreenLock is off (the mode implies it)', () {
      settings = appLockSettings(lockAppOnScreenLock: false);
      buildController();

      controller.handleScreenOff();

      expect(enforceAppLockCalls, 1);
    });

    test('resuming after backgrounding does NOT lock the app, however long the absence', () {
      fakeAsync((async) {
        settings = appLockSettings();
        var fakeNow = DateTime(2024);
        now = () => fakeNow;
        buildController();

        controller.handleAppLifecycleState(AppLifecycleState.paused);
        fakeNow = fakeNow.add(const Duration(hours: 3));
        async.elapse(const Duration(hours: 3));
        controller.handleAppLifecycleState(AppLifecycleState.resumed);

        expect(enforceAppLockCalls, 0);
        controller.dispose();
      });
    });

    test('contrast: plain "Immediately" (appLockAfterMins 0) DOES lock the app on the same resume', () {
      fakeAsync((async) {
        settings = appLockSettings(screenLockOnly: false);
        var fakeNow = DateTime(2024);
        now = () => fakeNow;
        buildController();

        controller.handleAppLifecycleState(AppLifecycleState.paused);
        fakeNow = fakeNow.add(const Duration(seconds: 1));
        async.elapse(const Duration(seconds: 1));
        controller.handleAppLifecycleState(AppLifecycleState.resumed);

        expect(enforceAppLockCalls, 1);
        controller.dispose();
      });
    });

    test('a genuine screen-off during a background period locks once, and resume does not lock again', () {
      fakeAsync((async) {
        settings = appLockSettings();
        var fakeNow = DateTime(2024);
        now = () => fakeNow;
        buildController();

        controller.handleAppLifecycleState(AppLifecycleState.paused);
        controller.handleScreenOff();
        fakeNow = fakeNow.add(const Duration(minutes: 1));
        async.elapse(const Duration(minutes: 1));
        controller.handleAppLifecycleState(AppLifecycleState.resumed);

        expect(enforceAppLockCalls, 1);
        controller.dispose();
      });
    });

    test('never locks without a master password configured', () {
      settings = appLockSettings(useMasterPassword: false);
      buildController();

      controller.handleScreenOff();

      expect(enforceAppLockCalls, 0);
    });

    test('does not affect Vault Lock, which has its own independent settings', () {
      fakeAsync((async) {
        // App Lock: screen-lock-only. Vault Lock: plain "Immediately".
        settings = appLockSettings();
        var fakeNow = DateTime(2024);
        now = () => fakeNow;
        buildController();

        controller.handleAppLifecycleState(AppLifecycleState.paused);
        fakeNow = fakeNow.add(const Duration(seconds: 1));
        async.elapse(const Duration(seconds: 1));
        controller.handleAppLifecycleState(AppLifecycleState.resumed);

        expect(enforceAppLockCalls, 0);
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